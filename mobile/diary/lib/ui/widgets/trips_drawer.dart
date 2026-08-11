import 'package:auto_route/auto_route.dart';
import 'package:diary/model/entities/trips/trip_list_item.dart';
import 'package:diary/repositories/trips_repository.dart';
import 'package:diary/routers/app_router.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit_state.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/widgets/trip_reload_sheets.dart';
import 'package:diary/ui/widgets/trips_drawer_presenter.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:diary/utils/date_time_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Drawer laterale con tutti i viaggi dell'utente e, per ognuno, il pulsante
/// "Dettaglio". La lista arriva dall'endpoint backend GET /mobility/trips.
class TripsDrawer extends StatelessWidget {
  const TripsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TripsListCubit(
        context.read<TripsRepository>(),
      )..load(),
      child: const Drawer(child: SafeArea(child: _TripsDrawerBody())),
    );
  }
}

enum _TripsDrawerMode { list, days, reloadable }

enum _TripAction { note, toggleReloadable, delete }

class _TripsDrawerBody extends StatefulWidget {
  const _TripsDrawerBody();

  @override
  State<_TripsDrawerBody> createState() => _TripsDrawerBodyState();
}

class _TripsDrawerBodyState extends State<_TripsDrawerBody> {
  _TripsDrawerMode _mode = _TripsDrawerMode.list;
  TripDayGroup? _selectedDay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(Dimensions.paddingMedium),
          child: Row(
            children: [
              const Icon(Icons.route),
              const SizedBox(width: Dimensions.paddingSmall),
              Text(
                'I miei viaggi',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Profilo',
                icon: const Icon(Icons.person_outline),
                onPressed: () {
                  Scaffold.of(context).closeDrawer();
                  context.router.push(const ProfileRoute());
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(Dimensions.paddingMedium),
          child: _DrawerModeToggle(
            value: _mode,
            onChanged: _changeMode,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: BlocBuilder<TripsListCubit, TripsListCubitState>(
            builder: (context, state) {
              switch (state.status) {
                case TripsListStatus.initial:
                case TripsListStatus.loading:
                  return const Center(child: CircularProgressIndicator());
                case TripsListStatus.empty:
                  return _DrawerMessage(
                    icon: _mode == _TripsDrawerMode.reloadable
                        ? Icons.replay_outlined
                        : Icons.map_outlined,
                    text: _mode == _TripsDrawerMode.reloadable
                        ? 'Nessun viaggio ricaricabile'
                        : 'Nessun viaggio ancora sincronizzato',
                  );
                case TripsListStatus.error:
                  return _DrawerMessage(
                    icon: Icons.error_outline,
                    text: state.error ?? 'Errore nel caricamento',
                    onRetry: () => _loadMode(context),
                  );
                case TripsListStatus.loaded:
                  return _mode == _TripsDrawerMode.list
                      ? _TripsListView(trips: state.trips)
                      : _mode == _TripsDrawerMode.reloadable
                          ? _TripsListView(
                              trips: state.trips,
                              reloadable: true,
                            )
                          : _TripsByDayView(
                              groups: groupTrackTripsByLocalDay(state.trips),
                              selectedDay: _selectedDay,
                              onSelectDay: _selectDay,
                              onBackToDays: _backToDays,
                            );
              }
            },
          ),
        ),
      ],
    );
  }

  void _changeMode(_TripsDrawerMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _selectedDay = null;
    });
    _loadMode(context);
  }

  void _loadMode(BuildContext context) {
    final cubit = context.read<TripsListCubit>();
    if (_mode == _TripsDrawerMode.reloadable) {
      cubit.loadReloadable();
    } else {
      cubit.load();
    }
  }

  void _selectDay(TripDayGroup group) {
    setState(() => _selectedDay = group);
  }

  void _backToDays() {
    setState(() => _selectedDay = null);
  }
}

class _DrawerModeToggle extends StatelessWidget {
  final _TripsDrawerMode value;
  final ValueChanged<_TripsDrawerMode> onChanged;

  const _DrawerModeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_TripsDrawerMode>(
      segments: const [
        ButtonSegment(
          value: _TripsDrawerMode.list,
          icon: Icon(Icons.format_list_bulleted),
        ),
        ButtonSegment(
          value: _TripsDrawerMode.days,
          icon: Icon(Icons.calendar_month_outlined),
        ),
        ButtonSegment(
          value: _TripsDrawerMode.reloadable,
          icon: Icon(Icons.replay_outlined),
        ),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (selected) => onChanged(selected.first),
    );
  }
}

