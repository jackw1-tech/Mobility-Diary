import 'package:auto_route/auto_route.dart';
import 'package:diary/model/entities/trips/trip_list_item.dart';
import 'package:diary/routers/app_router.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit.dart';
import 'package:diary/ui/widgets/trip_reload_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum TripAction { note, toggleReloadable, delete }


void openTripDetail(BuildContext context, TripListItem trip) {
  Scaffold.of(context).closeDrawer();
  context.router.push(TripDetailRoute(tripId: trip.id));
}

String reloadableUnavailableReason(TripListItem trip) {
  if (trip.isDerived) return 'Non disponibile sui viaggi derivati';
  if (trip.isReloadable) return 'Gia usato come sorgente';
  return 'Richiede telemetrie complete';
}

Future<void> handleTripAction(
  BuildContext context,
  TripListItem trip,
  TripAction action,
) async {
  switch (action) {
    case TripAction.note:
      final note = await _editNote(context, trip);
      if (note != null && context.mounted) {
        await _setNote(context, trip, note);
      }
      break;
    case TripAction.toggleReloadable:
      final confirmed = await _confirmReloadableChange(context, trip);
      if (confirmed == true && context.mounted) {
        await _setReloadable(context, trip, !trip.isReloadable);
      }
      break;
    case TripAction.delete:
      final confirmed = await _confirmDelete(context);
      if (confirmed == true && context.mounted) {
        await _delete(context, trip);
      }
      break;
  }
}

Future<void> playTripLive(BuildContext context, TripListItem trip) async {
  final acquisitionCubit = context.read<AcquisitionCubit>();
  if (acquisitionCubit.state.isTracking) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Viaggio in corso attivo. Impossibile avviare il replay.'),
      ),
    );
    return;
  }

  final selectedStart = await pickReloadStart(context, trip);
  if (selectedStart == null || !context.mounted) return;
  final replaySpeed = await _pickReplaySpeed(context);
  if (replaySpeed == null || !context.mounted) return;

  try {
    await acquisitionCubit.startReplay(
      trip.id,
      scheduledStartAt: selectedStart,
      replaySpeedMultiplier: replaySpeed,
    );
    if (!context.mounted) return;
    Scaffold.of(context).closeDrawer();
  } catch (e) {
    if (!context.mounted) return;
    final error = acquisitionCubit.state.errorMessage;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Errore avvio replay')),
    );
  }
}

// Funzione che viene eseguita quando esegup un caricamento diretto
Future<void> startTripReload(BuildContext context, TripListItem trip) async {
  final selectedStart = await pickReloadStart(context, trip);
  if (selectedStart == null || !context.mounted) return;
  final tripId = await context.read<TripsListCubit>().reloadTrip(
        trip.id,
        scheduledStartAt: selectedStart,
      );
  if (!context.mounted) return;
  if (tripId == null) {
    final error = context.read<TripsListCubit>().state.reloadError;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Ricaricamento non riuscito')),
    );
    return;
  }
  Scaffold.of(context).closeDrawer();
  context.router.push(TripDetailRoute(tripId: tripId));
}

/// Funzione che mostra la lista di slot disponibili per replay o caricamento diretto
Future<DateTime?> pickReloadStart(
  BuildContext context,
  TripListItem trip,
) async {
  final cubit = context.read<TripsListCubit>();
  final slots = await cubit.loadReloadSlots(trip.id);
  if (!context.mounted) return null;
  if (slots == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(cubit.state.reloadError ?? 'Slot non disponibili'),
      ),
    );
    return null;
  }
  if (slots.slots.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nessuno slot libero nel passato')),
    );
    return null;
  }
  return showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    builder: (_) => ReloadSlotSheet(slots: slots.slots),
  );
}

Future<double?> _pickReplaySpeed(BuildContext context) {
  return showModalBottomSheet<double>(
    context: context,
    showDragHandle: true,
    builder: (_) => const ReplaySpeedSheet(),
  );
}

Future<void> _setNote(
  BuildContext context,
  TripListItem trip,
  String note,
) async {
  await _runMutation(
    context,
    (cubit) => cubit.updateTripNote(trip.id, note),
    successMessage: 'Nota salvata',
  );
}

Future<void> _setReloadable(
  BuildContext context,
  TripListItem trip,
  bool value,
) async {
  await _runMutation(
    context,
    (cubit) => cubit.setTripReloadable(trip.id, value),
    successMessage: value ? 'Viaggio riutilizzabile' : 'Riutilizzo rimosso',
  );
}

Future<void> _delete(BuildContext context, TripListItem trip) async {
  await _runMutation(
    context,
    (cubit) => cubit.deleteTrip(trip.id),
    successMessage: 'Viaggio eliminato',
  );
}

Future<void> _runMutation(
  BuildContext context,
  Future<String?> Function(TripsListCubit cubit) action, {
  required String successMessage,
}) async {
  final error = await action(context.read<TripsListCubit>());
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(error ?? successMessage),
    ),
  );
}

Future<String?> _editNote(BuildContext context, TripListItem trip) async {
  final controller = TextEditingController(text: trip.note);
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nota viaggio'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: 'Aggiungi una nota',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: const Text('Svuota'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<bool?> _confirmReloadableChange(
  BuildContext context,
  TripListItem trip,
) {
  final enabling = !trip.isReloadable;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title:
          Text(enabling ? 'Rendere riutilizzabile?' : 'Rimuovere riutilizzo?'),
      content: Text(
        enabling
            ? 'Il viaggio potra essere usato come sorgente per nuovi caricamenti.'
            : 'Puoi rimuoverlo solo se non e stato ancora clonato.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(enabling ? 'Conferma' : 'Rimuovi'),
        ),
      ],
    ),
  );
}

Future<bool?> _confirmDelete(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Eliminare viaggio?'),
      content: const Text(
        'Verranno rimossi dati del database e file nel bucket. Non puoi eliminare un viaggio gia clonato.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Elimina'),
        ),
      ],
    ),
  );
}
