// 길이 단위 변환·포맷 유틸. mm/cm/inch 지원.
enum LengthUnit {
  mm('mm'),
  cm('cm'),
  inch('in');

  const LengthUnit(this.symbol);
  final String symbol;
}

class UnitConverter {
  const UnitConverter._();

  static const double _mmPerInch = 25.4;

  static double fromMm(double mm, LengthUnit to) {
    switch (to) {
      case LengthUnit.mm:
        return mm;
      case LengthUnit.cm:
        return mm / 10.0;
      case LengthUnit.inch:
        return mm / _mmPerInch;
    }
  }

  static String format(double mm, LengthUnit to, {int digits = 1}) {
    final value = fromMm(mm, to);
    return '${value.toStringAsFixed(digits)} ${to.symbol}';
  }

  /// mm²를 단위에 맞춰 변환. 면적 환산 계수는 길이의 제곱.
  static double area2FromMm2(double mm2, LengthUnit to) {
    switch (to) {
      case LengthUnit.mm:
        return mm2;
      case LengthUnit.cm:
        return mm2 / 100.0;
      case LengthUnit.inch:
        return mm2 / (_mmPerInch * _mmPerInch);
    }
  }

  static String formatArea(double mm2, LengthUnit to, {int digits = 2}) {
    final value = area2FromMm2(mm2, to);
    return '${value.toStringAsFixed(digits)} ${to.symbol}²';
  }
}
