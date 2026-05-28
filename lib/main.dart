// Length 앱 진입점. Riverpod ProviderScope 래핑 후 LengthApp 실행.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  runApp(const ProviderScope(child: LengthApp()));
}
