// 사진 — QR 마커 측정 모드. 사용자가 QR 한 변 길이(mm)를 입력하면 자동으로 4점 보정.
// 1) 설정(한 변 mm) + 이미지 선택 → 2) QR 감지·4점 표시(편집 가능) → 3) N점 측정.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/settings/measurement_prefs.dart';
import '../../../shared/capture/capture_widget.dart';
import '../../../shared/dialogs/confirm_exit.dart';
import '../../../shared/permissions/camera_permission.dart';
import '../../../shared/sensors/tilt_warning.dart';
import '../../result/domain/measurement_result.dart';
import '../planar_rectifier.dart';
import '../presentation/widgets/draggable_handle.dart';
import 'marker_detector.dart';

enum _Step { setup, calibrate, measure }

class PhotoMarkerScreen extends ConsumerStatefulWidget {
  const PhotoMarkerScreen({super.key});

  @override
  ConsumerState<PhotoMarkerScreen> createState() => _PhotoMarkerScreenState();
}

class _PhotoMarkerScreenState extends ConsumerState<PhotoMarkerScreen> {
  final ImagePicker _picker = ImagePicker();
  final GlobalKey _captureKey = GlobalKey();
  final MarkerDetector _detector = MarkerDetector();
  final TextEditingController _sizeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final side = await ref.read(markerSideMmProvider.future);
    if (!mounted) return;
    setState(() {
      _sizeCtrl.text = side.toStringAsFixed(0);
      _markerSideMm = side;
    });
  }

  _Step _step = _Step.setup;
  XFile? _image;
  double? _imageAspect;
  int _imageWidthPx = 0;
  int _imageHeightPx = 0;
  double _markerSideMm = 50;
  String? _qrValue;
  String? _detectionStatus;

  /// 위젯 좌표계 4점 (TL, TR, BR, BL).
  List<Offset>? _markerCorners;

  MeasureKind _kind = MeasureKind.distance;
  final List<Offset> _points = [];

  @override
  void dispose() {
    _detector.dispose();
    _sizeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final s = double.tryParse(_sizeCtrl.text);
    if (s == null || s <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('마커 한 변 길이를 mm 단위로 입력하세요.')),
      );
      return;
    }
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
      final dims = await _readDims(File(x.path));
      await ref.read(markerSideMmProvider.notifier).save(s);
      if (!mounted) return;
      setState(() {
        _image = x;
        _imageAspect = dims.width / dims.height;
        _imageWidthPx = dims.width;
        _imageHeightPx = dims.height;
        _markerSideMm = s;
        _step = _Step.calibrate;
        _markerCorners = null;
        _qrValue = null;
        _detectionStatus = '마커 감지 중...';
        _points.clear();
      });
      await _detect(x.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('이미지를 불러오지 못했습니다: $e')));
    }
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

  Future<void> _detect(String path) async {
    try {
      final det = await _detector.detectInImage(path);
      if (!mounted) return;
      if (det == null) {
        setState(() => _detectionStatus = '마커를 찾지 못했습니다. 4점을 수동으로 맞추세요.');
        return;
      }
      setState(() {
        _qrValue = det.rawValue;
        _detectionStatus = '감지됨${det.rawValue != null ? ' — "${det.rawValue}"' : ''}';
      });
      // 영상-위젯 매핑은 LayoutBuilder에서 area 알게 된 후 변환.
      _pendingImageCorners = det.cornersImagePx;
    } catch (e) {
      if (!mounted) return;
      setState(() => _detectionStatus = '감지 오류: $e. 수동으로 맞추세요.');
    }
  }

  List<Offset>? _pendingImageCorners;

  void _materializeCorners(Size area) {
    if (_pendingImageCorners == null) return;
    final sx = area.width / _imageWidthPx;
    final sy = area.height / _imageHeightPx;
    _markerCorners = _pendingImageCorners!
        .map((p) => Offset(p.dx * sx, p.dy * sy))
        .toList();
    _pendingImageCorners = null;
  }

  void _initFallbackCorners(Size area) {
    final boxW = area.width * 0.4;
    final cx = area.width / 2;
    final cy = area.height / 2;
    _markerCorners = [
      Offset(cx - boxW / 2, cy - boxW / 2),
      Offset(cx + boxW / 2, cy - boxW / 2),
      Offset(cx + boxW / 2, cy + boxW / 2),
      Offset(cx - boxW / 2, cy + boxW / 2),
    ];
  }

  PlanarRectifier? _buildRectifier() {
    final c = _markerCorners;
    if (c == null) return null;
    return PlanarRectifier.fromCorners(
      cornersWidgetPx: c,
      widthMm: _markerSideMm,
      heightMm: _markerSideMm,
    );
  }

  int? _maxPointsFor(MeasureKind k) => switch (k) {
        MeasureKind.distance => 2,
        MeasureKind.angle => 3,
        MeasureKind.perimeter || MeasureKind.area => null,
      };

  bool _canConfirm() {
    switch (_kind) {
      case MeasureKind.distance:
        return _points.length == 2;
      case MeasureKind.perimeter:
        return _points.length >= 2;
      case MeasureKind.area:
        return _points.length >= 3;
      case MeasureKind.angle:
        return _points.length == 3;
    }
  }

  void _onTapAdd(Offset local) {
    setState(() {
      final max = _maxPointsFor(_kind);
      if (max != null && _points.length >= max) {
        _points
          ..clear()
          ..add(local);
      } else {
        _points.add(local);
      }
    });
  }

  Future<void> _confirm() async {
    final rect = _buildRectifier();
    if (rect == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('스케일 계산에 실패했습니다. 4점을 다시 확인해주세요.')),
      );
      return;
    }
    final imagePath = await captureBoundaryAsPng(_captureKey);
    final modeLabel = _qrValue != null
        ? '사진 — QR (${_markerSideMm.toStringAsFixed(0)}mm)'
        : '사진 — 마커 (${_markerSideMm.toStringAsFixed(0)}mm)';
    final confidence = _qrValue != null
        ? MeasurementConfidence.high
        : MeasurementConfidence.medium;
    final calibNote =
        '${_qrValue != null ? 'QR 자동' : '수동'} 4점 + 호모그래피';
    late MeasurementResult result;
    switch (_kind) {
      case MeasureKind.distance:
        result = MeasurementResult(
          kind: MeasureKind.distance,
          value: rect.distanceMm(_points[0], _points[1]),
          modeLabel: modeLabel,
          confidence: confidence,
          note: calibNote,
          imagePath: imagePath,
        );
      case MeasureKind.perimeter:
        result = MeasurementResult(
          kind: MeasureKind.perimeter,
          value: rect.polylineLengthMm(_points),
          modeLabel: modeLabel,
          confidence: confidence,
          note: '폴리라인 ${_points.length}점',
          imagePath: imagePath,
        );
      case MeasureKind.area:
        result = MeasurementResult(
          kind: MeasureKind.area,
          value: rect.polygonAreaMm2(_points),
          modeLabel: modeLabel,
          confidence: confidence,
          note: '폴리곤 ${_points.length}점',
          imagePath: imagePath,
        );
      case MeasureKind.angle:
        result = MeasurementResult(
          kind: MeasureKind.angle,
          value: rect.angleAtVertexDegrees(
              _points[0], _points[1], _points[2]),
          modeLabel: modeLabel,
          confidence: confidence,
          note: '중간 점이 꼭짓점',
          imagePath: imagePath,
        );
    }
    if (!mounted) return;
    context.go('/result', extra: result);
  }

  @override
  Widget build(BuildContext context) {
    final inProgress = _step != _Step.setup;
    return PopScope(
      canPop: !inProgress,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmExitMeasurement(context) && mounted) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('QR/마커 측정')),
        body: TiltWarning(
          child: switch (_step) {
            _Step.setup => _buildSetupView(),
            _Step.calibrate => _buildCalibrateView(),
            _Step.measure => _buildMeasureView(),
          },
        ),
      ),
    );
  }

  Widget _buildSetupView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'QR 코드를 측정 대상 옆에 같은 평면으로 두고 촬영하세요. '
            'QR의 한 변 실제 길이(mm)를 입력하면 자동으로 4점 보정이 됩니다.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _sizeCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'QR 한 변 (mm)',
              helperText: '인쇄한 QR의 한 변 실측값.',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.camera_alt),
            onPressed: () => _pick(ImageSource.camera),
            label: const Text('촬영'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.photo_library),
            onPressed: () => _pick(ImageSource.gallery),
            label: const Text('갤러리에서 선택'),
          ),
        ],
      ),
    );
  }

  Widget _buildCalibrateView() {
    return _imageStage(
      instructions: _detectionStatus ?? '',
      buildOverlay: (area) {
        if (_markerCorners == null) {
          if (_pendingImageCorners != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _materializeCorners(area));
            });
          } else if (_detectionStatus != null &&
              _detectionStatus!.contains('수동')) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _initFallbackCorners(area));
            });
          }
          return const SizedBox.shrink();
        }
        return _buildCornerHandles(area);
      },
      primaryAction: _markerCorners == null
          ? null
          : () => setState(() => _step = _Step.measure),
      primaryLabel: '다음',
    );
  }

  Widget _buildMeasureView() {
    return _imageStage(
      header: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: MeasureKind.values.map((k) {
            return ChoiceChip(
              label: Text(k.label),
              selected: _kind == k,
              onSelected: (_) => setState(() {
                _kind = k;
                _points.clear();
              }),
            );
          }).toList(),
        ),
      ),
      instructions: _measureInstruction(),
      buildOverlay: _buildMeasureOverlay,
      secondary: OutlinedButton.icon(
        onPressed: _points.isEmpty ? null : () => setState(_points.removeLast),
        icon: const Icon(Icons.undo),
        label: const Text('실행 취소'),
      ),
      primaryAction: _canConfirm() ? _confirm : null,
      primaryLabel: '측정',
    );
  }

  Widget _imageStage({
    required String instructions,
    required Widget Function(Size area) buildOverlay,
    required VoidCallback? primaryAction,
    required String primaryLabel,
    Widget? header,
    Widget? secondary,
  }) {
    final aspect = _imageAspect ?? 1.0;
    return Column(
      children: [
        if (header != null) Padding(padding: const EdgeInsets.only(top: 8), child: header),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(instructions, textAlign: TextAlign.center),
        ),
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
                        if (_markerCorners != null)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _QuadPainter(_markerCorners!,
                                  color: Theme.of(context).colorScheme.primary,
                                  closed: true),
                            ),
                          ),
                        buildOverlay(area),
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
          child: Column(
            children: [
              if (secondary != null) ...[
                SizedBox(width: double.infinity, child: secondary),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        _step = _Step.setup;
                        _image = null;
                        _markerCorners = null;
                        _pendingImageCorners = null;
                        _qrValue = null;
                        _detectionStatus = null;
                        _points.clear();
                      }),
                      child: const Text('처음으로'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: primaryAction,
                      child: Text(primaryLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCornerHandles(Size area) {
    return Stack(
      children: [
        for (var i = 0; i < 4; i++)
          DraggableHandle(
            position: _markerCorners![i],
            label: '${i + 1}',
            onDrag: (p) => setState(() {
              _markerCorners![i] = Offset(
                p.dx.clamp(0, area.width),
                p.dy.clamp(0, area.height),
              );
            }),
          ),
      ],
    );
  }

  Widget _buildMeasureOverlay(Size area) {
    final color = Theme.of(context).colorScheme.secondary;
    return GestureDetector(
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
          if (_points.length >= 2)
            Positioned.fill(
              child: CustomPaint(
                painter: _QuadPainter(_points,
                    color: color, closed: _kind == MeasureKind.area),
              ),
            ),
          for (var i = 0; i < _points.length; i++)
            DraggableHandle(
              position: _points[i],
              color: color,
              label: '${i + 1}',
              onDrag: (p) => setState(() {
                _points[i] = Offset(
                  p.dx.clamp(0, area.width),
                  p.dy.clamp(0, area.height),
                );
              }),
            ),
        ],
      ),
    );
  }

  String _measureInstruction() => switch (_kind) {
        MeasureKind.distance => '대상의 두 점을 탭하세요.',
        MeasureKind.perimeter => '둘레를 따라 점을 차례로 탭하세요 (최소 2점).',
        MeasureKind.area => '도형 꼭짓점을 차례로 탭하세요 (최소 3점, 자동으로 닫힘).',
        MeasureKind.angle => '꼭짓점을 가운데로 세 점을 차례로 탭하세요.',
      };

  bool _isOnHandle(Offset p) {
    const r = 20.0;
    for (final pt in _points) {
      if ((p - pt).distance < r) return true;
    }
    return false;
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter(this.points, {required this.color, this.closed = false});
  final List<Offset> points;
  final Color color;
  final bool closed;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    if (closed && points.length >= 3) path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_QuadPainter old) =>
      old.points != points || old.color != color || old.closed != closed;
}
