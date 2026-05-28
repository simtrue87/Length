// 사진 — AI 깊이 추정 모드 (베타). EXIF focal + DepthEstimator → 두 점 탭 → 3D 거리.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/camera/camera_intrinsics.dart';
import '../../../../core/measurement/measurement_engine.dart';
import '../../../../shared/capture/capture_widget.dart';
import '../../../../shared/dialogs/confirm_exit.dart';
import '../../../../shared/permissions/camera_permission.dart';
import '../../../result/domain/measurement_result.dart';
import '../../presentation/widgets/draggable_handle.dart';
import '../domain/depth_estimator.dart';
import '../infrastructure/depth_estimator_factory.dart';
import '../infrastructure/exif_focal_reader.dart';

enum _Step { pickImage, processing, measure }

class PhotoAiDepthScreen extends StatefulWidget {
  const PhotoAiDepthScreen({super.key});

  @override
  State<PhotoAiDepthScreen> createState() => _PhotoAiDepthScreenState();
}

class _PhotoAiDepthScreenState extends State<PhotoAiDepthScreen> {
  final ImagePicker _picker = ImagePicker();
  final GlobalKey _captureKey = GlobalKey();

  DepthEstimator? _estimator;
  bool _estimatorIsReal = false;

  _Step _step = _Step.pickImage;
  XFile? _image;
  double? _imageAspect;
  int _imageWidthPx = 0;
  int _imageHeightPx = 0;
  CameraIntrinsics? _intrinsics;
  DepthMap? _depthMap;
  String? _depthSource;

  Offset? _pointA;
  Offset? _pointB;

  @override
  void initState() {
    super.initState();
    _initEstimator();
  }

  Future<void> _initEstimator() async {
    final res = await resolveDepthEstimator();
    if (!mounted) return;
    setState(() {
      _estimator = res.estimator;
      _estimatorIsReal = res.isReal;
    });
  }

