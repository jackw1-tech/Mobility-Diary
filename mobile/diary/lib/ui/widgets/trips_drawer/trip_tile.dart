import 'package:diary/model/entities/trips/trip_list_item.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit_state.dart';
import 'package:diary/ui/widgets/trips_drawer/trip_tile_actions.dart';
import 'package:diary/utils/date_time_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Riga di un viaggio nel drawer. In modalita' `reloadable` mostra i pulsanti
/// Live e Carica, altrimenti dettaglio e menu azioni.
class TripTile extends StatelessWidget {
  final TripListItem trip;
  final bool reloadable;

  const TripTile({
    required this.trip,
    this.reloadable = false,
    super.key,
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
      trailing:
          reloadable ? _reloadActions(context) : _standardActions(context),
    );
  }

  Widget _reloadActions(BuildContext context) {
    return BlocBuilder<TripsListCubit, TripsListCubitState>(
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
              onPressed: isBusy ? null : () => playTripLive(context, trip),
              icon: const Icon(Icons.play_arrow_outlined),
              label: const Text('Live'),
              style: compactStyle,
            ),
            TextButton.icon(
              onPressed: isBusy ? null : () => startTripReload(context, trip),
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
              onPressed: () => openTripDetail(context, trip),
              icon: Icon(trip.hasTrack ? Icons.route : Icons.view_timeline),
            ),
            if (isMutating)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              PopupMenuButton<TripAction>(
                tooltip: 'Azioni viaggio',
                onSelected: (action) => handleTripAction(context, trip, action),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: TripAction.note,
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
                    value: TripAction.toggleReloadable,
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
                          : Text(reloadableUnavailableReason(trip)),
                    ),
                  ),
                  PopupMenuItem(
                    value: TripAction.delete,
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

  String _title(TripListItem trip) {
    final note = trip.note.trim();
    return note.isEmpty ? DateTimeUtils.formatDateTime(trip.startedAt) : note;
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
