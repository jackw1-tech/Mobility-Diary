import 'package:diary/features/common/domain/app_result.dart';
import 'package:diary/features/route_assistant/domain/route_assistant_domain.dart';
import 'package:diary/repositories/route_assistant_repository.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit.dart';
import 'package:diary/ui/widgets/route_assistant_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

class _FakeService implements RouteAssistantRepository {
  List<ll.LatLng> route = const [ll.LatLng(45.0, 9.0), ll.LatLng(45.5, 9.2)];
  RouteMode? lastMode;

  @override
  Future<AppResult<List<GeocodingPlace>>> searchPlaces(String query,
          {ll.LatLng? proximity}) async =>
      const AppResult.success([]);

  @override
  Future<AppResult<RouteAssistantRoute>> fetchRoute({
    required ll.LatLng from,
    required ll.LatLng to,
    required RouteMode mode,
  }) async {
    lastMode = mode;
    return AppResult.success(
      RouteAssistantRoute(
        points: route,
        distanceMeters: 1200,
        durationSeconds: 600,
      ),
    );
  }

  @override
  Future<AppResult<RouteMode?>> classify(List<List<double>> samples) async =>
      const AppResult.success(null);
}

Future<RouteAssistantCubit> _activeCubit(_FakeService service) async {
  final cubit = RouteAssistantCubit(
    service,
    locationProvider: () async => const ll.LatLng(45.0, 9.0),
    sensorWindowProvider: () async => const [],
  );
  cubit.selectDestination(
    const GeocodingPlace(label: 'Duomo', location: ll.LatLng(45.46, 9.19)),
  );
  await cubit.confirmDestination();
  addTearDown(cubit.dismiss);
  return cubit;
}

Future<void> _pump(
  WidgetTester tester,
  RouteAssistantCubit cubit, {
  bool liveEnabled = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider.value(
          value: cubit,
          child: Stack(
            children: [RouteAssistantControls(liveEnabled: liveEnabled)],
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpIndicator(
  WidgetTester tester, {
  required RouteMode? mode,
  required bool hasResult,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            RouteDetectedModeIndicator(
              mode: mode,
              hasResult: hasResult,
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('non mostra nulla senza percorso attivo', (tester) async {
    final cubit = RouteAssistantCubit(
      _FakeService(),
      locationProvider: () async => const ll.LatLng(45.0, 9.0),
      sensorWindowProvider: () async => const [],
    );
    await _pump(tester, cubit);

    expect(find.byIcon(Icons.directions_bike), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('pallino rilevamento mostra stato in attesa', (tester) async {
    await _pumpIndicator(tester, mode: null, hasResult: false);

    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsNothing);
  });

  testWidgets('pallino rilevamento mostra fermo', (tester) async {
    await _pumpIndicator(tester, mode: null, hasResult: true);

    expect(find.byIcon(Icons.pause), findsOneWidget);
  });

  testWidgets('pallino rilevamento mostra icona della modalita',
      (tester) async {
    await _pumpIndicator(tester, mode: RouteMode.cycling, hasResult: true);

    expect(find.byIcon(Icons.directions_bike), findsOneWidget);
    final material = tester
        .widgetList<Material>(
          find.descendant(
            of: find.byType(RouteDetectedModeIndicator),
            matching: find.byType(Material),
          ),
        )
        .singleWhere((material) => material.shape is CircleBorder);
    expect(material.color, Colors.white);
  });

  testWidgets('mostra i selettori con un percorso attivo', (tester) async {
    final cubit = await _activeCubit(_FakeService());
    await _pump(tester, cubit);

    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.bolt), findsOneWidget);
    expect(find.byIcon(Icons.directions_walk), findsOneWidget);
    expect(find.byIcon(Icons.directions_bike), findsOneWidget);
    expect(find.byIcon(Icons.directions_car), findsOneWidget);
    cubit.dismiss();
  });

  testWidgets('tap su Auto cambia modalita e ricalcola', (tester) async {
    final service = _FakeService();
    final cubit = await _activeCubit(service);
    await _pump(tester, cubit);

    await tester.tap(find.byIcon(Icons.directions_car));
    await tester.pump();

    expect(cubit.state.mode, RouteMode.driving);
    expect(service.lastMode, RouteMode.driving);
    cubit.dismiss();
  });

  testWidgets('tap su X chiude e rimuove i selettori', (tester) async {
    final cubit = await _activeCubit(_FakeService());
    await _pump(tester, cubit);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(cubit.state.isActive, isFalse);
    expect(find.byIcon(Icons.directions_bike), findsNothing);
  });

  IconButton iconButton(WidgetTester tester, IconData icon) {
    return tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(icon),
        matching: find.byType(IconButton),
      ),
    );
  }

  testWidgets('Live disabilitato senza viaggio in corso', (tester) async {
    final cubit = await _activeCubit(_FakeService());
    await _pump(tester, cubit, liveEnabled: false);

    expect(iconButton(tester, Icons.bolt).onPressed, isNull);
    cubit.dismiss();
  });

  testWidgets('Live abilitato con un viaggio in corso', (tester) async {
    final cubit = await _activeCubit(_FakeService());
    await _pump(tester, cubit, liveEnabled: true);

    expect(iconButton(tester, Icons.bolt).onPressed, isNotNull);
    cubit.dismiss();
  });

  testWidgets('con Live attivo i chip manuali sono disabilitati',
      (tester) async {
    final cubit = await _activeCubit(_FakeService());
    await _pump(tester, cubit, liveEnabled: true);

    await tester.tap(find.byIcon(Icons.bolt));
    await tester.pump();

    expect(cubit.state.isLive, isTrue);
    expect(iconButton(tester, Icons.directions_car).onPressed, isNull);
    cubit.dismiss();
  });

  testWidgets('Live attivo resta spegnibile quando il viaggio si ferma',
      (tester) async {
    final cubit = await _activeCubit(_FakeService());
    await _pump(tester, cubit, liveEnabled: true);
    await tester.tap(find.byIcon(Icons.bolt));
    await tester.pump();

    await _pump(tester, cubit, liveEnabled: false);

    expect(cubit.state.isLive, isTrue);
    expect(iconButton(tester, Icons.bolt).onPressed, isNotNull);

    await tester.tap(find.byIcon(Icons.bolt));
    await tester.pump();

    expect(cubit.state.isLive, isFalse);
    expect(iconButton(tester, Icons.directions_car).onPressed, isNotNull);
    cubit.dismiss();
  });
}
