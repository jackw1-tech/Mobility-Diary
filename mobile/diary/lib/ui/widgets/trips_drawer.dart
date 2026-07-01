import 'package:auto_route/auto_route.dart';
import 'package:diary/network/dto/trip_list_item_dto.dart';
import 'package:diary/network/dto/trip_reload_slots_dto.dart';
import 'package:diary/network/service/trips_service.dart';
import 'package:diary/routers/app_router.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit_state.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/widgets/trips_drawer_presenter.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Drawer laterale con tutti i viaggi dell'utente e, per ognuno, il pulsante
/// "Dettaglio". La lista arriva dall'endpoint backend GET /mobility/trips.
class TripsDrawer extends StatelessWidget {
  const TripsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TripsListCubit(context.read<TripsService>())..load(),
      child: const Drawer(child: SafeArea(child: _TripsDrawerBody())),
    );
  }
}

enum _TripsDrawerMode { list, days, reloadable }

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
  final List<TripListItemDto> trips;
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
      title: Text(_formatDay(group.day)),
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
          title: Text(_formatDay(group.day)),
          subtitle: Text('${group.trips.length} percorsi nella giornata'),
        ),
        const Divider(height: 1),
        for (final trip in group.trips) _TripTile(trip: trip),
      ],
    );
  }
}

class _TripTile extends StatelessWidget {
  final TripListItemDto trip;
  final bool reloadable;

  const _TripTile({
    required this.trip,
    this.reloadable = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(_formatDate(trip.startedAt.toLocal())),
      subtitle: Text(_subtitle(trip)),
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
          : TextButton.icon(
              onPressed: trip.hasTrack
                  ? () {
                      Scaffold.of(context).closeDrawer();
                      context.router.push(TripDetailRoute(tripId: trip.id));
                    }
                  : null,
              icon: const Icon(Icons.route),
              label: const Text('Dettaglio'),
            ),
    );
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
    try {
      final slots =
          await context.read<TripsService>().fetchReloadSlots(trip.id);
      if (!context.mounted) return null;
      if (slots.slots.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nessuno slot libero nel passato')),
        );
        return null;
      }
      return showModalBottomSheet<DateTime>(
        context: context,
        showDragHandle: true,
        builder: (_) => _ReloadSlotSheet(slots: slots.slots),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
      return null;
    }
  }

  Future<double?> _pickReplaySpeed(BuildContext context) {
    return showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _ReplaySpeedSheet(),
    );
  }

  String _subtitle(TripListItemDto trip) {
    final distance = trip.distanceMeters;
    if (distance == null || distance <= 0) {
      return trip.hasTrack ? 'Traiettoria disponibile' : 'Nessuna traiettoria';
    }
    if (distance >= 1000) {
      return '${(distance / 1000).toStringAsFixed(1)} km';
    }
    return '${distance.toStringAsFixed(0)} m';
  }
}

class _ReloadSlotSheet extends StatelessWidget {
  final List<TripReloadSlotDto> slots;

  const _ReloadSlotSheet({required this.slots});

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

class _ReplaySpeedSheet extends StatelessWidget {
  const _ReplaySpeedSheet();

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

String _formatDate(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
}

String _formatDay(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)}/${dt.year}';
}
