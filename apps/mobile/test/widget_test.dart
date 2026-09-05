import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/main.dart';

void main() {
  testWidgets('renders the household finance overview', (tester) async {
    await tester.pumpWidget(const PaisaApp());
    expect(find.text('Paisa'), findsOneWidget);
    expect(find.text('Good evening, Arjun'), findsOneWidget);
    expect(find.text('SAVED THIS MONTH'), findsOneWidget);
  });
}
