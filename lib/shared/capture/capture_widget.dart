// 위젯을 PNG로 캡처해 임시파일로 저장하는 유틸. RepaintBoundary 기반.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// [key]가 가리키는 RepaintBoundary를 [pixelRatio] 배율로 PNG 캡처해
/// 임시 디렉터리에 저장하고 절대 경로를 반환. 실패 시 null.
Future<String?> captureBoundaryAsPng(
  GlobalKey key, {
  double pixelRatio = 2.0,
  String prefix = 'length',
}) async {
  final boundary =
      key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return null;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) return null;
  final dir = await getTemporaryDirectory();
  final name = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.png';
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(bytes.buffer.asUint8List());
  return file.path;
}
