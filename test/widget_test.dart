import 'package:flutter_test/flutter_test.dart';
import 'package:toeic_master_front/main.dart';

void main() {
  testWidgets('App should load and show bottom navigation', (WidgetTester tester) async {
    // 앱을 빌드합니다. (ExamTalkApp으로 이름 일치)
    await tester.pumpWidget(const ExamTalkApp());

    // 메인 탭 텍스트들이 화면에 있는지 확인합니다.
    expect(find.text('스터디'), findsWidgets);
    expect(find.text('마이페이지'), findsWidgets);
  });
}
