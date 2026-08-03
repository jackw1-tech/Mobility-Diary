import 'package:diary/utils/app_result.dart';
import 'package:diary/model/entities/privacy/trip_privacy_export.dart';
import 'package:diary/mappers/trip_privacy_export_mapper.dart';
import 'package:diary/network/service/trip_privacy_export_service.dart';
import 'package:diary/repositories/trip_privacy_export_repository.dart';

class TripPrivacyExportRepositoryImpl implements TripPrivacyExportRepository {
  final TripPrivacyExportService _service;
  final TripPrivacyExportMapper _mapper;

  const TripPrivacyExportRepositoryImpl({
    required TripPrivacyExportService service,
    required TripPrivacyExportMapper mapper,
  })  : _service = service,
        _mapper = mapper;

  @override
  Future<AppResult<TripPrivacyExport>> fetchExport(int tripId) => appResultOf(
        () async => _mapper.mapExport(await _service.fetchExport(tripId)),
      );
}
