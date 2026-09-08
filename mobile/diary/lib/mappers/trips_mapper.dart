import 'package:diary/model/entities/trips/trip_list_item.dart';
import 'package:diary/model/entities/trips/trip_enums.dart';
import 'package:diary/model/entities/trips/trip_reload.dart';
import 'package:diary/model/entities/trips/trip_track.dart';
import 'package:diary/network/dto/trip_list_item_dto.dart';
import 'package:diary/network/dto/trip_reload_dto.dart';
import 'package:diary/network/dto/trip_reload_slots_dto.dart';
import 'package:diary/network/dto/trip_track_dto.dart';

class TripsMapper {
  TripListItem mapTripListItem(TripListItemDto dto) => TripListItem(
        id: dto.id,
        startedAt: dto.startedAt,
        endedAt: dto.endedAt,
        status: TripStatus.fromWire(dto.status),
        distanceMeters: dto.distanceMeters,
        note: dto.note,
        hasTrack: dto.hasTrack,
        isReloadable: dto.isReloadable,
        isDerived: dto.isDerived,
        canDelete: dto.canDelete,
        canToggleReloadable: dto.canToggleReloadable,
        canEditNote: dto.canEditNote,
      );

  List<TripListItem> mapTripListItems(List<TripListItemDto> dtos) {
    return dtos.map(mapTripListItem).toList(growable: false);
  }

  TripReload mapTripReload(TripReloadDto dto) => TripReload(
        uploadId: dto.uploadId,
        tripId: dto.tripId,
        coreStatus: dto.coreStatus,
        rawStatus: dto.rawStatus,
        gpsPoints: dto.gpsPoints,
        stateTransitions: dto.stateTransitions,
        pathPoints: dto.pathPoints,
        distanceMeters: dto.distanceMeters,
        mapAvailable: dto.mapAvailable,
      );

  TripReloadSlots mapTripReloadSlots(TripReloadSlotsDto dto) => TripReloadSlots(
        sourceTripId: dto.sourceTripId,
        durationSeconds: dto.durationSeconds,
        slots: dto.slots.map(mapTripReloadSlot).toList(growable: false),
      );

  TripReloadSlot mapTripReloadSlot(TripReloadSlotDto dto) => TripReloadSlot(
        startedAt: dto.startedAt,
        endedAt: dto.endedAt,
      );

  TripTrack mapTripTrack(TripTrackDto dto) => TripTrack(
        tripId: dto.tripId,
        pointCount: dto.pointCount,
        distanceMeters: dto.distanceMeters,
        geojson: dto.geojson,
        bbox: dto.bbox,
      );

  TripDiary mapTripDiary(TripDiaryDto dto) => TripDiary(
        tripId: dto.tripId,
        status: TripDiaryStatus.fromWire(dto.status),
        processed: dto.processed,
        processingFailed: dto.processingFailed,
        processingFailureReason: dto.processingFailureReason,
        segments: dto.segments.map(mapTripDiarySegment).toList(growable: false),
        places: dto.places.map(mapTripDiaryPlace).toList(growable: false),
      );

  TripDiarySegment mapTripDiarySegment(TripDiarySegmentDto dto) {
    return TripDiarySegment(
      kind: TripDiarySegmentKind.fromWire(dto.kind),
      startTimestamp: dto.startTimestamp,
      endTimestamp: dto.endTimestamp,
      activity: MobilityActivity.fromWire(dto.activityLabel),
      distanceMeters: dto.distanceMeters,
      pathGeojson: dto.pathGeojson,
      place: dto.place == null ? null : mapTripDiaryPlace(dto.place!),
    );
  }

  TripDiaryPlace mapTripDiaryPlace(TripDiaryPlaceDto dto) => TripDiaryPlace(
        id: dto.id,
        latitude: dto.latitude,
        longitude: dto.longitude,
        radiusMeters: dto.radiusMeters,
        dwellSeconds: dto.dwellSeconds,
        label: dto.label,
      );
}
