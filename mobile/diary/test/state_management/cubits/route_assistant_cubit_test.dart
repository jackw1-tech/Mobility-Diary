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
  Object? searchError;
  Object? routeError;
  RouteMode? lastMode;
  int routeCalls = 0;
  // Se valorizzato, fetchRoute attende questo completer (per testare le corse).
  Completer<List<ll.LatLng>>? routeGate;

  @override
  Future<List<GeocodingPlace>> searchPlaces(
    String query, {
    ll.LatLng? proximity,
  }) async {
    if (searchError != null) throw searchError!;
    return places;
  }

  @override
  Future<List<ll.LatLng>> fetchRoute({
    required ll.LatLng from,
    required ll.LatLng to,
    required RouteMode mode,
  }) async {
    routeCalls += 1;
    lastMode = mode;
    final gate = routeGate;
    if (gate != null) return gate.future;
    if (routeError != null) throw routeError!;
    return route;
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
  RouteClassifierService? classifier,
  List<List<double>> sensorWindow = const [],
  Duration tickInterval = const Duration(milliseconds: 20),
}) {
  return RouteAssistantCubit(
    service,
    classifier: classifier ?? FakeClassifierService(),
    locationProvider: () async => location,
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

  test('search vuota azzera i risultati senza chiamare il servizio', () async {
    final service = FakeRouteAssistantService()
      ..places = [_place('Duomo', 45.46, 9.19)];
    final cubit = _cubit(service);
    await cubit.search('duomo');

    await cubit.search('   ');

    expect(cubit.state.searchResults, isEmpty);
  });

  test('confirmDestination calcola il percorso e chiude la ricerca', () async {
    final service = FakeRouteAssistantService()
      ..route = [const ll.LatLng(45.0, 9.0), const ll.LatLng(45.5, 9.2)];
    final cubit = _cubit(service);
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));
    cubit.openSearch();

    await cubit.confirmDestination();

    expect(cubit.state.routePoints, hasLength(2));
    expect(cubit.state.isActive, isTrue);
    expect(cubit.state.isSearchOpen, isFalse);
    expect(service.lastMode, RouteMode.walking);
    cubit.dismiss();
  });

  test('setMode ricalcola il percorso col nuovo profilo', () async {
    final service = FakeRouteAssistantService()..route = [const ll.LatLng(1, 1)];
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
    final service = FakeRouteAssistantService()..route = [const ll.LatLng(1, 1)];
    final cubit = _cubit(service);
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));
    await cubit.confirmDestination();

    cubit.dismiss();

    expect(cubit.state.routePoints, isEmpty);
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
    final service = FakeRouteAssistantService()..route = [const ll.LatLng(1, 1)];
    final cubit = _cubit(service, location: null);
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));

    await cubit.confirmDestination();

    expect(cubit.state.routePoints, isEmpty);
    expect(cubit.state.errorMessage, contains('Posizione'));
    expect(service.routeCalls, 0);
  });

  test('dismiss durante un fetch in volo non riattiva l assistente', () async {
    final gate = Completer<List<ll.LatLng>>();
    final service = FakeRouteAssistantService()..routeGate = gate;
    final cubit = _cubit(service);
    cubit.selectDestination(_place('Duomo', 45.46, 9.19));
    final pending = cubit.confirmDestination(); // fetch resta in sospeso

    cubit.dismiss();
    gate.complete([const ll.LatLng(1, 1)]); // la risposta arriva dopo il dismiss
    await pending;

    expect(cubit.state.routePoints, isEmpty);
    expect(cubit.state.isActive, isFalse);
  });

  test('Live ricalcola il percorso a ogni tick (anche senza cambio modalita)',
      () async {
    final service = FakeRouteAssistantService()..route = [const ll.LatLng(1, 1)];
    final classifier = FakeClassifierService()..result = RouteMode.walking; // stessa del default
    final cubit = _cubit(service, classifier: classifier, sensorWindow: _oneWindow);
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
    final service = FakeRouteAssistantService()..route = [const ll.LatLng(1, 1)];
    final classifier = FakeClassifierService()..result = null;
    final cubit = _cubit(service, classifier: classifier, sensorWindow: _oneWindow);
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

  test('spegnere Live disabilita la classificazione (ricalcolo continua)', () async {
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
