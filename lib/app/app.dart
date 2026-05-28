// 앱 루트 위젯. Riverpod ProviderScope + MaterialApp.router + 테마 적용.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/theme_mode_pref.dart';
import 'router.dart';
import 'theme.dart';

class LengthApp extends ConsumerWidget {
  const LengthApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    return MaterialApp.router(
      title: 'Length',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: mode,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
