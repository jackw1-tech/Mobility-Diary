import 'package:diary/ui/widgets/state_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a retry action only when recovery is available',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StateMessage(
          icon: Icons.cloud_off,
          text: 'Connessione non disponibile',
          onRetry: () => retries += 1,
        ),
      ),
    );

    expect(find.text('Connessione non disponibile'), findsOneWidget);
    expect(find.text('Riprova'), findsOneWidget);

    await tester.tap(find.text('Riprova'));
    expect(retries, 1);
  });

  testWidgets('renders a terminal message without a retry button',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StateMessage(
          icon: Icons.info_outline,
          text: 'Nessun viaggio disponibile',
        ),
      ),
    );

    expect(find.text('Nessun viaggio disponibile'), findsOneWidget);
    expect(find.text('Riprova'), findsNothing);
  });
}
