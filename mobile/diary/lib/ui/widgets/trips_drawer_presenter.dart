import 'package:diary/model/entities/trips/trip_list_item.dart';

const kMinTripsPerDayGroup = 1;

class TripDayGroup {
  final DateTime day;
  final List<TripListItem> trips;

  const TripDayGroup({required this.day, required this.trips});
}

List<TripDayGroup> groupTrackTripsByLocalDay(
  List<TripListItem> trips, {
  int minTrips = kMinTripsPerDayGroup,
}) {
  final byDay = <DateTime, List<TripListItem>>{};
  for (final trip in trips) {
    if (!trip.hasTrack) continue;
    final local = trip.startedAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    byDay.putIfAbsent(day, () => []).add(trip);
  }

  final groups = [
    for (final entry in byDay.entries)
      if (entry.value.length >= minTrips)
        TripDayGroup(day: entry.key, trips: List.unmodifiable(entry.value)),
  ];
  groups.sort((a, b) => b.day.compareTo(a.day));
  return List.unmodifiable(groups);
}

List<TripListItem> sameLocalDayTrackTrips(
  List<TripListItem> trips,
  int tripId,
) {
  TripListItem? selected;
  for (final trip in trips) {
    if (trip.id == tripId) {
      selected = trip;
      break;
    }
  }
  if (selected == null) return const [];

  final selectedLocal = selected.startedAt.toLocal();
  final selectedDay = DateTime(
    selectedLocal.year,
    selectedLocal.month,
    selectedLocal.day,
  );
  final result = [
    for (final trip in trips)
      if (trip.hasTrack && _sameLocalDay(trip.startedAt, selectedDay)) trip,
  ];
  result.sort((a, b) => a.startedAt.compareTo(b.startedAt));
  return List.unmodifiable(result);
}

bool _sameLocalDay(DateTime value, DateTime day) {
  final local = value.toLocal();
  return local.year == day.year &&
      local.month == day.month &&
      local.day == day.day;
}
