// YOLO11n-seg 다중 클래스(credit_card, fish) 검출기.
// 모델 자산이 없으면 load()가 ModelMissingException을 던지고, 호출 측에서 CV 폴백.
//
// 입력: 임의 사진 (카드+측정 대상이 함께 있을 수 있음)
// 출력: LengthDetection { card?: CardDetection, fish?: FishDetection }
//
// 후처리 단계 (Phase D 완성 시):
//   1. 출력 텐서 디코드 → [num_boxes, (xywh, class_scores, mask_coeffs(32))]
//   2. 신뢰도·NMS로 클래스별 1개씩 추림
//   3. mask_coeffs × prototypes(32×160×160) → 160×160 마스크
//   4. sigmoid + threshold 0.5 → 이진 마스크
//   5. 박스로 클립 → 원본 좌표로 리사이즈
//   6. opencv_dart로 외곽 추출 (card: minAreaRect 4점, fish: 외곽 폴리곤 + minAreaRect 장변 양끝)
//
// 현재 구현 상태: 스캐폴드. load()/preprocess()/inference() 골격 완성, post-process는 모델 실제 출력 텐서 모양 확인 후 작성.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../reference_object/card_detector.dart' show CardDetection;
import 'length_detection.dart';

const String _modelAsset = 'assets/models/length_yolo11n_seg.tflite';
const int _inputSize = 640;

// 클래스 ID 및 검출 신뢰도·NMS 임계값. Phase D 후처리 구현 시 사용.
// ignore: unused_element
const int _classCard = 0;
// ignore: unused_element
const int _classFish = 1;
// ignore: unused_element
const double _confThreshold = 0.25;
// ignore: unused_element
const double _iouThreshold = 0.45;

class ModelMissingException implements Exception {
  const ModelMissingException(this.message);
  final String message;
  @override
  String toString() => 'ModelMissingException: $message';
}

class YoloLengthDetector {
  YoloLengthDetector._(this._interpreter);

  final Interpreter _interpreter;
  var _closed = false;