class _TripsListView extends StatelessWidget {
  final List<TripListItem> trips;
  final bool reloadable;

  const _TripsListView({
    required this.trips,
    this.reloadable = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: trips.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _TripTile(
        trip: trips[index],
        reloadable: reloadable,
      ),
    );
  }
}

class _TripsByDayView extends StatelessWidget {
  final List<TripDayGroup> groups;
  final TripDayGroup? selectedDay;
  final ValueChanged<TripDayGroup> onSelectDay;
  final VoidCallback onBackToDays;

  const _TripsByDayView({
    required this.groups,
    required this.selectedDay,
    required this.onSelectDay,
    required this.onBackToDays,
  });

  @override
  Widget build(BuildContext context) {
    final day = selectedDay;
    if (day != null) {
      return _DayTripsView(
        group: day,
        onBack: onBackToDays,
      );
    }

    if (groups.isEmpty) {
      return const _DrawerMessage(
        icon: Icons.calendar_month_outlined,
        text: 'Nessun giorno con percorsi disponibili',
      );
    }

    return ListView.separated(
      itemCount: groups.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _DayGroupTile(
        group: groups[index],
        onTap: () => onSelectDay(groups[index]),
      ),
    );
  }
}

class _DayGroupTile extends StatelessWidget {
  final TripDayGroup group;
  final VoidCallback onTap;

  const _DayGroupTile({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = group.trips.length;
    return ListTile(
      leading: const Icon(Icons.calendar_today_outlined),
      title: Text(DateTimeUtils.formatDate(group.day)),
      subtitle: Text(count == 1 ? '1 percorso' : '$count percorsi'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _DayTripsView extends StatelessWidget {
  final TripDayGroup group;
  final VoidCallback onBack;

  const _DayTripsView({
    required this.group,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: Dimensions.paddingMedium),
      children: [
        ListTile(
          leading: IconButton(
            tooltip: 'Torna ai giorni',
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
          ),
          title: Text(DateTimeUtils.formatDate(group.day)),
          subtitle: Text('${group.trips.length} percorsi nella giornata'),
        ),
        const Divider(height: 1),
        for (final trip in group.trips) _TripTile(trip: trip),
      ],
    );
  }
}

class _TripTile extends StatelessWidget {
  final TripListItem trip;
  final bool reloadable;

  const _TripTile({
    required this.trip,
    this.reloadable = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        _title(trip),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _subtitle(trip),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: reloadable
          ? BlocBuilder<TripsListCubit, TripsListCubitState>(
              builder: (context, state) {
                final isReloading = state.reloadingTripId == trip.id;
                final isBusy = state.reloadingTripId != null;
                final compactStyle = TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: isBusy ? null : () => _playLive(context),
                      icon: const Icon(Icons.play_arrow_outlined),
                      label: const Text('Live'),
                      style: compactStyle,
                    ),
                    TextButton.icon(
                      onPressed: isBusy ? null : () => _reload(context),
                      icon: isReloading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.file_upload_outlined),
                      label: const Text('Carica'),
                      style: compactStyle,
                    ),
                  ],
                );
              },
            )
          : _standardActions(context),
    );
  }

