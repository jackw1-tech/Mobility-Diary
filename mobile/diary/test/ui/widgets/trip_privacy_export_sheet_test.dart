import 'package:diary/network/dto/trip_privacy_export_dto.dart';
import 'package:diary/network/service/trip_privacy_export_service.dart';
import 'package:diary/state_management/cubits/trip_privacy_export_cubit/trip_privacy_export_cubit.dart';
import 'package:diary/ui/widgets/trip_privacy_export_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTripPrivacyExportService implements TripPrivacyExportService {
  @override
  Future<TripPrivacyExportDto> fetchExport(int tripId) async {
    return TripPrivacyExportDto.fromJson({
      'trip_id': tripId,
      'level': 'approximate',
      'protected': true,
      'approximated_coordinates': true,
      'cell_size_meters': 150,
      'text': '08:15-08:35 spostamento a piedi',
      'segments': const <Map<String, Object?>>[],
    });
  }
}

void main() {
  testWidgets('shows a native share action for ready exports', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => TripPrivacyExportCubit(
              _FakeTripPrivacyExportService(),
            )..load(7),
            child: const TripPrivacyExportView(tripId: 7),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Export diario'), findsOneWidget);
    expect(find.text('Copia'), findsOneWidget);
    expect(find.text('Condividi'), findsOneWidget);
  });
}
