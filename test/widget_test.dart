// 앱 부트 위젯 테스트. ProviderScope + 라우터가 모드 선택 화면을 그리는지 확인.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:length/app/app.dart';

void main() {
  testWidgets('앱이 부트되어 모드 선택 화면을 표시한다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LengthApp()));
    await tester.pumpAndSettle();

    expect(find.text('Length'), findsOneWidget);
    expect(find.text('AR 두 점 측정'), findsOneWidget);
  });
}
