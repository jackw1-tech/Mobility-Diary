import 'dart:async';

import 'package:diary/features/route_assistant/domain/route_assistant_domain.dart';
import 'package:diary/network/service/route_assistant_service.dart';
import 'package:diary/network/service/route_classifier_service.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

class FakeClassifierService implements RouteClassifierService {
  RouteMode? result;
  Object? error;
  int calls = 0;

  @override
  Future<RouteMode?> classify(List<List<double>> samples) async {
    calls += 1;
    if (error != null) throw error!;
    return result;
  }
}

class FakeRouteAssistantService implements RouteAssistantService {
  List<GeocodingPlace> places = const [];
  List<ll.LatLng> route = const [];
  double distanceMeters = 1200;
  double durationSeconds = 600;
  Object? searchError;
  Object? routeError;
  RouteMode? lastMode;
  ll.LatLng? lastSearchProximity;
  ll.LatLng? lastRouteFrom;
  int routeCalls = 0;
  Completer<List<GeocodingPlace>>? searchGate;
  // Se valorizzato, fetchRoute attende questo completer (per testare le corse).
  Completer<RouteAssistantRoute>? routeGate;

  @override
  Future<List<GeocodingPlace>> searchPlaces(
    String query, {
    ll.LatLng? proximity,
  }) async {
    lastSearchProximity = proximity;
    final gate = searchGate;
    if (gate != null) return gate.future;
    if (searchError != null) throw searchError!;
    return places;
  }

  @override
  Future<RouteAssistantRoute> fetchRoute({
    required ll.LatLng from,
    required ll.LatLng to,
    required RouteMode mode,
  }) async {
    routeCalls += 1;
    lastMode = mode;
    lastRouteFrom = from;
    final gate = routeGate;
    if (gate != null) return gate.future;
    if (routeError != null) throw routeError!;
    return RouteAssistantRoute(
      points: route,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
    );
  }
}

GeocodingPlace _place(String label, double lat, double lon) =>
    GeocodingPlace(label: label, location: ll.LatLng(lat, lon));

final _oneWindow = [
  [for (var i = 0; i < 6; i++) i.toDouble()],
];

RouteAssistantCubit _cubit(
  FakeRouteAssistantService service, {
  ll.LatLng? location = const ll.LatLng(45.0, 9.0),
  ll.LatLng? activeLocation,
  RouteClassifierService? classifier,
  List<List<double>> sensorWindow = const [],
  Duration tickInterval = const Duration(milliseconds: 20),
}) {
  return RouteAssistantCubit(
    service,
    classifier: classifier ?? FakeClassifierService(),
    locationProvider: () async => location,
    activeLocationProvider:
        activeLocation == null ? null : () => activeLocation,
    sensorWindowProvider: () async => sensorWindow,
    tickInterval: tickInterval,
  );
}

