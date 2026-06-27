import 'package:latlong2/latlong.dart';

/// Un Luogo Significativo user-scoped per la schermata di review, con le visite
/// di supporto (evidenza di mappa) e il contesto che spiega perche' e' proposto.
class PlaceReviewDto {
  final int id;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String state; // CANDIDATE / CONFIRMED / REJECTED
  final String label;
  final String category;
  final String customName;
  final int visitCount;
  final int distinctDays;
  final List<PlaceVisitDto> visits;

  const PlaceReviewDto({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.state,
    required this.label,
    required this.category,
    required this.customName,
    required this.visitCount,
    required this.distinctDays,
    required this.visits,
  });

  bool get isConfirmed => state == 'CONFIRMED';
  bool get isCandidate => state == 'CANDIDATE';
  bool get isRejected => state == 'REJECTED';

  LatLng get center => LatLng(latitude, longitude);

  factory PlaceReviewDto.fromJson(Map<String, dynamic> json) {
    return PlaceReviewDto(
      id: json['id'] as int,
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lon'] as num).toDouble(),
      radiusMeters: (json['radius_meters'] as num? ?? 0).toDouble(),
      state: json['state'] as String? ?? '',
      label: json['label'] as String? ?? '',
      category: json['category'] as String? ?? '',
      customName: json['custom_name'] as String? ?? '',
      visitCount: json['visit_count'] as int? ?? 0,
      distinctDays: json['distinct_days'] as int? ?? 0,
      visits: (json['visits'] as List<dynamic>? ?? const [])
          .map((value) => PlaceVisitDto.fromJson(
                Map<String, dynamic>.from(value as Map<dynamic, dynamic>),
              ))
          .toList(growable: false),
    );
  }
}

class PlaceVisitDto {
  final double latitude;
  final double longitude;
  final DateTime startedAt;
  final DateTime endedAt;
  final int pointCount;

  const PlaceVisitDto({
    required this.latitude,
    required this.longitude,
    required this.startedAt,
    required this.endedAt,
    required this.pointCount,
  });

  LatLng get center => LatLng(latitude, longitude);

  factory PlaceVisitDto.fromJson(Map<String, dynamic> json) {
    return PlaceVisitDto(
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lon'] as num).toDouble(),
      startedAt: DateTime.parse(json['started_at'] as String),
      endedAt: DateTime.parse(json['ended_at'] as String),
      pointCount: json['point_count'] as int? ?? 0,
    );
  }
}
