import 'package:diary/utils/app_result.dart';
import 'package:diary/model/entities/trips/trip_list_item.dart';
import 'package:diary/model/entities/trips/trip_reload.dart';

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
