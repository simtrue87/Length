// 이미지 파일 EXIF에서 35mm 환산 초점거리 추출. 실패 시 폴백.
import 'dart:io';

import 'package:exif/exif.dart';

class ExifFocalResult {
  const ExifFocalResult({required this.focal35mm, required this.isFallback});
  final double focal35mm;
  final bool isFallback;
}

const double _defaultFocal35mm = 26.0;

/// 우선순위: FocalLengthIn35mmFilm → (FocalLength × cropFactor 추정 불가하면 기본).
Future<ExifFocalResult> readFocal35mm(File file) async {
  try {
    final bytes = await file.readAsBytes();
    final tags = await readExifFromBytes(bytes);
    final f35 = tags['EXIF FocalLengthIn35mmFilm'];
    if (f35 != null) {
      final parsed = double.tryParse(f35.printable.trim());
      if (parsed != null && parsed > 0) {
        return ExifFocalResult(focal35mm: parsed, isFallback: false);
      }
    }
  } catch (_) {
    // 무시: 폴백.
  }
  return const ExifFocalResult(focal35mm: _defaultFocal35mm, isFallback: true);
}
