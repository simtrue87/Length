// 사진 기반 참조 객체 측정 화면.
// 1) 이미지 선택 → 2) 신용카드 4점 보정 → 3) 측정 종류 선택 + N점 입력 → 4) 결과.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/capture/capture_widget.dart';
import '../../../shared/dialogs/confirm_exit.dart';
import '../../../shared/permissions/camera_permission.dart';
import '../../../shared/sensors/tilt_warning.dart';
import '../../result/domain/measurement_result.dart';
import '../ml/yolo_length_detector.dart';
import '../planar_rectifier.dart';
import '../reference_object/card_detector.dart';
import '../reference_object/reference_object.dart';
import 'widgets/draggable_handle.dart';

enum _Step { pickImage, calibrate, measure }

class PhotoReferenceScreen extends StatefulWidget {
  const PhotoReferenceScreen({super.key});

  @override
  State<PhotoReferenceScreen> createState() => _PhotoReferenceScreenState();
}

class _PhotoReferenceScreenState extends State<PhotoReferenceScreen> {
  final ImagePicker _picker = ImagePicker();
  final ReferenceObject _reference = ReferenceObject.creditCard;
  final GlobalKey _captureKey = GlobalKey();
  final CardDetector _detector = CardDetector();

  /// YOLO 다중 클래스 검출기 — 모델 자산 있으면 카드 1차 검출에 활용. 없으면 null 폴백.
  YoloLengthDetector? _yolo;
  bool _yoloAttempted = false;

  _Step _step = _Step.pickImage;
  XFile? _image;
  double? _imageAspect;
  int _imageWidthPx = 0;
  int _imageHeightPx = 0;

  /// 위젯 좌표계(이미지 표시 영역 기준) 4점: TL, TR, BR, BL.
  List<Offset>? _refCorners;

  /// 자동 감지 결과(이미지 픽셀 좌표). LayoutBuilder에서 위젯 좌표로 변환 후 [_refCorners]에 저장.
  List<Offset>? _pendingImageCorners;
  bool _autoDetected = false;
  String? _detectionStatus;

  /// ROI 모드 — 사용자가 카드 영역을 박스로 지정한 뒤 그 안에서 재검출.
  bool _roiMode = false;
  Size? _imageStageArea; // 마지막 LayoutBuilder area (위젯↔이미지 좌표 변환용).

  /// 이미지 픽셀 좌표의 강한 코너 후보들 (스냅용).
  List<Offset> _cornerCandidates = const [];

