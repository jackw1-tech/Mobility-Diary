import 'package:flutter_test/flutter_test.dart';

import 'package:diary/main.dart';

void main() {
  testWidgets('Diary app mounts without framework errors', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DiaryApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DiaryApp), findsOneWidget);
    expect(find.text('Sensori reali'), findsOneWidget);
    expect(find.text('Eventi simulati'), findsNothing);
  });
}
