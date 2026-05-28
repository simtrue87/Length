// 사진 — 물고기 직선 길이 측정 (베타).
// 1) 설정(카드 mm) → 2) 카드 4점 보정(자동/수동) → 3) 물고기 bbox 드래그
// 4) GrabCut + minAreaRect로 양 끝점 자동, 사용자 미세 조정 → 결과.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/capture/capture_widget.dart';
import '../../../shared/dialogs/confirm_exit.dart';
import '../../../shared/permissions/camera_permission.dart';
import '../../../shared/sensors/tilt_warning.dart';
import '../../result/domain/measurement_result.dart';
import '../planar_rectifier.dart';
import '../presentation/widgets/draggable_handle.dart';
import '../reference_object/card_detector.dart';
import 'fish_detector.dart';

enum _Step { setup, calibrate, selectBbox, refine }

class PhotoFishScreen extends StatefulWidget {
  const PhotoFishScreen({super.key});

  @override
  State<PhotoFishScreen> createState() => _PhotoFishScreenState();
}

class _PhotoFishScreenState extends State<PhotoFishScreen> {
  final ImagePicker _picker = ImagePicker();
  final GlobalKey _captureKey = GlobalKey();
  final CardDetector _cardDetector = CardDetector();
  final FishDetector _fishDetector = FishDetector();

  _Step _step = _Step.setup;
  XFile? _image;
  double? _imageAspect;
  int _imageWidthPx = 0;
  int _imageHeightPx = 0;

  static const double _cardWidthMm = 85.6; // 신용카드 가로.

  // 카드 4점 (위젯 좌표).
  List<Offset>? _cardCorners;
  List<Offset>? _pendingCardImagePx;
  bool _cardAuto = false;
  String? _calibStatus;

  // 물고기 bbox (위젯 좌표).
  Offset? _bboxStart;
  Offset? _bboxEnd;

  // 자동 검출 끝점 (위젯 좌표).
  Offset? _endpointA;
  Offset? _endpointB;
  bool _fishAuto = false;
  String? _detectStatus;

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
      final dims = await _readDims(File(x.path));
      setState(() {
        _image = x;
        _imageAspect = dims.width / dims.height;
        _imageWidthPx = dims.width;
        _imageHeightPx = dims.height;
        _step = _Step.calibrate;
        _cardCorners = null;
        _pendingCardImagePx = null;
        _cardAuto = false;
        _calibStatus = '카드 자동 감지 중...';
        _bboxStart = null;
        _bboxEnd = null;
        _endpointA = null;
        _endpointB = null;
        _fishAuto = false;
        _detectStatus = null;
      });
      final det = await _cardDetector.detect(x.path);
      if (!mounted) return;
      if (det == null) {
        setState(() => _calibStatus = '카드 자동 감지 실패 — 4점을 수동으로 맞추세요.');
      } else {
        setState(() {
          _pendingCardImagePx = det.cornersImagePx;
          _cardAuto = true;
          _calibStatus = '카드 감지됨 — 필요 시 미세 조정하세요.';
        });
      }
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

  void _materializeCardCorners(Size area) {
    if (_pendingCardImagePx == null) return;
    final sx = area.width / _imageWidthPx;
    final sy = area.height / _imageHeightPx;
    _cardCorners = _pendingCardImagePx!
        .map((p) => Offset(p.dx * sx, p.dy * sy))
        .toList();
    _pendingCardImagePx = null;
  }

  void _initCardFallback(Size area) {
    const cardAspect = 85.6 / 53.98;
    final w = area.width * 0.6;
    final h = w / cardAspect;
    final cx = area.width / 2;
    final cy = area.height / 2;
    _cardCorners = [
      Offset(cx - w / 2, cy - h / 2),
      Offset(cx + w / 2, cy - h / 2),
      Offset(cx + w / 2, cy + h / 2),
      Offset(cx - w / 2, cy + h / 2),
    ];
  }

  PlanarRectifier? _buildRectifier() {
    final c = _cardCorners;
    if (c == null) return null;
    return PlanarRectifier.fromCorners(
      cornersWidgetPx: c,
      widthMm: _cardWidthMm,
      heightMm: 53.98,
    );
  }