  Future<void> _pick(ImageSource source) async {
    if (source == ImageSource.camera) {
      final perm = await ensureCameraPermission(context);
      if (!perm.allowed) {
        if (!mounted || perm.message == null) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(perm.message!)));
        return;
      }
    }
    try {
      final x = await _picker.pickImage(source: source, maxWidth: 4000);
      if (x == null) return;
      setState(() {
        _image = x;
        _step = _Step.processing;
        _pointA = null;
        _pointB = null;
      });
      await _loadAndEstimate(File(x.path));
    } catch (e) {
      if (!mounted) return;
      setState(() => _step = _Step.pickImage);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('처리 실패: $e')));
    }
  }

  Future<void> _loadAndEstimate(File file) async {
    final est = _estimator;
    if (est == null) {
      throw StateError('깊이 추정기가 아직 준비되지 않았습니다.');
    }
    final dims = await _readDims(file);
    final focal = await readFocal35mm(file);
    final depthMap = await est.estimate(file.path);
    final intrinsics = CameraIntrinsics.fromFocal35mm(
      focal35mm: focal.focal35mm,
      imageWidthPx: dims.width,
      imageHeightPx: dims.height,
    );
    if (!mounted) return;
    setState(() {
      _imageAspect = dims.width / dims.height;
      _imageWidthPx = dims.width;
      _imageHeightPx = dims.height;
      _intrinsics = intrinsics;
      _depthMap = depthMap;
      _depthSource = focal.isFallback
          ? 'EXIF 없음 — 기본 ${focal.focal35mm.toStringAsFixed(0)}mm 환산 사용'
          : 'EXIF ${focal.focal35mm.toStringAsFixed(0)}mm 환산';
      _step = _Step.measure;
    });
  }

  Future<({int width, int height})> _readDims(File file) async {
    final completer = Completer<({int width, int height})>();
    final stream = Image.file(file).image.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      completer.complete((width: info.image.width, height: info.image.height));
      stream.removeListener(listener);
    });
    stream.addListener(listener);
    return completer.future;
  }

  void _onTapAdd(Offset local) {
    setState(() {
      if (_pointA == null) {
        _pointA = local;
      } else if (_pointB == null) {
        _pointB = local;
      } else {
        _pointA = local;
        _pointB = null;
      }
    });
  }

  Future<void> _confirm(Size area) async {
    final imagePath = await captureBoundaryAsPng(_captureKey);
    final k = _intrinsics!;
    final depth = _depthMap!;
    final scaleX = _imageWidthPx / area.width;
    final scaleY = _imageHeightPx / area.height;

    double depthAt(Offset widgetPx) {
      final u = (widgetPx.dx * scaleX).round();
      final v = (widgetPx.dy * scaleY).round();
      final du = (u / _imageWidthPx * depth.width).round();
      final dv = (v / _imageHeightPx * depth.height).round();
      return depth.depthAtPixel(du, dv);
    }

    final pa = _pointA!;
    final pb = _pointB!;
    final p3a = unproject(
      u: pa.dx * scaleX,
      v: pa.dy * scaleY,
      depth: depthAt(pa),
      intrinsics: k,
    );
    final p3b = unproject(
      u: pb.dx * scaleX,
      v: pb.dy * scaleY,
      depth: depthAt(pb),
      intrinsics: k,
    );
    final mm = MeasurementEngine.distance3D(p3a, p3b);

    final relativeNote = _estimatorIsReal
        ? '⚠ 상대 깊이(Depth Anything V2) — 절대 mm 보정 미적용. 참고용. ${_depthSource ?? ''}'
        : '⚠ 상대 깊이(스텁) — 모델 미배포. ${_depthSource ?? ''}';
    final result = MeasurementResult(
      kind: MeasureKind.distance,
      value: mm,
      modeLabel: _estimatorIsReal ? '사진 — AI 깊이' : '사진 — AI 깊이 (스텁)',
      confidence: depth.isMetric
          ? MeasurementConfidence.medium
          : MeasurementConfidence.low,
      note: depth.isMetric ? _depthSource : relativeNote,
      imagePath: imagePath,
    );

    if (!mounted) return;
    context.go('/result', extra: result);
  }

  @override
  Widget build(BuildContext context) {
    final inProgress = _step != _Step.pickImage;
    return PopScope(
      canPop: !inProgress,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmExitMeasurement(context) && mounted) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(title: const Text('AI 깊이 추정 (베타)')),
      body: switch (_step) {
        _Step.pickImage => _buildPickView(),
        _Step.processing => const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('깊이 추정 중...'),
              ],
            ),
          ),
        _Step.measure => _buildMeasureView(),
      },
      ),
    );
  }

  Widget _buildPickView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '단안 깊이 모델로 사진 1장에서 거리를 추정합니다. '
              '${_estimator == null ? '깊이 추정기 준비 중...' : _estimatorIsReal ? 'Depth Anything V2 모델 로드 완료. 결과는 상대 깊이로 참고용입니다.' : '모델 미배포 — 스텁으로 흐름 검증. 신뢰도는 낮음.'}',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.camera_alt),
            onPressed: () => _pick(ImageSource.camera),
            label: const Text('촬영'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.photo_library),
            onPressed: () => _pick(ImageSource.gallery),
            label: const Text('갤러리에서 선택'),
          ),
        ],
      ),
    );
  }

  Widget _buildMeasureView() {
    final aspect = _imageAspect ?? 1.0;
    final color = Theme.of(context).colorScheme.secondary;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _depthSource ?? '',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('대상의 두 점을 탭하세요.', textAlign: TextAlign.center),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: aspect,
              child: LayoutBuilder(
                builder: (context, c) {
                  final area = Size(c.maxWidth, c.maxHeight);
                  return RepaintBoundary(
                    key: _captureKey,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.file(File(_image!.path), fit: BoxFit.fill),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (d) {
                            final clamped = Offset(
                              d.localPosition.dx.clamp(0, area.width),
                              d.localPosition.dy.clamp(0, area.height),
                            );
                            if (_isOnHandle(clamped)) return;
                            _onTapAdd(clamped);
                          },
                          child: Stack(
                            children: [
                              if (_pointA != null && _pointB != null)
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _LinePainter(
                                        _pointA!, _pointB!, color),
                                  ),
                                ),
                              if (_pointA != null)
                                DraggableHandle(
                                  position: _pointA!,
                                  color: color,
                                  label: 'A',
                                  onDrag: (p) => setState(() => _pointA = Offset(
                                        p.dx.clamp(0, area.width),
                                        p.dy.clamp(0, area.height),
                                      )),
                                ),
                              if (_pointB != null)
                                DraggableHandle(
                                  position: _pointB!,
                                  color: color,
                                  label: 'B',
                                  onDrag: (p) => setState(() => _pointB = Offset(
                                        p.dx.clamp(0, area.width),
                                        p.dy.clamp(0, area.height),
                                      )),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _step = _Step.pickImage;
                    _image = null;
                    _pointA = null;
                    _pointB = null;
                  }),
                  child: const Text('다시 선택'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: (_pointA != null && _pointB != null)
                      ? _confirmFromCurrentArea
                      : null,
                  child: const Text('측정'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _confirmFromCurrentArea() {
    final box = _captureKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _confirm(box.size);
  }

  bool _isOnHandle(Offset p) {
    const r = 20.0;
    if (_pointA != null && (p - _pointA!).distance < r) return true;
    if (_pointB != null && (p - _pointB!).distance < r) return true;
    return false;
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.a, this.b, this.color);
  final Offset a;
  final Offset b;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3;
    canvas.drawLine(a, b, paint);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.a != a || old.b != b || old.color != color;
}