void main() {
  test('parte in modalita walking senza percorso', () {
    final cubit = _cubit(FakeRouteAssistantService());
    expect(cubit.state.mode, RouteMode.walking);
    expect(cubit.state.routePoints, isEmpty);
    expect(cubit.state.isActive, isFalse);
  });

  test('search popola i risultati geocoding', () async {
    final service = FakeRouteAssistantService()
      ..places = [_place('Duomo', 45.46, 9.19)];
    final cubit = _cubit(service);

    await cubit.search('duomo');

    expect(cubit.state.searchResults, hasLength(1));
    expect(cubit.state.searchResults.first.label, 'Duomo');
    expect(cubit.state.isSearching, isFalse);
  });

  test('search usa la posizione della sessione attiva come proximity',
      () async {
    final service = FakeRouteAssistantService()
      ..places = [_place('Duomo', 45.46, 9.19)];
    final cubit = _cubit(
      service,
      location: const ll.LatLng(10, 10),
      activeLocation: const ll.LatLng(45.47, 9.20),
    );

    await cubit.search('duomo');

    expect(service.lastSearchProximity, const ll.LatLng(45.47, 9.20));
  });

  test('search vuota azzera i risultati senza chiamare il servizio', () async {
    final service = FakeRouteAssistantService()
      ..places = [_place('Duomo', 45.46, 9.19)];
    final cubit = _cubit(service);
    await cubit.search('duomo');

    await cubit.search('   ');

    expect(cubit.state.searchResults, isEmpty);
  });

  test('search vuota invalida una ricerca precedente in volo', () async {
    final gate = Completer<List<GeocodingPlace>>();
    final service = FakeRouteAssistantService()..searchGate = gate;
    final cubit = _cubit(service);
    final pending = cubit.search('duomo');
    await Future<void>.delayed(Duration.zero);

    await cubit.search('   ');
    gate.complete([_place('Duomo', 45.46, 9.19)]);
    await pending;

    expect(cubit.state.searchResults, isEmpty);
    expect(cubit.state.isSearching, isFalse);
  });

  test('confirmDestination calcola il percorso e chiude la ricerca', () async {
    final service = FakeRouteAssistantService()
      ..route = [const ll.LatLng(45.0, 9.0), const ll.LatLng(45.5, 9.2)]
      ..distanceMeters = 3200
      ..durationSeconds = 780;
    final cubit = _cubit(service);
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));
    cubit.openSearch();

    await cubit.confirmDestination();

    expect(cubit.state.routePoints, hasLength(2));
    expect(cubit.state.isActive, isTrue);
    expect(cubit.state.isSearchOpen, isFalse);
    expect(service.lastMode, RouteMode.walking);
    expect(cubit.state.route?.distanceMeters, 3200);
    expect(cubit.state.route?.durationSeconds, 780);
    expect(cubit.state.routeUpdatedAt, isNotNull);
    cubit.dismiss();
  });

  test('confirmDestination parte dalla posizione della sessione attiva',
      () async {
    final service = FakeRouteAssistantService()
      ..route = [const ll.LatLng(45.47, 9.20), const ll.LatLng(45.5, 9.2)];
    final cubit = _cubit(
      service,
      location: const ll.LatLng(10, 10),
      activeLocation: const ll.LatLng(45.47, 9.20),
    );
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));

    await cubit.confirmDestination();

    expect(service.lastRouteFrom, const ll.LatLng(45.47, 9.20));
    cubit.dismiss();
  });

  test('setMode ricalcola il percorso col nuovo profilo', () async {
    final service = FakeRouteAssistantService()
      ..route = [const ll.LatLng(1, 1)];
    final cubit = _cubit(service);
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));
    await cubit.confirmDestination();

    await cubit.setMode(RouteMode.driving);

    expect(service.lastMode, RouteMode.driving);
    expect(service.routeCalls, 2);
    cubit.dismiss();
  });

  test('setMode senza destinazione non calcola percorsi', () async {
    final service = FakeRouteAssistantService();
    final cubit = _cubit(service);

    await cubit.setMode(RouteMode.walking);

    expect(cubit.state.mode, RouteMode.walking);
    expect(service.routeCalls, 0);
  });

  test('dismiss azzera percorso e destinazione', () async {
    final service = FakeRouteAssistantService()
      ..route = [const ll.LatLng(1, 1)];
    final cubit = _cubit(service);
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));
    await cubit.confirmDestination();

    cubit.dismiss();

    expect(cubit.state.routePoints, isEmpty);
    expect(cubit.state.routeUpdatedAt, isNull);
    expect(cubit.state.destination, isNull);
    expect(cubit.state.mode, RouteMode.walking);
  });

  test('errore di routing viene esposto in errorMessage', () async {
    final service = FakeRouteAssistantService()
      ..routeError = const RouteAssistantException('boom');
    final cubit = _cubit(service);
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));

    await cubit.confirmDestination();

    expect(cubit.state.routePoints, isEmpty);
    expect(cubit.state.errorMessage, 'boom');
  });

  test('posizione mancante blocca il calcolo con errore', () async {
    final service = FakeRouteAssistantService()
      ..route = [const ll.LatLng(1, 1)];
    final cubit = _cubit(service, location: null);
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));

    await cubit.confirmDestination();

    expect(cubit.state.routePoints, isEmpty);
    expect(cubit.state.errorMessage, contains('Posizione'));
    expect(service.routeCalls, 0);
  });

  test('dismiss durante un fetch in volo non riattiva l assistente', () async {
    final gate = Completer<RouteAssistantRoute>();
    final service = FakeRouteAssistantService()..routeGate = gate;
    final cubit = _cubit(service);
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));
    final pending = cubit.confirmDestination(); // fetch resta in sospeso

    cubit.dismiss();
    gate.complete(
      const RouteAssistantRoute(
        points: [ll.LatLng(1, 1)],
        distanceMeters: 100,
        durationSeconds: 60,
      ),
    ); // la risposta arriva dopo il dismiss
    await pending;

    expect(cubit.state.routePoints, isEmpty);
    expect(cubit.state.isActive, isFalse);
  });

  test('Live ricalcola il percorso a ogni tick (anche senza cambio modalita)',
      () async {
    final service = FakeRouteAssistantService()
      ..route = [const ll.LatLng(1, 1)];
    final classifier = FakeClassifierService()
      ..result = RouteMode.walking; // stessa del default
    final cubit =
        _cubit(service, classifier: classifier, sensorWindow: _oneWindow);
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));
    await cubit.confirmDestination();
    final routeCallsBefore = service.routeCalls;

    cubit.toggleLive();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(cubit.state.isLive, isTrue);
    expect(cubit.state.mode, RouteMode.walking);
    expect(cubit.state.detectedMode, RouteMode.walking);
    expect(service.routeCalls, greaterThan(routeCallsBefore));
    cubit.dismiss();
  });

  test('Live con IDLE (null) mantiene profilo ed evidenziazione', () async {
    final service = FakeRouteAssistantService()
      ..route = [const ll.LatLng(1, 1)];
    final classifier = FakeClassifierService()..result = null;
    final cubit =
        _cubit(service, classifier: classifier, sensorWindow: _oneWindow);
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));
    await cubit.confirmDestination();

    cubit.toggleLive();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(cubit.state.mode, RouteMode.walking);
    expect(cubit.state.detectedMode, isNull);
    cubit.dismiss();
  });

  test('Live senza finestra sensori non classifica', () async {
    final classifier = FakeClassifierService()..result = RouteMode.walking;
    final cubit = _cubit(
      FakeRouteAssistantService(),
      classifier: classifier,
      sensorWindow: const [],
    );
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));

    cubit.toggleLive();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(classifier.calls, 0);
    cubit.dismiss();
  });

  test('rilevamento passivo classifica senza percorso attivo', () async {
    final service = FakeRouteAssistantService()
      ..route = [const ll.LatLng(1, 1)];
    final classifier = FakeClassifierService()..result = RouteMode.cycling;
    final cubit = _cubit(
      service,
      classifier: classifier,
      sensorWindow: _oneWindow,
    );

    cubit.setPassiveModeDetectionEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(classifier.calls, 1);
    expect(cubit.state.detectedMode, RouteMode.cycling);
    expect(cubit.state.hasDetectedModeResult, isTrue);
    expect(cubit.state.mode, RouteMode.walking);
    expect(service.routeCalls, 0);
    cubit.dismiss();
  });

  test('confirmDestination usa la previsione passiva come modalita iniziale',
      () async {
    final service = FakeRouteAssistantService()
      ..route = [const ll.LatLng(1, 1)];
    final classifier = FakeClassifierService()..result = RouteMode.cycling;
    final cubit = _cubit(
      service,
      classifier: classifier,
      sensorWindow: _oneWindow,
    );
    cubit.setPassiveModeDetectionEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));

    await cubit.confirmDestination();

    expect(cubit.state.mode, RouteMode.cycling);
    expect(service.lastMode, RouteMode.cycling);
    cubit.dismiss();
  });

  test('rilevamento passivo riparte dall ultima previsione Live', () async {
    final service = FakeRouteAssistantService()
      ..route = [const ll.LatLng(1, 1)];
    final classifier = FakeClassifierService()..result = RouteMode.driving;
    final cubit = _cubit(
      service,
      classifier: classifier,
      sensorWindow: _oneWindow,
    );
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));
    await cubit.confirmDestination();
    cubit.toggleLive();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    cubit.dismiss();
    cubit.setPassiveModeDetectionEnabled(true);

    expect(cubit.state.detectedMode, RouteMode.driving);
    expect(cubit.state.hasDetectedModeResult, isTrue);
    cubit.dismiss();
  });

  test('rilevamento passivo mostra idle quando il classificatore torna null',
      () async {
    final classifier = FakeClassifierService()..result = null;
    final cubit = _cubit(
      FakeRouteAssistantService(),
      classifier: classifier,
      sensorWindow: _oneWindow,
    );

    cubit.setPassiveModeDetectionEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(cubit.state.detectedMode, isNull);
    expect(cubit.state.hasDetectedModeResult, isTrue);
    cubit.dismiss();
  });

  test('confirmDestination ignora la previsione passiva ferma', () async {
    final service = FakeRouteAssistantService()
      ..route = [const ll.LatLng(1, 1)];
    final classifier = FakeClassifierService()..result = null;
    final cubit = _cubit(
      service,
      classifier: classifier,
      sensorWindow: _oneWindow,
    );
    cubit.setPassiveModeDetectionEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));

    await cubit.confirmDestination();

    expect(cubit.state.mode, RouteMode.walking);
    expect(service.lastMode, RouteMode.walking);
    cubit.dismiss();
  });

  test('spegnere il rilevamento passivo svuota la previsione', () async {
    final classifier = FakeClassifierService()..result = RouteMode.driving;
    final cubit = _cubit(
      FakeRouteAssistantService(),
      classifier: classifier,
      sensorWindow: _oneWindow,
    );
    cubit.setPassiveModeDetectionEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    cubit.setPassiveModeDetectionEnabled(false);

    expect(cubit.state.detectedMode, isNull);
    expect(cubit.state.hasDetectedModeResult, isFalse);
    cubit.dismiss();
  });

  test('fine viaggio svuota la previsione salvata', () async {
    final classifier = FakeClassifierService()..result = RouteMode.driving;
    final cubit = _cubit(
      FakeRouteAssistantService(),
      classifier: classifier,
      sensorWindow: _oneWindow,
    );
    cubit.setPassiveModeDetectionEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    cubit.clearDetectedModePrediction();

    expect(cubit.state.detectedMode, isNull);
    expect(cubit.state.hasDetectedModeResult, isFalse);
    cubit.dismiss();
  });

  test('spegnere Live disabilita la classificazione (ricalcolo continua)',
      () async {
    final classifier = FakeClassifierService()..result = RouteMode.driving;
    final cubit = _cubit(
      FakeRouteAssistantService()..route = [const ll.LatLng(1, 1)],
      classifier: classifier,
      sensorWindow: _oneWindow,
    );
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));
    await cubit.confirmDestination();
    cubit.toggleLive();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    cubit.toggleLive();

    expect(cubit.state.isLive, isFalse);
    expect(cubit.state.detectedMode, isNull);
    final callsAfterStop = classifier.calls;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    // Live OFF: il classificatore non viene piu' chiamato
    expect(classifier.calls, callsAfterStop);
    cubit.dismiss();
  });
}