  Future<void> _runFishDetection(Size area) async {
    if (_bboxStart == null || _bboxEnd == null) return;
    final l = math.min(_bboxStart!.dx, _bboxEnd!.dx);
    final t = math.min(_bboxStart!.dy, _bboxEnd!.dy);
    final r = math.max(_bboxStart!.dx, _bboxEnd!.dx);
    final b = math.max(_bboxStart!.dy, _bboxEnd!.dy);
    final widgetRect = Rect.fromLTRB(l, t, r, b);
    if (widgetRect.width < 10 || widgetRect.height < 10) {
      setState(() => _detectStatus = '박스가 너무 작습니다. 다시 그려주세요.');
      return;
    }
    setState(() => _detectStatus = '물고기 자동 검출 중...');

    final sx = _imageWidthPx / area.width;
    final sy = _imageHeightPx / area.height;
    final imageRect = Rect.fromLTRB(
      widgetRect.left * sx,
      widgetRect.top * sy,
      widgetRect.right * sx,
      widgetRect.bottom * sy,
    );

    final det = await _fishDetector.detect(
      imagePath: _image!.path,
      bboxImagePx: imageRect,
    );
    if (!mounted) return;
    if (det == null) {
      setState(() {
        _endpointA = widgetRect.topLeft;
        _endpointB = widgetRect.bottomRight;
        _fishAuto = false;
        _detectStatus = '자동 검출 실패 — 양 끝점을 수동으로 맞추세요.';
        _step = _Step.refine;
      });
      return;
    }
    // 이미지 픽셀 → 위젯 좌표.
    final invSx = area.width / _imageWidthPx;
    final invSy = area.height / _imageHeightPx;
    setState(() {
      _endpointA = Offset(
          det.endpointAImagePx.dx * invSx, det.endpointAImagePx.dy * invSy);
      _endpointB = Offset(
          det.endpointBImagePx.dx * invSx, det.endpointBImagePx.dy * invSy);
      _fishAuto = true;
      _detectStatus = '자동 검출 완료 — 필요 시 끝점을 끌어 보정하세요.';
      _step = _Step.refine;
    });
  }

