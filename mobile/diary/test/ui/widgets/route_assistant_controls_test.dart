import 'package:diary/features/route_assistant/domain/route_assistant_domain.dart';
import 'package:diary/network/service/route_assistant_service.dart';
import 'package:diary/network/service/route_classifier_service.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit.dart';
import 'package:diary/ui/widgets/route_assistant_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

class _FakeService implements RouteAssistantService {
  List<ll.LatLng> route = const [ll.LatLng(45.0, 9.0), ll.LatLng(45.5, 9.2)];
  RouteMode? lastMode;

  @override
  Future<List<GeocodingPlace>> searchPlaces(String query,
          {ll.LatLng? proximity}) async =>
      const [];

  @override
  Future<List<ll.LatLng>> fetchRoute({
    required ll.LatLng from,
    required ll.LatLng to,
    required RouteMode mode,
  }) async {
    lastMode = mode;
    return route;
  }
}

class _NoopClassifier implements RouteClassifierService {
  @override
  Future<RouteMode?> classify(List<List<double>> samples) async => null;
}

Future<RouteAssistantCubit> _activeCubit(_FakeService service) async {
  final cubit = RouteAssistantCubit(
    service,
    classifier: _NoopClassifier(),
    locationProvider: () async => const ll.LatLng(45.0, 9.0),
    sensorWindowProvider: () async => const [],
  );
  cubit.selectDestination(
    const GeocodingPlace(label: 'Duomo', location: ll.LatLng(45.46, 9.19)),
  );
  await cubit.confirmDestination();
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

void main() {
  testWidgets('non mostra nulla senza percorso attivo', (tester) async {
    final cubit = RouteAssistantCubit(
      _FakeService(),
      classifier: _NoopClassifier(),
      locationProvider: () async => const ll.LatLng(45.0, 9.0),
      sensorWindowProvider: () async => const [],
    );
    await _pump(tester, cubit);

    expect(find.byIcon(Icons.directions_bike), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('mostra i selettori con un percorso attivo', (tester) async {
    final cubit = await _activeCubit(_FakeService());
    await _pump(tester, cubit);

    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.bolt), findsOneWidget);
    expect(find.byIcon(Icons.directions_walk), findsOneWidget);
    expect(find.byIcon(Icons.directions_bike), findsOneWidget);
    expect(find.byIcon(Icons.directions_car), findsOneWidget);
  });

  testWidgets('tap su Auto cambia modalita e ricalcola', (tester) async {
    final service = _FakeService();
    final cubit = await _activeCubit(service);
    await _pump(tester, cubit);

    await tester.tap(find.byIcon(Icons.directions_car));
    await tester.pump();

    expect(cubit.state.mode, RouteMode.driving);
    expect(service.lastMode, RouteMode.driving);
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
  });

  testWidgets('Live abilitato con un viaggio in corso', (tester) async {
    final cubit = await _activeCubit(_FakeService());
    await _pump(tester, cubit, liveEnabled: true);

    expect(iconButton(tester, Icons.bolt).onPressed, isNotNull);
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
}
