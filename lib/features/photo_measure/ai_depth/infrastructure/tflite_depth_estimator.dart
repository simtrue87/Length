// Depth Anything V2 Small TFLite 추정기.
// 모델 자산이 없으면 load()가 ModelMissingException을 던지고, 상위에서 Stub로 폴백.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../domain/depth_estimator.dart';

const String _modelAsset = 'assets/models/depth_anything_v2_small.tflite';
const int _inputSize = 256;

class ModelMissingException implements Exception {
  const ModelMissingException(this.message);
  final String message;
  @override
  String toString() => 'ModelMissingException: $message';
}

class TfliteDepthEstimator implements DepthEstimator {
  TfliteDepthEstimator._(this._interpreter);

  final Interpreter _interpreter;

  static Future<TfliteDepthEstimator> load() async {
    try {
      // rootBundle.load는 자산이 없으면 throw → 파일로 추출 후 Interpreter.fromFile.
      final bytes = await rootBundle.load(_modelAsset);
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'depth_anything_v2_small.tflite'));
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      final interpreter = Interpreter.fromFile(file);
      return TfliteDepthEstimator._(interpreter);
    } catch (e) {
      throw ModelMissingException(
        '모델 자산을 로드할 수 없습니다($_modelAsset): $e',
      );
    }
  }

  @override
  Future<DepthMap> estimate(String imagePath) async {
    final raw = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      throw StateError('이미지를 디코드할 수 없습니다: $imagePath');
    }
    final resized = img.copyResize(decoded, width: _inputSize, height: _inputSize);
    final input = _imageToFloat32(resized);
    final output = List.generate(
      1,
      (_) => List.generate(_inputSize, (_) => List.filled(_inputSize, 0.0)),
    );
    _interpreter.run(input, output);

    final flat = Float32List(_inputSize * _inputSize);
    for (var y = 0; y < _inputSize; y++) {
      for (var x = 0; x < _inputSize; x++) {
        flat[y * _inputSize + x] = output[0][y][x];
      }
    }
    return DepthMap(
      depths: flat,
      width: _inputSize,
      height: _inputSize,
      isMetric: false, // Depth Anything V2는 상대 깊이.
    );
  }

  void close() => _interpreter.close();

  /// [1, H, W, 3] float32 [0,1] normalized.
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
}
