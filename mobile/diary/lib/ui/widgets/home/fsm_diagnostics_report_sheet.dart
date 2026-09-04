import 'dart:async';

import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

typedef DiagnosticsContentCopier = Future<void> Function(String content);

Future<void> showFsmDiagnosticsReportSheet(
  BuildContext context,
  AcquisitionDiagnosticsReport report,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FsmDiagnosticsReportView(report: report),
  );
}

class FsmDiagnosticsReportView extends StatelessWidget {
  final AcquisitionDiagnosticsReport report;
  final DiagnosticsContentCopier? copyContent;

  const FsmDiagnosticsReportView({
    required this.report,
    this.copyContent,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Dimensions.paddingMedium,
          0,
          Dimensions.paddingMedium,
          Dimensions.paddingMedium,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.description_outlined,
                    color: ColorPalette.primary),
                const SizedBox(width: Dimensions.paddingSmall),
                Expanded(
                  child: Text(
                    'Log diagnostici registrazione',
                    style: textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Chiudi',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: Dimensions.paddingSmall),
            Text(
              'Il file contiene ${report.decisionCount} decisioni della FSM. '
              'Non include coordinate GPS.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: Dimensions.paddingMedium),
            DecoratedBox(
              decoration: BoxDecoration(
                color: ColorPalette.surfaceSofter,
                borderRadius:
                    BorderRadius.circular(Dimensions.borderRadiusMedium),
                border: Border.all(color: ColorPalette.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.all(Dimensions.paddingMedium),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Dimensions.paddingXSmall),
                    Text(
                      _formatBytes(report.sizeBytes),
                      style: textTheme.bodySmall
                          ?.copyWith(color: ColorPalette.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Dimensions.paddingMedium),
            _CopyDiagnosticsButton(
              content: report.content,
              copyContent: copyContent ?? _copyToClipboard,
            ),
            const SizedBox(height: Dimensions.paddingSmall),
            Builder(
              builder: (buttonContext) => FilledButton.icon(
                onPressed: () => _shareFile(buttonContext),
                icon: const Icon(Icons.ios_share),
                label: const Text('Condividi / salva file'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _copyToClipboard(String content) {
    return Clipboard.setData(ClipboardData(text: content));
  }

  Future<void> _shareFile(BuildContext context) async {
    try {
      final renderBox = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(report.filePath, mimeType: 'application/x-ndjson')],
          subject: 'Log diagnostici Mobility Diary',
          sharePositionOrigin: renderBox == null
              ? null
              : renderBox.localToGlobal(Offset.zero) & renderBox.size,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossibile condividere il file diagnostico.'),
          backgroundColor: ColorPalette.error,
        ),
      );
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kibibytes = bytes / 1024;
    if (kibibytes < 1024) return '${kibibytes.toStringAsFixed(1)} KB';
    return '${(kibibytes / 1024).toStringAsFixed(1)} MB';
  }
}

class _CopyDiagnosticsButton extends StatefulWidget {
  final String content;
  final DiagnosticsContentCopier copyContent;

  const _CopyDiagnosticsButton({
    required this.content,
    required this.copyContent,
  });

  @override
  State<_CopyDiagnosticsButton> createState() => _CopyDiagnosticsButtonState();
}

class _CopyDiagnosticsButtonState extends State<_CopyDiagnosticsButton> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await widget.copyContent(widget.content);
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _copied ? null : _copy,
      icon: Icon(_copied ? Icons.check : Icons.copy),
      label: Text(_copied ? 'Copiato' : 'Copia contenuto'),
    );
  }
}