  Widget _standardActions(BuildContext context) {
    return BlocBuilder<TripsListCubit, TripsListCubitState>(
      builder: (context, state) {
        final isMutating = state.mutatingTripId == trip.id;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Dettaglio',
              onPressed: trip.hasTrack ? () => _openDetail(context) : null,
              icon: const Icon(Icons.route),
            ),
            if (isMutating)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              PopupMenuButton<_TripAction>(
                tooltip: 'Azioni viaggio',
                onSelected: (action) => _handleAction(context, action),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _TripAction.note,
                    enabled: trip.canEditNote,
                    child: ListTile(
                      leading: const Icon(Icons.notes_outlined),
                      title: const Text('Nota'),
                      subtitle: trip.canEditNote
                          ? null
                          : const Text('Disponibile a viaggio completato'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _TripAction.toggleReloadable,
                    enabled: trip.canToggleReloadable,
                    child: ListTile(
                      leading: Icon(
                        trip.isReloadable
                            ? Icons.replay_circle_filled_outlined
                            : Icons.replay_outlined,
                      ),
                      title: Text(
                        trip.isReloadable
                            ? 'Rimuovi riutilizzo'
                            : 'Rendi riutilizzabile',
                      ),
                      subtitle: trip.canToggleReloadable
                          ? null
                          : Text(_reloadableUnavailableReason(trip)),
                    ),
                  ),
                  PopupMenuItem(
                    value: _TripAction.delete,
                    enabled: trip.canDelete,
                    child: const ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Elimina'),
                      subtitle: Text('Non disponibile se gia clonato'),
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  void _openDetail(BuildContext context) {
    Scaffold.of(context).closeDrawer();
    context.router.push(TripDetailRoute(tripId: trip.id));
  }

  Future<void> _handleAction(BuildContext context, _TripAction action) async {
    switch (action) {
      case _TripAction.note:
        final note = await _editNote(context);
        if (note != null && context.mounted) {
          await _setNote(context, note);
        }
        break;
      case _TripAction.toggleReloadable:
        final confirmed = await _confirmReloadableChange(context);
        if (confirmed == true && context.mounted) {
          await _setReloadable(context, !trip.isReloadable);
        }
        break;
      case _TripAction.delete:
        final confirmed = await _confirmDelete(context);
        if (confirmed == true && context.mounted) {
          await _delete(context);
        }
        break;
    }
  }

  Future<void> _setNote(BuildContext context, String note) async {
    await _runMutation(
      context,
      (cubit) => cubit.updateTripNote(trip.id, note),
      successMessage: 'Nota salvata',
      fallbackError: 'Nota non salvata',
    );
  }

  Future<void> _setReloadable(BuildContext context, bool value) async {
    await _runMutation(
      context,
      (cubit) => cubit.setTripReloadable(trip.id, value),
      successMessage: value ? 'Viaggio riutilizzabile' : 'Riutilizzo rimosso',
      fallbackError: 'Modifica non riuscita',
    );
  }

  Future<String?> _editNote(BuildContext context) async {
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

  Future<void> _delete(BuildContext context) async {
    await _runMutation(
      context,
      (cubit) => cubit.deleteTrip(trip.id),
      successMessage: 'Viaggio eliminato',
      fallbackError: 'Eliminazione non riuscita',
    );
  }

  Future<void> _runMutation(
    BuildContext context,
    Future<bool> Function(TripsListCubit cubit) action, {
    required String successMessage,
    required String fallbackError,
  }) async {
    final ok = await action(context.read<TripsListCubit>());
    if (!context.mounted) return;
    final state = context.read<TripsListCubit>().state;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(ok ? successMessage : state.mutationError ?? fallbackError),
      ),
    );
  }

  Future<bool?> _confirmReloadableChange(BuildContext context) {
    final enabling = !trip.isReloadable;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            enabling ? 'Rendere riutilizzabile?' : 'Rimuovere riutilizzo?'),
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

  String _reloadableUnavailableReason(TripListItem trip) {
    if (trip.isDerived) return 'Non disponibile sui viaggi derivati';
    if (trip.isReloadable) return 'Gia usato come sorgente';
    return 'Richiede telemetrie complete';
  }

  Future<void> _playLive(BuildContext context) async {
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

    final selectedStart = await _pickReloadStart(context);
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

  Future<void> _reload(BuildContext context) async {
    final selectedStart = await _pickReloadStart(context);
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

  Future<DateTime?> _pickReloadStart(BuildContext context) async {
    final result = await context.read<TripsRepository>().fetchReloadSlots(
          trip.id,
        );
    if (!context.mounted) return null;
    final failure = result.failure;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure.message)),
      );
      return null;
    }
    final slots = result.requireValue;
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

  String _title(TripListItem trip) {
    final note = trip.note.trim();
    return note.isEmpty
        ? DateTimeUtils.formatDateTime(trip.startedAt)
        : note;
  }

  String _subtitle(TripListItem trip) {
    final prefix = trip.note.trim().isEmpty
        ? ''
        : '${DateTimeUtils.formatDateTime(trip.startedAt)} - ';
    final distance = trip.distanceMeters;
    if (distance == null || distance <= 0) {
      return trip.hasTrack
          ? '${prefix}Traiettoria disponibile'
          : '${prefix}Nessuna traiettoria';
    }
    if (distance >= 1000) {
      return '$prefix${(distance / 1000).toStringAsFixed(1)} km';
    }
    return '$prefix${distance.toStringAsFixed(0)} m';
  }
}

class _DrawerMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  const _DrawerMessage({
    required this.icon,
    required this.text,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: ColorPalette.textSecondary),
            const SizedBox(height: Dimensions.paddingSmall),
            Text(text, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: Dimensions.paddingSmall),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Riprova'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