  static Future<YoloLengthDetector> load() async {
    try {
      final bytes = await rootBundle.load(_modelAsset);
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'length_yolo11n_seg.tflite'));
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      final options = InterpreterOptions()..threads = 4;
      // TODO: GPU/NNAPI delegate 시도 (Phase D 검증 시 활성화).
      final interpreter = Interpreter.fromFile(file, options: options);
      if (kDebugMode) {
        debugPrint('[YOLO] loaded $_modelAsset. inputs=${interpreter.getInputTensors().length} '
            'outputs=${interpreter.getOutputTensors().length}');
        for (final t in interpreter.getOutputTensors()) {
          debugPrint('[YOLO] output: shape=${t.shape} type=${t.type}');
        }
      }
      return YoloLengthDetector._(interpreter);
    } catch (e) {
      throw ModelMissingException(
        '모델 자산을 로드할 수 없습니다($_modelAsset): $e',
      );
    }
  }

  /// 임의 사진 → 카드+물고기 동시 검출. 둘 다 못 찾으면 [LengthDetection]의 두 필드 모두 null.
  Future<LengthDetection> detect(String imagePath) async {
    if (_closed) {
      throw StateError('detector closed');
    }
    final raw = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      throw StateError('이미지 디코드 실패: $imagePath');
    }
    final origW = decoded.width;
    final origH = decoded.height;

    // letterbox: 종횡비 유지하며 _inputSize x _inputSize 정사각에 패딩.
    final (letter, scale, padX, padY) = _letterbox(decoded, _inputSize);
    final inputTensor = _imageToFloat32(letter);

    // 출력 텐서 모양은 모델에 따라 다름. YOLOv8/v11-seg 기준:
    //   out0: [1, 4 + num_classes + 32, num_boxes]  (예: [1, 38, 8400])
    //   out1: [1, 32, 160, 160]                     (mask prototypes)
    // 실제 모델 받으면 shape 출력 확인 후 아래 두 변수 모양 맞춰 수정.
    final outDet = _allocateDetectionOutput();
    final outProto = _allocateProtoOutput();
    final outputs = <int, Object>{0: outDet, 1: outProto};
    _interpreter.runForMultipleInputs([inputTensor], outputs);

    // 후처리: 신뢰도·NMS → 클래스별 best → 마스크 합성 → opencv 외곽 추출.
    // 현재는 미구현 (Phase D 작업 시 완성). 모델 자산 없으면 어차피 여기 도달 안 함.
    final card = _decodeCard(outDet, outProto,
        origW: origW, origH: origH, scale: scale, padX: padX, padY: padY);
    final fish = _decodeFish(outDet, outProto,
        origW: origW, origH: origH, scale: scale, padX: padX, padY: padY);

    return LengthDetection(card: card, fish: fish);
  }

  void close() {
    if (_closed) return;
    _interpreter.close();
    _closed = true;
  }

  // ---- 전처리 ----------

  /// letterbox: 짧은 변에 회색 패딩, 종횡비 유지. (변환된 이미지, 스케일, padX, padY) 반환.
  (img.Image, double, int, int) _letterbox(img.Image src, int targetSize) {
    final scale = targetSize / (src.width > src.height ? src.width : src.height);
    final newW = (src.width * scale).round();
    final newH = (src.height * scale).round();
    final resized = img.copyResize(src, width: newW, height: newH);
    final canvas = img.Image(width: targetSize, height: targetSize);
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
    final padX = ((targetSize - newW) / 2).round();
    final padY = ((targetSize - newH) / 2).round();
    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);
    return (canvas, scale, padX, padY);
  }

  /// [1, H, W, 3] float32 [0,1] normalized (NHWC). TFLite 변환 시 형식이 NCHW면 여기 수정.
  List<List<List<List<double>>>> _imageToFloat32(img.Image src) {
    return [
      List.generate(_inputSize, (y) {
        return List.generate(_inputSize, (x) {
          final px = src.getPixel(x, y);
          return [px.r / 255.0, px.g / 255.0, px.b / 255.0];
        });
      }),
    ];
  }

  // ---- 출력 버퍼 할당 ----------

  /// 디텍션 출력 모양 — Phase D에서 실제 모델 shape에 맞춰 조정.
  /// 임시 가정: [1, 38, 8400] (4 box + 2 class + 32 mask coeffs, 8400 anchors).
  Object _allocateDetectionOutput() {
    const numFields = 4 + 2 + 32; // = 38
    const numAnchors = 8400;
    return [
      List.generate(numFields, (_) => List.filled(numAnchors, 0.0)),
    ];
  }

  /// 마스크 prototype 출력 — 임시 가정: [1, 32, 160, 160].
  Object _allocateProtoOutput() {
    return [
      List.generate(32, (_) {
        return List.generate(160, (_) => List.filled(160, 0.0));
      }),
    ];
  }

  // ---- 후처리 ----------

  CardDetection? _decodeCard(
    Object outDet,
    Object outProto, {
    required int origW,
    required int origH,
    required double scale,
    required int padX,
    required int padY,
  }) {
    // TODO Phase D: 디텍션 텐서에서 class 0(card) 후보 중 신뢰도 최대 → NMS → 마스크 합성 →
    //              opencv minAreaRect → 4점 → letterbox 좌표 → 원본 좌표 복원.
    return null;
  }

  FishDetection? _decodeFish(
    Object outDet,
    Object outProto, {
    required int origW,
    required int origH,
    required double scale,
    required int padX,
    required int padY,
  }) {
    // TODO Phase D: 디텍션 텐서에서 class 1(fish) 후보 → 마스크 합성 → opencv findContours →
    //              외곽 폴리곤 + minAreaRect 장변 양끝(head/tail).
    return null;
  }
}

