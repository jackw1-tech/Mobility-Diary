import 'package:diary/features/privacy/domain/privacy_level.dart';
import 'package:diary/network/dto/trip_privacy_export_dto.dart';
import 'package:diary/network/service/trip_privacy_export_service.dart';
import 'package:diary/state_management/cubits/trip_privacy_export_cubit/trip_privacy_export_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTripPrivacyExportService implements TripPrivacyExportService {
  TripPrivacyExportDto response;
  Object? error;
  int fetchCalls = 0;
  int? requestedTripId;

  FakeTripPrivacyExportService(this.response);

  @override
  Future<TripPrivacyExportDto> fetchExport(int tripId) async {
    fetchCalls += 1;
    requestedTripId = tripId;
    final failure = error;
    if (failure != null) throw failure;
    return response;
  }
}

TripPrivacyExportDto approximateExport() {
  return TripPrivacyExportDto.fromJson(const {
    'trip_id': 7,
    'level': 'approximate',
    'protected': true,
    'approximated_coordinates': true,
    'cell_size_meters': 150,
    'text': 'Diario viaggio #7\n'
        'Privacy level: approximate\n'
        'Cell size: 150 m\n'
        'Coordinate approssimate: non sono letture GPS originali.\n\n'
        '08:15-08:35 walking\n'
        '  Privacy-aware path: 2 approximated points\n'
        '    [9.1008, 45.4601] [9.2009, 45.4702]\n'
        '08:35-08:55 Sosta significativa in area approssimata',
    'segments': [
      {
        'kind': 'MOVE',
        'start_label': '08:15',
        'end_label': '08:35',
        'activity_label': 'WALKING',
        'title': 'walking',
        'point_count': 2,
        'coordinates': [
          [9.1008, 45.4601],
          [9.2009, 45.4702],
        ],
      },
      {
        'kind': 'STOP',
        'start_label': '08:35',
        'end_label': '08:55',
        'activity_label': 'IDLE',
        'title': 'Sosta significativa in area approssimata',
        'point_count': 0,
        'coordinates': <List<double>>[],
      },
    ],
  });
}

Future<void> flushCubitStream() => Future<void>.delayed(Duration.zero);

void main() {
  group('TripPrivacyExportCubit', () {
    test('loads the export and exposes the preview text', () async {
      final service = FakeTripPrivacyExportService(approximateExport());
      final cubit = TripPrivacyExportCubit(service);
      final states = <TripPrivacyExportState>[];
      final subscription = cubit.stream.listen(states.add);
      addTearDown(subscription.cancel);
      addTearDown(cubit.close);

      await cubit.load(7);
      await flushCubitStream();

      expect(service.fetchCalls, 1);
      expect(service.requestedTripId, 7);
      expect(states.map((state) => state.status), [
        TripPrivacyExportStatus.loading,
        TripPrivacyExportStatus.ready,
      ]);
      expect(cubit.state.export!.level, PrivacyLevel.approximate);
      expect(cubit.state.export!.text, contains('Privacy level: approximate'));
    });

    test('non-precise preview never leaks precise geometry or labels', () async {
      final service = FakeTripPrivacyExportService(approximateExport());
      final cubit = TripPrivacyExportCubit(service);
      addTearDown(cubit.close);

      await cubit.load(7);

      final export = cubit.state.export!;
      // The fixture mirrors the backend contract: cloaked coordinates, generic
      // stop wording, and no original GPS reading in the text.
      expect(export.approximatedCoordinates, isTrue);
      expect(export.text, isNot(contains('universita')));
      expect(export.text, isNot(contains('[9.1, 45.46]')));
      final stop =
          export.segments.firstWhere((segment) => segment.kind == 'STOP');
      expect(stop.title, 'Sosta significativa in area approssimata');
      expect(stop.coordinates, isEmpty);
    });

    test('emits an error when the export request fails', () async {
      final service = FakeTripPrivacyExportService(approximateExport())
        ..error = Exception('offline');
      final cubit = TripPrivacyExportCubit(service);
      addTearDown(cubit.close);

      await cubit.load(7);

      expect(cubit.state.status, TripPrivacyExportStatus.error);
      expect(cubit.state.error, contains('offline'));
    });
  });
}
