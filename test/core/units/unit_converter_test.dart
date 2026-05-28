// UnitConverter 단위 테스트.
import 'package:flutter_test/flutter_test.dart';
import 'package:length/core/units/unit_converter.dart';

void main() {
  group('fromMm', () {
    test('mm 변환 없음', () {
      expect(UnitConverter.fromMm(100, LengthUnit.mm), 100);
    });

    test('cm = mm / 10', () {
      expect(UnitConverter.fromMm(85.6, LengthUnit.cm), closeTo(8.56, 1e-9));
    });

    test('inch = mm / 25.4', () {
      expect(UnitConverter.fromMm(25.4, LengthUnit.inch), closeTo(1.0, 1e-9));
    });
  });

  group('format', () {
    test('기본 자릿수 1', () {
      expect(UnitConverter.format(85.6, LengthUnit.mm), '85.6 mm');
    });

    test('cm 변환 + 자릿수 2', () {
      expect(UnitConverter.format(85.6, LengthUnit.cm, digits: 2), '8.56 cm');
    });

    test('inch 변환', () {
      expect(UnitConverter.format(25.4, LengthUnit.inch), '1.0 in');
    });
  });
}
