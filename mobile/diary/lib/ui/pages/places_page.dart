import 'package:auto_route/auto_route.dart';
import 'package:diary/model/entities/places/place_review.dart';
import 'package:diary/repositories/places_repository.dart';
import 'package:diary/routers/app_router.dart';
import 'package:diary/state_management/cubits/places_cubit/places_cubit.dart';
import 'package:diary/state_management/cubits/places_cubit/places_cubit_state.dart';
import 'package:diary/theme/semantic_colors.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/pages/place_presenter.dart';
import 'package:diary/ui/widgets/state_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Schermata di review dei Luoghi Significativi: sezioni Confermati e Candidati.
/// I dati arrivano da GET /mobility/places (user-scoped).
@RoutePage()
class PlacesPage extends StatelessWidget {
  const PlacesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          PlacesCubit(context.read<PlacesRepository>())..load(),
      child: Scaffold(
        appBar: AppBar(centerTitle: true, title: const Text('I miei luoghi')),
        body: const SafeArea(child: _PlacesBody()),
      ),
    );
  }
}

class _PlacesBody extends StatelessWidget {
  const _PlacesBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlacesCubit, PlacesCubitState>(
      builder: (context, state) {
        switch (state.status) {
          case PlacesStatus.initial:
          case PlacesStatus.loading:
            return const Center(child: CircularProgressIndicator());
          case PlacesStatus.empty:
            return const StateMessage(
              icon: Icons.place_outlined,
              text: 'Nessun luogo significativo ancora riconosciuto',
            );
          case PlacesStatus.error:
            return StateMessage(
              icon: Icons.error_outline,
              text: state.error ?? 'Errore nel caricamento',
              onRetry: () => context.read<PlacesCubit>().load(),
            );
          case PlacesStatus.miningInProgress:
            return _MiningInProgressMessage(
              onRefresh: () => context.read<PlacesCubit>().load(),
            );
          case PlacesStatus.loaded:
            return RefreshIndicator(
              onRefresh: () => context.read<PlacesCubit>().load(),
              child: ListView(
                padding: const EdgeInsets.all(Dimensions.paddingMedium),
                children: [
                  if (state.placeStatus != null && !state.canReview)
                    _PlaceMiningBanner(
                      statusText: placeMiningStatusTitle(state.placeStatus!),
                      message: placeMiningStatusMessage(state.placeStatus!),
                      onRefresh: () => context.read<PlacesCubit>().load(),
                    ),
                  _PlaceSection(title: 'Confermati', places: state.confirmed),
                  _PlaceSection(title: 'Candidati', places: state.candidates),
                  _PlaceSection(title: 'Rifiutati', places: state.rejected),
                ],
              ),
            );
        }
      },
    );
  }
}

/// PENDING/RUNNING:
class _MiningInProgressMessage extends StatelessWidget {
  final VoidCallback onRefresh;

  const _MiningInProgressMessage({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: Dimensions.paddingMedium),
            Text(
              'Analisi in corso, torna più tardi',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: Dimensions.paddingMedium),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Aggiorna stato'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceMiningBanner extends StatelessWidget {
  final String statusText;
  final String message;
  final VoidCallback onRefresh;

  const _PlaceMiningBanner({
    required this.statusText,
    required this.message,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: Dimensions.paddingMedium),
      color: Theme.of(
        context,
      ).extension<SemanticColors>()!.warning.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              statusText,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Dimensions.paddingSmall),
            Text(message),
            const SizedBox(height: Dimensions.paddingMedium),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Aggiorna stato'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceSection extends StatelessWidget {
  final String title;
  final List<PlaceReview> places;

  const _PlaceSection({required this.title, required this.places});

  @override
  Widget build(BuildContext context) {
    if (places.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: Dimensions.paddingSmall,
          ),
          child: Text(
            '$title (${places.length})',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        for (final place in places) _PlaceCard(place: place),
        const SizedBox(height: Dimensions.paddingMedium),
      ],
    );
  }
}

class _PlaceCard extends StatelessWidget {
  final PlaceReview place;

  const _PlaceCard({required this.place});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: Dimensions.paddingSmall),
      child: ListTile(
        leading: Icon(
          placeStateIcon(place),
          color: placeStateColor(
            place,
            sem: Theme.of(context).extension<SemanticColors>()!,
          ),
        ),
        title: Text(
          place.label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(placeEvidenceText(place)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await context.router.push(PlaceDetailRoute(place: place));
          // Al ritorno, ricarica la lista per riflettere le azioni manuali.
          if (context.mounted) context.read<PlacesCubit>().load();
        },
      ),
    );
  }
}
