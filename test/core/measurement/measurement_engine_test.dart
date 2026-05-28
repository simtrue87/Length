// MeasurementEngine 단위 테스트.
import 'package:flutter_test/flutter_test.dart';
import 'package:length/core/measurement/measurement_engine.dart';

void main() {
  group('distance2D', () {
    test('3-4-5 삼각형', () {
      expect(
        MeasurementEngine.distance2D(const Offset(0, 0), const Offset(3, 4)),
        5.0,
      );
    });

    test('같은 점은 0', () {
      expect(
        MeasurementEngine.distance2D(const Offset(2, 2), const Offset(2, 2)),
        0.0,
      );
    });
  });

  group('distance3D', () {
    test('1-2-2 → 3', () {
      const a = (x: 0.0, y: 0.0, z: 0.0);
      const b = (x: 1.0, y: 2.0, z: 2.0);
      expect(MeasurementEngine.distance3D(a, b), 3.0);
    });
  });

  group('computeScale', () {
    test('신용카드 100픽셀 = 85.6mm → 0.856 mm/px', () {
      expect(MeasurementEngine.computeScale(100, 85.6), closeTo(0.856, 1e-9));
    });

    test('0 이하 길이는 ArgumentError', () {
      expect(() => MeasurementEngine.computeScale(0, 85.6), throwsArgumentError);
      expect(() => MeasurementEngine.computeScale(-1, 85.6), throwsArgumentError);
    });
  });

  group('pixelToMm', () {
    test('스케일 곱셈', () {
      expect(
        MeasurementEngine.pixelToMm(pixelDistance: 50, mmPerPixel: 0.856),
        closeTo(42.8, 1e-9),
      );
    });
  });

  group('polylineLengthPx', () {
    test('점 1개 이하면 0', () {
      expect(MeasurementEngine.polylineLengthPx([]), 0);
      expect(MeasurementEngine.polylineLengthPx([const Offset(1, 2)]), 0);
    });

    test('직선 3점 합산', () {
      expect(
        MeasurementEngine.polylineLengthPx([
          const Offset(0, 0),
          const Offset(3, 4),
          const Offset(3, 4 + 5),
        ]),
        10.0,
      );
    });
  });

  group('polygonAreaPx2', () {
    test('정사각형 10x10 = 100', () {
      expect(
        MeasurementEngine.polygonAreaPx2(const [
          Offset(0, 0),
          Offset(10, 0),
          Offset(10, 10),
          Offset(0, 10),
        ]),
        100.0,
      );
    });

    test('시계방향이어도 같은 면적', () {
      expect(
        MeasurementEngine.polygonAreaPx2(const [
          Offset(0, 0),
          Offset(0, 10),
          Offset(10, 10),
          Offset(10, 0),
        ]),
        100.0,
      );
    });

    test('3점 미만은 0', () {
      expect(MeasurementEngine.polygonAreaPx2(const []), 0);
      expect(MeasurementEngine.polygonAreaPx2(const [Offset(0, 0), Offset(1, 1)]), 0);
    });
  });

  group('computeMmPerPixelFromHeight', () {
    test('FOV 60°, 높이 1000mm, 위젯 1000px → 2*1000*tan(30°) / 1000', () {
      final mmPerPx = MeasurementEngine.computeMmPerPixelFromHeight(
        heightMm: 1000,
        verticalFovDegrees: 60,
        widgetHeightPx: 1000,
      );
      // 2 * 1000 * tan(30°) ≈ 1154.7 → /1000 ≈ 1.1547
      expect(mmPerPx, closeTo(1.1547, 1e-3));
    });

    test('높이 0 이하면 ArgumentError', () {
      expect(
        () => MeasurementEngine.computeMmPerPixelFromHeight(
          heightMm: 0,
          verticalFovDegrees: 60,
          widgetHeightPx: 100,
        ),
        throwsArgumentError,
      );
    });

    test('위젯 높이 0 이하면 ArgumentError', () {
      expect(
        () => MeasurementEngine.computeMmPerPixelFromHeight(
          heightMm: 500,
          verticalFovDegrees: 60,
          widgetHeightPx: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('angleAtVertexDegrees', () {
    test('직각', () {
      expect(
        MeasurementEngine.angleAtVertexDegrees(
          const Offset(1, 0),
          const Offset(0, 0),
          const Offset(0, 1),
        ),
        closeTo(90.0, 1e-9),
      );
    });

    test('일직선 = 180', () {
      expect(
        MeasurementEngine.angleAtVertexDegrees(
          const Offset(-1, 0),
          const Offset(0, 0),
          const Offset(1, 0),
        ),
        closeTo(180.0, 1e-9),
      );
    });

    test('vertex와 동일점은 ArgumentError', () {
      expect(
        () => MeasurementEngine.angleAtVertexDegrees(
          const Offset(0, 0),
          const Offset(0, 0),
          const Offset(1, 1),
        ),
        throwsArgumentError,
      );
    });
  });
}
