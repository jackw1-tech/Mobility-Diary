import 'package:diary/features/common/domain/app_result.dart';
import 'package:diary/features/route_assistant/domain/route_assistant_domain.dart';
import 'package:diary/repositories/route_assistant_repository.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit.dart';
import 'package:diary/ui/widgets/route_assistant_search_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

class _FakeService implements RouteAssistantRepository {
  Object? routeError;

  @override
  Future<AppResult<List<GeocodingPlace>>> searchPlaces(
    String query, {
    ll.LatLng? proximity,
  }) async =>
      const AppResult.success([]);

  @override
  Future<AppResult<RouteAssistantRoute>> fetchRoute({
    required ll.LatLng from,
    required ll.LatLng to,
    required RouteMode mode,
  }) async {
    if (routeError != null) return AppResult.failure(toAppFailure(routeError!));
    return const AppResult.success(
      RouteAssistantRoute(
        points: [ll.LatLng(45.0, 9.0), ll.LatLng(45.5, 9.2)],
        distanceMeters: 1200,
        durationSeconds: 600,
      ),
    );
  }

  @override
  Future<AppResult<RouteMode?>> classify(List<List<double>> samples) async =>
      const AppResult.success(null);
}

Future<void> _pump(WidgetTester tester, RouteAssistantCubit cubit) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider.value(
          value: cubit,
          child: const RouteAssistantSearchSheet(),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('mostra errore di routing senza chiudere il sheet',
      (tester) async {
    final service = _FakeService()
      ..routeError = const RouteAssistantException('boom');
    final cubit = RouteAssistantCubit(
      service,
      locationProvider: () async => const ll.LatLng(45.0, 9.0),
      sensorWindowProvider: () async => const [],
    )..selectDestination(
        const GeocodingPlace(label: 'Duomo', location: ll.LatLng(45.46, 9.19)),
      );

    await _pump(tester, cubit);
    await tester.tap(find.text('Vai'));
    await tester.pump();

    expect(find.text('boom'), findsOneWidget);
    expect(find.byType(RouteAssistantSearchSheet), findsOneWidget);
  });
}
