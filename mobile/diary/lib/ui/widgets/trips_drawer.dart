import 'package:auto_route/auto_route.dart';
import 'package:diary/network/dto/trip_list_item_dto.dart';
import 'package:diary/network/service/trips_service.dart';
import 'package:diary/routers/app_router.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit_state.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/widgets/trips_drawer_presenter.dart';
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

enum _TripsDrawerMode { list, days }

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
        Expanded(
          child: BlocBuilder<TripsListCubit, TripsListCubitState>(
            builder: (context, state) {
              switch (state.status) {
                case TripsListStatus.initial:
                case TripsListStatus.loading:
                  return const Center(child: CircularProgressIndicator());
                case TripsListStatus.empty:
                  return const _DrawerMessage(
                    icon: Icons.map_outlined,
                    text: 'Nessun viaggio ancora sincronizzato',
                  );
                case TripsListStatus.error:
                  return _DrawerMessage(
                    icon: Icons.error_outline,
                    text: state.error ?? 'Errore nel caricamento',
                    onRetry: () => context.read<TripsListCubit>().load(),
                  );
                case TripsListStatus.loaded:
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(Dimensions.paddingMedium),
                        child: _DrawerModeToggle(
                          value: _mode,
                          onChanged: _changeMode,
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: _mode == _TripsDrawerMode.list
                            ? _TripsListView(trips: state.trips)
                            : _TripsByDayView(
                                groups: groupTrackTripsByLocalDay(state.trips),
                                selectedDay: _selectedDay,
                                onSelectDay: _selectDay,
                                onBackToDays: _backToDays,
                              ),
                      ),
                    ],
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
          label: Text('Lista'),
        ),
        ButtonSegment(
          value: _TripsDrawerMode.days,
          icon: Icon(Icons.calendar_month_outlined),
          label: Text('Giorni'),
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

  const _TripsListView({required this.trips});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: trips.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _TripTile(trip: trips[index]),
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

  const _TripTile({required this.trip});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(_formatDate(trip.startedAt.toLocal())),
      subtitle: Text(_subtitle(trip)),
      trailing: TextButton.icon(
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