  Future<void> _confirm() async {
    final rect = _buildRectifier();
    if (rect == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('스케일 계산에 실패했습니다. 카드 4점을 다시 확인해주세요.')),
      );
      return;
    }
    final imagePath = await captureBoundaryAsPng(_captureKey);
    final mm = rect.distanceMm(_endpointA!, _endpointB!);
    final auto = _fishAuto && _cardAuto;
    final result = MeasurementResult(
      kind: MeasureKind.distance,
      value: mm,
      modeLabel: '사진 — 물고기 (베타)',
      confidence:
          auto ? MeasurementConfidence.high : MeasurementConfidence.medium,
      note:
          '${_fishAuto ? '자동 검출' : '수동 끝점'} + ${_cardAuto ? '카드 자동' : '카드 수동'} + 호모그래피 (직선)',
      imagePath: imagePath,
    );
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
        appBar: AppBar(title: const Text('물고기 측정 (베타)')),
        body: TiltWarning(
          child: switch (_step) {
            _Step.setup => _buildSetupView(),
            _Step.calibrate => _buildCalibrateView(),
            _Step.selectBbox => _buildBboxView(),
            _Step.refine => _buildRefineView(),
          },
        ),
      ),
    );
  }

  Widget _buildSetupView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '물고기 옆에 신용카드를 같은 평면으로 두고 위에서 수직으로 촬영하세요. '
              '카드는 자동으로 감지하고, 물고기는 박스를 한 번 그리면 양 끝점을 자동 추출합니다.',
              textAlign: TextAlign.center,
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
      ),
    );
  }

  Widget _buildCalibrateView() {
    return _imageStage(
      instructions: _calibStatus ?? '카드 4점을 확인하세요.',
      buildOverlay: (area) {
        if (_cardCorners == null) {
          if (_pendingCardImagePx != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _materializeCardCorners(area));
            });
          } else if (_calibStatus != null && _calibStatus!.contains('실패')) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _initCardFallback(area));
            });
          }
          return const SizedBox.shrink();
        }
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _QuadPainter(_cardCorners!,
                    color: Theme.of(context).colorScheme.primary, closed: true),
              ),
            ),
            for (var i = 0; i < 4; i++)
              DraggableHandle(
                position: _cardCorners![i],
                label: '${i + 1}',
                onDrag: (p) => setState(() {
                  _cardCorners![i] = Offset(
                    p.dx.clamp(0, area.width),
                    p.dy.clamp(0, area.height),
                  );
                }),
              ),
          ],
        );
      },
      primaryAction: _cardCorners == null
          ? null
          : () => setState(() => _step = _Step.selectBbox),
      primaryLabel: '다음 (물고기 선택)',
    );
  }

  Widget _buildBboxView() {
    return _imageStage(
      instructions: '물고기를 감싸는 사각형을 그려주세요. 시작점 → 끝점.',
      buildOverlay: (a) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => setState(() {
            _bboxStart = _clamp(d.localPosition, a);
            _bboxEnd = _bboxStart;
          }),
          onPanUpdate: (d) => setState(() {
            _bboxEnd = _clamp(d.localPosition, a);
          }),
          child: Stack(
            children: [
              if (_cardCorners != null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _QuadPainter(_cardCorners!,
                        color: Theme.of(context).colorScheme.primary,
                        closed: true),
                  ),
                ),
              if (_bboxStart != null && _bboxEnd != null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BboxPainter(_bboxStart!, _bboxEnd!,
                        Theme.of(context).colorScheme.secondary),
                  ),
                ),
            ],
          ),
        );
      },
      primaryAction: (_bboxStart != null && _bboxEnd != null)
          ? _runFishDetectionFromCurrent
          : null,
      primaryLabel: '검출',
    );
  }

  void _runFishDetectionFromCurrent() {
    final box = _captureKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _runFishDetection(box.size);
  }

  Widget _buildRefineView() {
    final color = Theme.of(context).colorScheme.secondary;
    return _imageStage(
      instructions: _detectStatus ?? '양 끝점을 확인하세요.',
      buildOverlay: (area) {
        return Stack(
          children: [
            if (_cardCorners != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: _QuadPainter(_cardCorners!,
                      color: Theme.of(context).colorScheme.primary,
                      closed: true),
                ),
              ),
            if (_endpointA != null && _endpointB != null) ...[
              Positioned.fill(
                child: CustomPaint(
                  painter:
                      _LinePainter(_endpointA!, _endpointB!, color),
                ),
              ),
              DraggableHandle(
                position: _endpointA!,
                color: color,
                label: 'A',
                onDrag: (p) => setState(() => _endpointA = _clamp(p, area)),
              ),
              DraggableHandle(
                position: _endpointB!,
                color: color,
                label: 'B',
                onDrag: (p) => setState(() => _endpointB = _clamp(p, area)),
              ),
            ],
          ],
        );
      },
      primaryAction:
          (_endpointA != null && _endpointB != null) ? _confirm : null,
      primaryLabel: '측정',
      secondary: OutlinedButton.icon(
        onPressed: () => setState(() {
          _step = _Step.selectBbox;
          _endpointA = null;
          _endpointB = null;
          _fishAuto = false;
        }),
        icon: const Icon(Icons.crop_free),
        label: const Text('박스 다시 그리기'),
      ),
    );
  }

  Offset _clamp(Offset p, Size area) => Offset(
        p.dx.clamp(0, area.width),
        p.dy.clamp(0, area.height),
      );

  Widget _imageStage({
    required String instructions,
    required Widget Function(Size area) buildOverlay,
    required VoidCallback? primaryAction,
    required String primaryLabel,
    Widget? secondary,
  }) {
    final aspect = _imageAspect ?? 1.0;
    return Column(
      children: [
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
                          child:
                              Image.file(File(_image!.path), fit: BoxFit.fill),
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
                        _cardCorners = null;
                        _pendingCardImagePx = null;
                        _bboxStart = null;
                        _bboxEnd = null;
                        _endpointA = null;
                        _endpointB = null;
                        _detectStatus = null;
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

class _LinePainter extends CustomPainter {
  _LinePainter(this.a, this.b, this.color);
  final Offset a;
  final Offset b;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = color
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.a != a || old.b != b || old.color != color;
}

class _BboxPainter extends CustomPainter {
  _BboxPainter(this.start, this.end, this.color);
  final Offset start;
  final Offset end;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromPoints(start, end),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_BboxPainter old) =>
      old.start != start || old.end != end || old.color != color;
}
