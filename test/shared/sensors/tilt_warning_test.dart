// tiltDegreesFromAccel 단위 테스트.
import 'package:flutter_test/flutter_test.dart';
import 'package:length/shared/sensors/tilt_warning.dart';

void main() {
  test('z=g면 0도', () {
    expect(tiltDegreesFromAccel(9.80665), closeTo(0.0, 1e-6));
  });

  test('z=0이면 90도', () {
    expect(tiltDegreesFromAccel(0.0), closeTo(90.0, 1e-6));
  });

  test('z=g*cos(30°)이면 30도', () {
    const z = 9.80665 * 0.8660254;
    expect(tiltDegreesFromAccel(z), closeTo(30.0, 1e-3));
  });
}
