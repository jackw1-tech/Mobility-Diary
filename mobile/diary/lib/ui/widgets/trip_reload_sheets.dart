import 'package:diary/features/trips/domain/trip_reload.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:flutter/material.dart';

class ReloadSlotSheet extends StatelessWidget {
  final List<TripReloadSlot> slots;

  const ReloadSlotSheet({super.key, required this.slots});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Dimensions.paddingMedium,
                0,
                Dimensions.paddingMedium,
                Dimensions.paddingSmall,
              ),
              child: Text(
                'Scegli data di inizio',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: slots.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final slot = slots[index];
                  return ListTile(
                    leading: const Icon(Icons.event_available_outlined),
                    title: Text(_formatDate(slot.startedAt.toLocal())),
                    subtitle: Text(
                      'Fine prevista ${_formatDate(slot.endedAt.toLocal())}',
                    ),
                    onTap: () => Navigator.of(context).pop(slot.startedAt),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReplaySpeedSheet extends StatelessWidget {
  const ReplaySpeedSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Dimensions.paddingMedium,
              0,
              Dimensions.paddingMedium,
              Dimensions.paddingSmall,
            ),
            child: Text(
              'Velocità replay',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          for (final speed in const [1.0, 2.0, 5.0])
            ListTile(
              leading: const Icon(Icons.speed_outlined),
              title: Text('${speed.toStringAsFixed(0)}x'),
              onTap: () => Navigator.of(context).pop(speed),
            ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
}
