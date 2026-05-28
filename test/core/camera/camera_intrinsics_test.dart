// CameraIntrinsics 생성 + unproject 단위 테스트.
import 'package:flutter_test/flutter_test.dart';
import 'package:length/core/camera/camera_intrinsics.dart';

void main() {
  group('fromFocal35mm', () {
    test('36mm 환산·4000px 폭 → fx 4000', () {
      final k = CameraIntrinsics.fromFocal35mm(
        focal35mm: 36,
        imageWidthPx: 4000,
        imageHeightPx: 3000,
      );
      expect(k.fxPx, 4000.0);
      expect(k.cxPx, 2000.0);
      expect(k.cyPx, 1500.0);
    });
  });

  group('unproject', () {
    final k = CameraIntrinsics.fromFocal35mm(
      focal35mm: 26,
      imageWidthPx: 4000,
      imageHeightPx: 3000,
    );

    test('주점은 (0,0,depth)', () {
      final p = unproject(u: 2000, v: 1500, depth: 500, intrinsics: k);
      expect(p.x, 0.0);
      expect(p.y, 0.0);
      expect(p.z, 500.0);
    });

    test('주점 오른쪽 1픽셀, depth=fx → X=1mm', () {
      final p = unproject(u: k.cxPx + 1, v: k.cyPx, depth: k.fxPx, intrinsics: k);
      expect(p.x, closeTo(1.0, 1e-9));
      expect(p.y, 0.0);
    });
  });
}