  MeasureKind _kind = MeasureKind.distance;
  final List<Offset> _points = [];

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
        _refCorners = null;
        _pendingImageCorners = null;
        _autoDetected = false;
        _detectionStatus = '카드 자동 감지 중...';
        _points.clear();
      });
      // 코너 후보 미리 추출(스냅용).
      _detector.findCornerCandidates(x.path).then((pts) {
        debugPrint('[Snap] corner candidates: ${pts.length}');
        if (mounted) setState(() => _cornerCandidates = pts);
      });

      // 1차: YOLO 카드 검출.
      final yoloCard = await _runYoloCard(x.path);
      if (!mounted) return;
      if (yoloCard != null) {
        setState(() {
          _pendingImageCorners = yoloCard.cornersImagePx;
          _autoDetected = true;
          _detectionStatus = '자동 감지됨 (YOLO) — 필요 시 4점을 미세 조정하세요.';
        });
        return;
      }

      // 2차: 기존 CV CardDetector.
      final det = await _detector.detect(x.path);
      if (!mounted) return;
      if (det == null) {
        setState(() {
          _detectionStatus = '자동 감지 실패 — 4점을 수동으로 맞추세요.';
        });
      } else {
        setState(() {
          _pendingImageCorners = det.cornersImagePx;
          _autoDetected = true;
          _detectionStatus = '자동 감지됨 — 필요 시 4점을 미세 조정하세요.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('이미지를 불러오지 못했습니다: $e')));
    }
  }

  @override
  void dispose() {
    _yolo?.close();
    super.dispose();
  }

  /// YOLO 카드 검출 1회 lazy load. 모델 자산 없으면 null 캐시 후 항상 null 반환.
  Future<CardDetection?> _runYoloCard(String imagePath) async {
    try {
      if (!_yoloAttempted) {
        _yoloAttempted = true;
        try {
          _yolo = await YoloLengthDetector.load();
        } on ModelMissingException {
          _yolo = null;
        }
      }
      final yolo = _yolo;
      if (yolo == null) return null;
      final result = await yolo.detect(imagePath);
      return result.card;
    } catch (_) {
      return null;
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

  void _materializeAutoCorners(Size area) {
    if (_pendingImageCorners == null) return;
    final sx = area.width / _imageWidthPx;
    final sy = area.height / _imageHeightPx;
    _refCorners = _pendingImageCorners!
        .map((p) => Offset(p.dx * sx, p.dy * sy))
        .toList();
    _pendingImageCorners = null;
  }

  void _enterRoiMode() {
    final area = _imageStageArea;
    setState(() {
      _roiMode = true;
      _detectionStatus = null;
      _refCorners = area == null ? null : _initialRoiBox(area);
    });
  }

  List<Offset> _initialRoiBox(Size area) {
    final w = area.width * 0.7;
    final h = area.height * 0.5;
    final cx = area.width / 2;
    final cy = area.height / 2;
    return [
      Offset(cx - w / 2, cy - h / 2),
      Offset(cx + w / 2, cy - h / 2),
      Offset(cx + w / 2, cy + h / 2),
      Offset(cx - w / 2, cy + h / 2),
    ];
  }

  /// ROI 4점 드래그 시 축정렬 박스 유지.
  void _onRoiDrag(int index, Offset p, Size area) {
    final c = _refCorners;
    if (c == null) return;
    final clamped = Offset(
      p.dx.clamp(0, area.width),
      p.dy.clamp(0, area.height),
    );
    // 인접 두 점의 좌표를 따라 갱신해 항상 직사각형 유지.
    final next = [...c];
    next[index] = clamped;
    final tl = next[0], tr = next[1], br = next[2], bl = next[3];
    switch (index) {
      case 0: // TL
        next[1] = Offset(tr.dx, clamped.dy);
        next[3] = Offset(clamped.dx, bl.dy);
        break;
      case 1: // TR
        next[0] = Offset(tl.dx, clamped.dy);
        next[2] = Offset(clamped.dx, br.dy);
        break;
      case 2: // BR
        next[3] = Offset(bl.dx, clamped.dy);
        next[1] = Offset(clamped.dx, tr.dy);
        break;
      case 3: // BL
        next[2] = Offset(br.dx, clamped.dy);
        next[0] = Offset(clamped.dx, tl.dy);
        break;
    }
    setState(() => _refCorners = next);
  }

  Future<void> _retryDetectInRoi() async {
    final c = _refCorners;
    final area = _imageStageArea;
    final img = _image;
    if (c == null || area == null || img == null) return;
    // 위젯 → 이미지 좌표.
    final sx = _imageWidthPx / area.width;
    final sy = _imageHeightPx / area.height;
    final xs = c.map((p) => p.dx * sx);
    final ys = c.map((p) => p.dy * sy);
    final roi = Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
    setState(() => _detectionStatus = '지정 영역에서 카드 재검색 중...');
    final det = await _detector.detect(img.path, roi: roi);
    if (!mounted) return;

    // ROI 면적 대비 검출 면적이 너무 작으면(내부 작은 영역 오인식) ROI 자체를 사용.
    final roiArea = roi.width * roi.height;
    final tooSmall = det == null ||
        _quadArea(det.cornersImagePx) < roiArea * 0.30;

    if (tooSmall) {
      // ROI 박스 4점을 이미지 픽셀 → 위젯 픽셀로 매핑해 _pendingImageCorners에 주입.
      final roiCornersImagePx = [
        Offset(roi.left, roi.top),
        Offset(roi.right, roi.top),
        Offset(roi.right, roi.bottom),
        Offset(roi.left, roi.bottom),
      ];
      setState(() {
        _roiMode = false;
        _pendingImageCorners = roiCornersImagePx;
        _refCorners = null;
        _autoDetected = false;
        _detectionStatus = det == null
            ? '자동 감지 실패 — 지정한 영역으로 4점을 배치했습니다. 모서리를 미세 조정하세요.'
            : '검출 영역이 너무 작아 지정한 ROI로 4점을 배치했습니다. 모서리를 미세 조정하세요.';
      });
      return;
    }
    setState(() {
      _roiMode = false;
      _pendingImageCorners = det.cornersImagePx;
      _refCorners = null;
      _autoDetected = true;
      _detectionStatus = '재검색 성공 — 필요 시 4점을 미세 조정하세요.';
    });
  }

  double _quadArea(List<Offset> p) {
    // Shoelace
    var s = 0.0;
    for (var i = 0; i < p.length; i++) {
      final a = p[i];
      final b = p[(i + 1) % p.length];
      s += a.dx * b.dy - b.dx * a.dy;
    }
    return s.abs() / 2;
  }

  void _initRefCorners(Size area) {
    final w = area.width;
    final cardAspect = _reference.widthMm / _reference.heightMm;
    final boxW = w * 0.6;
    final boxH = boxW / cardAspect;
    final cx = w / 2;
    final cy = area.height / 2;
    _refCorners = [
      Offset(cx - boxW / 2, cy - boxH / 2),
      Offset(cx + boxW / 2, cy - boxH / 2),
      Offset(cx + boxW / 2, cy + boxH / 2),
      Offset(cx - boxW / 2, cy + boxH / 2),
    ];
  }

  PlanarRectifier? _buildRectifier() {
    final c = _refCorners;
    if (c == null) return null;
    return PlanarRectifier.fromCorners(
      cornersWidgetPx: c,
      widthMm: _reference.widthMm,
      heightMm: _reference.heightMm,
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

  void _undoLast() {
    if (_points.isEmpty) return;
    setState(_points.removeLast);
  }

  void _changeKind(MeasureKind k) {
    setState(() {
      _kind = k;
      _points.clear();
    });
  }

  Future<void> _confirmMeasurement() async {
    final rect = _buildRectifier();
    if (rect == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('스케일 계산에 실패했습니다. 4점을 다시 확인해주세요.')),
      );
      return;
    }
    final imagePath = await captureBoundaryAsPng(_captureKey);
    final modeLabel = '사진 — ${_reference.label}';
    final confidence = _autoDetected
        ? MeasurementConfidence.high
        : MeasurementConfidence.medium;
    final calibNote = _autoDetected ? '자동 4점 + 호모그래피' : '수동 4점 + 호모그래피';
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
          value: rect.angleAtVertexDegrees(_points[0], _points[1], _points[2]),
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
      appBar: AppBar(title: Text('참조 객체 — ${_reference.label}')),
      body: TiltWarning(
        child: switch (_step) {
          _Step.pickImage => _PickImageView(onPick: _pick),
          _Step.calibrate => _buildImageStage(
              instructions: _roiMode
                  ? '카드 주변을 박스로 감싼 뒤 "이 영역에서 찾기"를 누르세요.'
                  : (_detectionStatus ?? '신용카드 네 모서리에 4점을 맞추세요.'),
              buildOverlay: _buildCalibrateOverlay,
              primaryAction: _roiMode
                  ? (_refCorners == null ? null : _retryDetectInRoi)
                  : (_refCorners == null
                      ? null
                      : () => setState(() => _step = _Step.measure)),
              primaryLabel: _roiMode ? '이 영역에서 찾기' : '다음',
              secondary: _roiMode
                  ? OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _roiMode = false;
                        _refCorners = null;
                        _pendingImageCorners = null;
                      }),
                      icon: const Icon(Icons.close),
                      label: const Text('영역 지정 취소'),
                    )
                  : OutlinedButton.icon(
                      onPressed: _enterRoiMode,
                      icon: const Icon(Icons.crop),
                      label: const Text('영역 지정 후 재검색'),
                    ),
            ),
          _Step.measure => _buildImageStage(
              instructions: _measureInstruction(),
              header: _buildKindChips(),
              buildOverlay: _buildMeasureOverlay,
              primaryAction: _canConfirm() ? _confirmMeasurement : null,
              primaryLabel: '측정',
              secondary: _buildUndoButton(),
            ),
        },
      ),
    ),
    );
  }

  String _measureInstruction() => switch (_kind) {
        MeasureKind.distance => '대상의 두 점을 탭하세요.',
        MeasureKind.perimeter => '둘레를 따라 점을 차례로 탭하세요 (최소 2점).',
        MeasureKind.area => '도형 꼭짓점을 차례로 탭하세요 (최소 3점, 자동으로 닫힘).',
        MeasureKind.angle => '꼭짓점을 가운데로 세 점을 차례로 탭하세요.',
      };

  Widget _buildKindChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        alignment: WrapAlignment.center,
        children: MeasureKind.values.map((k) {
          return ChoiceChip(
            label: Text(k.label),
            selected: _kind == k,
            onSelected: (_) => _changeKind(k),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildUndoButton() {
    return OutlinedButton.icon(
      onPressed: _points.isEmpty ? null : _undoLast,
      icon: const Icon(Icons.undo),
      label: const Text('실행 취소'),
    );
  }

  Widget _buildImageStage({
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
                  _imageStageArea = area;
                  if (_step == _Step.calibrate && _refCorners == null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        if (_roiMode) {
                          _refCorners = _initialRoiBox(area);
                        } else if (_pendingImageCorners != null) {
                          _materializeAutoCorners(area);
                        } else if (_detectionStatus != null &&
                            _detectionStatus!.contains('실패')) {
                          _initRefCorners(area);
                        }
                      });
                    });
                  }
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
                        _step = _Step.pickImage;
                        _image = null;
                        _refCorners = null;
                        _pendingImageCorners = null;
                        _autoDetected = false;
                        _detectionStatus = null;
                        _roiMode = false;
                        _cornerCandidates = const [];
                        _points.clear();
                      }),
                      child: const Text('다시 선택'),
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

  Widget _buildCalibrateOverlay(Size area) {
    final corners = _refCorners;
    if (corners == null) return const SizedBox.shrink();
    return Stack(
      children: [
        // 코너 스냅 후보 시각화 (옅은 점).
        if (!_roiMode && _cornerCandidates.isNotEmpty && _imageWidthPx > 0)
          Positioned.fill(
            child: CustomPaint(
              painter: _CornerHintPainter(
                _cornerCandidates,
                imageWidth: _imageWidthPx.toDouble(),
                imageHeight: _imageHeightPx.toDouble(),
              ),
            ),
          ),
        Positioned.fill(
          child: CustomPaint(painter: _QuadPainter(corners, closed: true)),
        ),
        for (var i = 0; i < 4; i++)
          DraggableHandle(
            position: corners[i],
            label: _roiMode ? '' : '${i + 1}',
            onDrag: (p) {
              if (_roiMode) {
                _onRoiDrag(i, p, area);
              } else {
                // 드래그 중에는 자유 이동(스냅 없음).
                setState(() {
                  corners[i] = Offset(
                    p.dx.clamp(0, area.width),
                    p.dy.clamp(0, area.height),
                  );
                });
              }
            },
            onDragEnd: _roiMode
                ? null
                : (last) {
                    final snapped = _snapToNearestCorner(last, area);
                    if (snapped == last) return;
                    setState(() {
                      corners[i] = Offset(
                        snapped.dx.clamp(0, area.width),
                        snapped.dy.clamp(0, area.height),
                      );
                    });
                  },
          ),
      ],
    );
  }

  /// 위젯 좌표 [p]가 강한 코너 후보 근처에 있으면 그 코너 위치(위젯 좌표)로 스냅.
  /// 이미지 짧은 변의 ~2% 이내일 때만 스냅.
  Offset _snapToNearestCorner(Offset p, Size area) {
    final cands = _cornerCandidates;
    if (cands.isEmpty || _imageWidthPx == 0 || _imageHeightPx == 0) return p;
    final sx = _imageWidthPx / area.width;
    final sy = _imageHeightPx / area.height;
    final pImg = Offset(p.dx * sx, p.dy * sy);
    final thresholdImg =
        math.min(_imageWidthPx, _imageHeightPx) * 0.05;
    double bestD2 = thresholdImg * thresholdImg;
    Offset? bestCand;
    for (final c in cands) {
      final dx = c.dx - pImg.dx;
      final dy = c.dy - pImg.dy;
      final d2 = dx * dx + dy * dy;
      if (d2 < bestD2) {
        bestD2 = d2;
        bestCand = c;
      }
    }
    if (bestCand == null) return p;
    final snapped = Offset(bestCand.dx / sx, bestCand.dy / sy);
    if (kDebugMode) {
      debugPrint('[Snap] dist=${math.sqrt(bestD2).toStringAsFixed(1)}px(img) '
          'from=${p.dx.toStringAsFixed(1)},${p.dy.toStringAsFixed(1)} '
          'to=${snapped.dx.toStringAsFixed(1)},${snapped.dy.toStringAsFixed(1)}');
    }
    return snapped;
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
          if (_refCorners != null)
            Positioned.fill(
              child: CustomPaint(painter: _QuadPainter(_refCorners!, closed: true)),
            ),
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

  bool _isOnHandle(Offset p) {
    const r = 20.0;
    for (final pt in _points) {
      if ((p - pt).distance < r) return true;
    }
    return false;
  }
}

class _PickImageView extends StatelessWidget {
  const _PickImageView({required this.onPick});
  final void Function(ImageSource) onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '신용카드를 측정 대상과 같은 평면에 두고 위에서 수직으로 촬영하세요.',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.camera_alt),
            onPressed: () => onPick(ImageSource.camera),
            label: const Text('촬영'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.photo_library),
            onPressed: () => onPick(ImageSource.gallery),
            label: const Text('갤러리에서 선택'),
          ),
        ],
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter(this.points, {this.color = const Color(0xFF00897B), this.closed = false});
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

class _CornerHintPainter extends CustomPainter {
  _CornerHintPainter(this.imageCandidates,
      {required this.imageWidth, required this.imageHeight});
  final List<Offset> imageCandidates;
  final double imageWidth;
  final double imageHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / imageWidth;
    final sy = size.height / imageHeight;
    final paint = Paint()
      ..color = const Color(0x6600897B)
      ..style = PaintingStyle.fill;
    for (final c in imageCandidates) {
      canvas.drawCircle(Offset(c.dx * sx, c.dy * sy), 2, paint);
    }
  }

  @override
  bool shouldRepaint(_CornerHintPainter old) =>
      old.imageCandidates != imageCandidates;
}
