import 'package:auto_route/auto_route.dart';
import 'package:diary/repositories/trips_repository.dart';
import 'package:diary/routers/app_router.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit_state.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/widgets/trips_drawer/drawer_message.dart';
import 'package:diary/ui/widgets/trips_drawer/trips_drawer_mode.dart';
import 'package:diary/ui/widgets/trips_drawer/trips_views.dart';
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
      create: (context) => TripsListCubit(
        context.read<TripsRepository>(),
      )..load(),
      child: const Drawer(child: SafeArea(child: _TripsDrawerBody())),
    );
  }
}

class _TripsDrawerBody extends StatefulWidget {
  const _TripsDrawerBody();

  @override
  State<_TripsDrawerBody> createState() => _TripsDrawerBodyState();
}

class _TripsDrawerBodyState extends State<_TripsDrawerBody> {
  TripsDrawerMode _mode = TripsDrawerMode.list;
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
          child: TripsDrawerModeToggle(
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
                  return DrawerMessage(
                    icon: _mode == TripsDrawerMode.reloadable
                        ? Icons.replay_outlined
                        : Icons.map_outlined,
                    text: _mode == TripsDrawerMode.reloadable
                        ? 'Nessun viaggio ricaricabile'
                        : 'Nessun viaggio ancora sincronizzato',
                  );
                case TripsListStatus.error:
                  return DrawerMessage(
                    icon: Icons.error_outline,
                    text: state.error ?? 'Errore nel caricamento',
                    onRetry: () => _loadMode(context),
                  );
                case TripsListStatus.loaded:
                  return _mode == TripsDrawerMode.list
                      ? TripsListView(trips: state.trips)
                      : _mode == TripsDrawerMode.reloadable
                          ? TripsListView(
                              trips: state.trips,
                              reloadable: true,
                            )
                          : TripsByDayView(
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

  void _changeMode(TripsDrawerMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _selectedDay = null;
    });
    _loadMode(context);
  }

  void _loadMode(BuildContext context) {
    final cubit = context.read<TripsListCubit>();
    if (_mode == TripsDrawerMode.reloadable) {
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
