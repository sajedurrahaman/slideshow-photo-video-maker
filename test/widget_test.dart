import 'package:flutter_test/flutter_test.dart';

import 'package:clip_craft_slideshow/main.dart';

void main() {
  testWidgets('App boots to splash then home', (WidgetTester tester) async {
    await tester.pumpWidget(const ClipCraftApp());
    expect(find.text('ClipCraft'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pumpAndSettle();
    expect(find.text('New Slideshow'), findsOneWidget);
  });
}
