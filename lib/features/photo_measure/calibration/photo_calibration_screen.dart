// 사진 — 캘리브레이션 모드. 평면 위에서 단말을 평행하게 두고 수직 촬영.
// 입력: 카메라 높이(mm) + 세로 FOV(° 기본 60) + 이미지. 점 N개 탭으로 측정.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/measurement/measurement_engine.dart';
import '../../../core/settings/measurement_prefs.dart';
import '../../../shared/capture/capture_widget.dart';
import '../../../shared/dialogs/confirm_exit.dart';
import '../../../shared/permissions/camera_permission.dart';
import '../../../shared/sensors/tilt_warning.dart';
import '../../result/domain/measurement_result.dart';
import '../presentation/widgets/draggable_handle.dart';

enum _Step { setup, measure }

class PhotoCalibrationScreen extends ConsumerStatefulWidget {
  const PhotoCalibrationScreen({super.key});

  @override
  ConsumerState<PhotoCalibrationScreen> createState() =>
      _PhotoCalibrationScreenState();
}

class _PhotoCalibrationScreenState extends ConsumerState<PhotoCalibrationScreen> {
  final ImagePicker _picker = ImagePicker();
  final GlobalKey _captureKey = GlobalKey();
  final TextEditingController _heightCtrl = TextEditingController();
  final TextEditingController _fovCtrl = TextEditingController();

  _Step _step = _Step.setup;
  XFile? _image;
  double? _imageAspect;
  double _heightMm = 300;
  double _fovDegrees = 60;

  MeasureKind _kind = MeasureKind.distance;
  final List<Offset> _points = [];

  StreamSubscription<AccelerometerEvent>? _accelSub;
  double _currentTilt = 0;

