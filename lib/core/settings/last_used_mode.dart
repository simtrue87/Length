// 마지막으로 진입한 측정 모드 경로를 영속화. 모드 선택 화면에서 "최근" 배지로 활용.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'last_used_mode_route';

class LastUsedModeNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> set(String route) async {
    state = AsyncData(route);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, route);
  }
}

final lastUsedModeProvider =
    AsyncNotifierProvider<LastUsedModeNotifier, String?>(
        LastUsedModeNotifier.new);
