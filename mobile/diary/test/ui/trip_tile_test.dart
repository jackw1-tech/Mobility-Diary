import 'package:diary/model/entities/trips/trip_enums.dart';
import 'package:diary/model/entities/trips/trip_list_item.dart';
import 'package:diary/model/entities/trips/trip_reload.dart';
import 'package:diary/repositories/trips_repository.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit.dart';
import 'package:diary/ui/widgets/trips_drawer/trip_tile.dart';
import 'package:diary/utils/app_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens detail access for a trip without a trajectory',
      (tester) async {
    final cubit = TripsListCubit(_UnusedTripsRepository());
    addTearDown(cubit.close);
    final trip = TripListItem(
      id: 1,
      startedAt: DateTime.utc(2026, 9, 4, 10),
      endedAt: DateTime.utc(2026, 9, 4, 11),
      status: TripStatus.processed,
      distanceMeters: null,
      hasTrack: false,
    );

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(home: Scaffold(body: TripTile(trip: trip))),
      ),
    );

    final button = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .singleWhere((button) => button.tooltip == 'Dettaglio');
    expect(button.onPressed, isNotNull);
  });
}

class _UnusedTripsRepository implements TripsRepository {
  @override
  Future<AppResult<void>> deleteTrip(int tripId) => throw UnimplementedError();

  @override
  Future<AppResult<List<TripListItem>>> fetchReloadableTrips() =>
      throw UnimplementedError();

  @override
  Future<AppResult<TripReloadSlots>> fetchReloadSlots(int sourceTripId) =>
      throw UnimplementedError();

  @override
  Future<AppResult<List<TripListItem>>> fetchTrips() =>
      throw UnimplementedError();

  @override
  Future<AppResult<TripReload>> reloadTrip({
    required int sourceTripId,
    DateTime? scheduledStartAt,
  }) =>
      throw UnimplementedError();

  @override
  Future<AppResult<TripListItem>> setTripReloadable({
    required int tripId,
    required bool isReloadable,
  }) =>
      throw UnimplementedError();

  @override
  Future<AppResult<TripListItem>> updateTripNote({
    required int tripId,
    required String note,
  }) =>
      throw UnimplementedError();
}
