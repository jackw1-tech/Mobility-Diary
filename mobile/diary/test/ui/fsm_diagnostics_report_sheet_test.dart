import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/ui/widgets/home/fsm_diagnostics_report_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offers full log copy and native file sharing', (tester) async {
    const logContent = '{"type":"recording_started"}\n';
    final timestamp = DateTime.utc(2026, 9, 4, 10);
    final report = AcquisitionDiagnosticsReport(
      sessionId: 'session-id',
      filePath: '/tmp/fsm-diagnostics-session-id.jsonl',
      fileName: 'fsm-diagnostics-session-id.jsonl',
      content: logContent,
      sizeBytes: logContent.length,
      decisionCount: 42,
      startedAt: timestamp,
      endedAt: timestamp.add(const Duration(minutes: 5)),
    );
    String? copiedContent;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FsmDiagnosticsReportView(
            report: report,
            copyContent: (content) async => copiedContent = content,
          ),
        ),
      ),
    );

    expect(find.textContaining('42 decisioni della FSM'), findsOneWidget);
    expect(find.text('Copia contenuto'), findsOneWidget);
    expect(find.text('Condividi / salva file'), findsOneWidget);

    await tester.tap(find.text('Copia contenuto'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Copiato'), findsOneWidget);
    expect(copiedContent, logContent);
  });
}
