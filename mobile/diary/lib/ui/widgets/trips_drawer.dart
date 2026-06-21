import 'package:auto_route/auto_route.dart';
import 'package:diary/network/dto/trip_list_item_dto.dart';
import 'package:diary/network/service/trips_service.dart';
import 'package:diary/routers/app_router.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit_state.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Drawer laterale con tutti i viaggi dell'utente e, per ognuno, il pulsante
/// "Vedi su mappa". La lista arriva dall'endpoint backend GET /mobility/trips.
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

class _TripsDrawerBody extends StatelessWidget {
  const _TripsDrawerBody();

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
                tooltip: 'Aggiorna',
                icon: const Icon(Icons.refresh),
                onPressed: () => context.read<TripsListCubit>().load(),
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
                  return ListView.separated(
                    itemCount: state.trips.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        _TripTile(trip: state.trips[index]),
                  );
              }
            },
          ),
        ),
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
                context.router.push(TripMapRoute(tripId: trip.id));
              }
            : null,
        icon: const Icon(Icons.map),
        label: const Text('Vedi su mappa'),
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
