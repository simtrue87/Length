// QR 코드를 정지 이미지에서 감지해 4 모서리(이미지 픽셀 좌표)를 반환.
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class MarkerDetection {
  const MarkerDetection({
    required this.cornersImagePx,
    required this.rawValue,
    required this.imageWidthPx,
    required this.imageHeightPx,
  });

  /// TL, TR, BR, BL 순서 (mobile_scanner의 corners는 시계방향으로 4개).
  final List<Offset> cornersImagePx;
  final String? rawValue;
  final int imageWidthPx;
  final int imageHeightPx;
}

class MarkerDetector {
  MarkerDetector({MobileScannerController? controller})
      : _controller = controller ?? MobileScannerController(formats: const [
              BarcodeFormat.qrCode,
              BarcodeFormat.dataMatrix,
            ]);

  final MobileScannerController _controller;

  Future<MarkerDetection?> detectInImage(String imagePath) async {
    final capture = await _controller.analyzeImage(imagePath);
    if (capture == null || capture.barcodes.isEmpty) return null;
    final barcode = capture.barcodes.first;
    final corners = barcode.corners;
    if (corners.length != 4) return null;
    final size = capture.size;
    return MarkerDetection(
      cornersImagePx: corners,
      rawValue: barcode.rawValue,
      imageWidthPx: size.width.toInt(),
      imageHeightPx: size.height.toInt(),
    );
  }

  Future<void> dispose() => _controller.dispose();
}
