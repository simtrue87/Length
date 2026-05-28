// 사용자의 선호 단위(mm/cm/inch)를 SharedPreferences로 영속화하는 Riverpod 노티파이어.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../units/unit_converter.dart';

const _prefKey = 'preferred_unit';

class PreferredUnitNotifier extends AsyncNotifier<LengthUnit> {
  @override
  Future<LengthUnit> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) return LengthUnit.cm;
    return LengthUnit.values.firstWhere(
      (u) => u.name == raw,
      orElse: () => LengthUnit.cm,
    );
  }

  Future<void> set(LengthUnit unit) async {
    state = AsyncData(unit);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, unit.name);
  }
}

final preferredUnitProvider =
    AsyncNotifierProvider<PreferredUnitNotifier, LengthUnit>(
        PreferredUnitNotifier.new);
