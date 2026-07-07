import 'package:diary/features/common/domain/app_result.dart';
import 'package:diary/features/trips/domain/trip_list_item.dart';
import 'package:diary/features/trips/domain/trip_reload.dart';

abstract class TripsRepository {
  Future<AppResult<List<TripListItem>>> fetchTrips();

  Future<AppResult<List<TripListItem>>> fetchReloadableTrips();

  Future<AppResult<TripReloadSlots>> fetchReloadSlots(int sourceTripId);

  Future<AppResult<void>> deleteTrip(int tripId);

  Future<AppResult<TripListItem>> setTripReloadable({
    required int tripId,
    required bool isReloadable,
  });

  Future<AppResult<TripListItem>> updateTripNote({
    required int tripId,
    required String note,
  });

  Future<AppResult<TripReload>> reloadTrip({
    required int sourceTripId,
    DateTime? scheduledStartAt,
  });
}
