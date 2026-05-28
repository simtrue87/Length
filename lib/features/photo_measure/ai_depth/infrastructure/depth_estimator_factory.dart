// 모델 자산 존재 여부에 따라 TFLite 또는 Stub 추정기를 반환.
import '../domain/depth_estimator.dart';
import 'stub_depth_estimator.dart';
import 'tflite_depth_estimator.dart';

class DepthEstimatorResolution {
  const DepthEstimatorResolution({required this.estimator, required this.isReal});
  final DepthEstimator estimator;
  final bool isReal;
}

Future<DepthEstimatorResolution> resolveDepthEstimator() async {
  try {
    final tflite = await TfliteDepthEstimator.load();
    return DepthEstimatorResolution(estimator: tflite, isReal: true);
  } on ModelMissingException {
    return const DepthEstimatorResolution(
      estimator: StubDepthEstimator(),
      isReal: false,
    );
  }
}