  @override
  void initState() {
    super.initState();
    _accelSub = accelerometerEventStream().listen((e) {
      final tilt = tiltDegreesFromAccel(e.z);
      if ((_currentTilt - tilt).abs() > 1) {
        setState(() => _currentTilt = tilt);
      }
    });
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await ref.read(calibrationPrefsProvider.future);
    if (!mounted) return;
    setState(() {
      _heightCtrl.text = prefs.heightMm.toStringAsFixed(0);
      _fovCtrl.text = prefs.fovDegrees.toStringAsFixed(0);
      _heightMm = prefs.heightMm;
      _fovDegrees = prefs.fovDegrees;
    });
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _heightCtrl.dispose();
    _fovCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final h = double.tryParse(_heightCtrl.text);
    final f = double.tryParse(_fovCtrl.text);
    if (h == null || h <= 0 || f == null || f <= 0 || f >= 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('높이(>0)와 FOV(0~180°)를 확인하세요.')),
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
      final aspect = await _readAspectRatio(File(x.path));
      await ref
          .read(calibrationPrefsProvider.notifier)
          .save(heightMm: h, fovDegrees: f);
      if (!mounted) return;
      setState(() {
        _image = x;
        _imageAspect = aspect;
        _heightMm = h;
        _fovDegrees = f;
        _step = _Step.measure;
        _points.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('이미지를 불러오지 못했습니다: $e')));
    }
  }

  Future<double> _readAspectRatio(File file) async {
    final completer = Completer<double>();
    final stream = Image.file(file).image.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      completer.complete(info.image.width / info.image.height);
      stream.removeListener(listener);
    });
    stream.addListener(listener);
    return completer.future;
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

  Future<void> _confirmMeasurement(Size area) async {
    final imagePath = await captureBoundaryAsPng(_captureKey);
    final mmPerPx = MeasurementEngine.computeMmPerPixelFromHeight(
      heightMm: _heightMm,
      verticalFovDegrees: _fovDegrees,
      widgetHeightPx: area.height,
    );
    final tiltNote = _currentTilt > 10
        ? '기울기 ${_currentTilt.toStringAsFixed(0)}° — 신뢰도 낮음'
        : null;
    final confidence = _currentTilt > 20
        ? MeasurementConfidence.low
        : MeasurementConfidence.medium;
    late MeasurementResult result;
    switch (_kind) {
      case MeasureKind.distance:
        final px = MeasurementEngine.distance2D(_points[0], _points[1]);
        result = MeasurementResult(
          kind: MeasureKind.distance,
          value: MeasurementEngine.pixelToMm(
              pixelDistance: px, mmPerPixel: mmPerPx),
          modeLabel: '사진 — 캘리브레이션 (h=${_heightMm.toStringAsFixed(0)}mm)',
          confidence: confidence,
          note: tiltNote ?? 'FOV ${_fovDegrees.toStringAsFixed(0)}°',
          imagePath: imagePath,
        );
      case MeasureKind.perimeter:
        final px = MeasurementEngine.polylineLengthPx(_points);
        result = MeasurementResult(
          kind: MeasureKind.perimeter,
          value: MeasurementEngine.pixelToMm(
              pixelDistance: px, mmPerPixel: mmPerPx),
          modeLabel: '사진 — 캘리브레이션 (h=${_heightMm.toStringAsFixed(0)}mm)',
          confidence: confidence,
          note: tiltNote ?? '폴리라인 ${_points.length}점',
          imagePath: imagePath,
        );
      case MeasureKind.area:
        final px2 = MeasurementEngine.polygonAreaPx2(_points);
        result = MeasurementResult(
          kind: MeasureKind.area,
          value: MeasurementEngine.pixelArea2ToMm2(
              pixelArea: px2, mmPerPixel: mmPerPx),
          modeLabel: '사진 — 캘리브레이션 (h=${_heightMm.toStringAsFixed(0)}mm)',
          confidence: confidence,
          note: tiltNote ?? '폴리곤 ${_points.length}점',
          imagePath: imagePath,
        );
      case MeasureKind.angle:
        // 각도는 평면 가정에서 스케일과 무관.
        final deg = MeasurementEngine.angleAtVertexDegrees(
            _points[0], _points[1], _points[2]);
        result = MeasurementResult(
          kind: MeasureKind.angle,
          value: deg,
          modeLabel: '사진 — 캘리브레이션',
          confidence: confidence,
          note: tiltNote ?? '중간 점이 꼭짓점',
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
        appBar: AppBar(title: const Text('캘리브레이션 + 평면 가정')),
        body: TiltWarning(
          child: switch (_step) {
            _Step.setup => _buildSetupView(),
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
            '단말을 평면(바닥/테이블)과 평행하게 들고 위에서 수직으로 촬영하세요. '
            '기울기가 크면 오차가 큽니다.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _heightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '카메라 높이 (mm)',
              helperText: '바닥/테이블에서 카메라까지의 수직 거리.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fovCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '세로 시야각 FOV (°)',
              helperText: '기본 60°. 단말 사양 확인 가능.',
            ),
          ),
          const SizedBox(height: 24),
          Card(
            color: _currentTilt > 10
                ? Theme.of(context).colorScheme.errorContainer
                : Theme.of(context).colorScheme.surfaceContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.screen_rotation_alt),
                  const SizedBox(width: 8),
                  Text('현재 기울기: ${_currentTilt.toStringAsFixed(0)}°'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
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

  Widget _buildMeasureView() {
    final aspect = _imageAspect ?? 1.0;
    final color = Theme.of(context).colorScheme.secondary;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(_measureInstruction(), textAlign: TextAlign.center),
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
                              if (_points.length >= 2)
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _PointsPainter(_points,
                                        color: color,
                                        closed: _kind == MeasureKind.area),
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
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _points.isEmpty
                      ? null
                      : () => setState(_points.removeLast),
                  icon: const Icon(Icons.undo),
                  label: const Text('실행 취소'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        _step = _Step.setup;
                        _image = null;
                        _points.clear();
                      }),
                      child: const Text('처음으로'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, _) {
                        // 측정 영역의 actual size는 AspectRatio에서 결정됨.
                        // confirm 시 다시 LayoutBuilder로 area 얻어 호출.
                        return FilledButton(
                          onPressed: _canConfirm()
                              ? () => _confirmFromCurrentArea()
                              : null,
                          child: const Text('측정'),
                        );
                      },
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

  void _confirmFromCurrentArea() {
    final ctx = _captureKey.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _confirmMeasurement(box.size);
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

class _PointsPainter extends CustomPainter {
  _PointsPainter(this.points, {required this.color, this.closed = false});
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
  bool shouldRepaint(_PointsPainter old) =>
      old.points != points || old.color != color || old.closed != closed;
}
