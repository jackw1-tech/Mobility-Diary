import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:diary/ui/widgets/trip_map/trip_map_states.dart';
import 'package:diary/ui/widgets/trip_map/trip_track_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// in base allo stato emesso da TripTrackCubit mostri oppure no la mappa in TripDetailPage
// La differenza tra un trip con solo path e un trip con har completato (segmenti) è all'interno dell'oggeto state
class TripMapPage extends StatelessWidget {
  final Widget? topLeftOverlay;

  const TripMapPage({this.topLeftOverlay, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TripTrackCubit, TripTrackCubitState>(
      builder: (context, state) {
        switch (state.status) {
          case TripTrackStatus.initial:
          case TripTrackStatus.loading:
            return const Center(child: CircularProgressIndicator());
          case TripTrackStatus.loaded:
            return TripTrackMap(state: state, topLeftOverlay: topLeftOverlay);
          case TripTrackStatus.empty:
            return const EmptyTrack();
          case TripTrackStatus.error:
            return TrackError(
              message: state.error ?? 'Errore sconosciuto',
              onRetry: () => context.read<TripTrackCubit>().reload(),
            );
        }
      },
    );
  }
}
