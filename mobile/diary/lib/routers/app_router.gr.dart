// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

part of 'app_router.dart';

/// generated route for
/// [AnalyticsPage]
class AnalyticsRoute extends PageRouteInfo<void> {
  const AnalyticsRoute({List<PageRouteInfo>? children})
    : super(AnalyticsRoute.name, initialChildren: children);

  static const String name = 'AnalyticsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const AnalyticsPage();
    },
  );
}

/// generated route for
/// [HomePage]
class HomeRoute extends PageRouteInfo<void> {
  const HomeRoute({List<PageRouteInfo>? children})
    : super(HomeRoute.name, initialChildren: children);

  static const String name = 'HomeRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const HomePage();
    },
  );
}

/// generated route for
/// [PlaceDetailPage]
class PlaceDetailRoute extends PageRouteInfo<PlaceDetailRouteArgs> {
  PlaceDetailRoute({
    required PlaceReview place,
    Key? key,
    List<PageRouteInfo>? children,
  }) : super(
         PlaceDetailRoute.name,
         args: PlaceDetailRouteArgs(place: place, key: key),
         initialChildren: children,
       );

  static const String name = 'PlaceDetailRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<PlaceDetailRouteArgs>();
      return PlaceDetailPage(place: args.place, key: args.key);
    },
  );
}

class PlaceDetailRouteArgs {
  const PlaceDetailRouteArgs({required this.place, this.key});

  final PlaceReview place;

  final Key? key;

  @override
  String toString() {
    return 'PlaceDetailRouteArgs{place: $place, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PlaceDetailRouteArgs) return false;
    return place == other.place && key == other.key;
  }

  @override
  int get hashCode => place.hashCode ^ key.hashCode;
}

/// generated route for
/// [PlacesPage]
class PlacesRoute extends PageRouteInfo<void> {
  const PlacesRoute({List<PageRouteInfo>? children})
    : super(PlacesRoute.name, initialChildren: children);

  static const String name = 'PlacesRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const PlacesPage();
    },
  );
}

/// generated route for
/// [ProfilePage]
class ProfileRoute extends PageRouteInfo<void> {
  const ProfileRoute({List<PageRouteInfo>? children})
    : super(ProfileRoute.name, initialChildren: children);

  static const String name = 'ProfileRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const ProfilePage();
    },
  );
}

/// generated route for
/// [TripDetailPage]
class TripDetailRoute extends PageRouteInfo<TripDetailRouteArgs> {
  TripDetailRoute({
    required int tripId,
    Key? key,
    List<PageRouteInfo>? children,
  }) : super(
         TripDetailRoute.name,
         args: TripDetailRouteArgs(tripId: tripId, key: key),
         rawPathParams: {'id': tripId},
         initialChildren: children,
       );

  static const String name = 'TripDetailRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<TripDetailRouteArgs>(
        orElse: () => TripDetailRouteArgs(tripId: pathParams.getInt('id')),
      );
      return TripDetailPage(tripId: args.tripId, key: args.key);
    },
  );
}

class TripDetailRouteArgs {
  const TripDetailRouteArgs({required this.tripId, this.key});

  final int tripId;

  final Key? key;

  @override
  String toString() {
    return 'TripDetailRouteArgs{tripId: $tripId, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TripDetailRouteArgs) return false;
    return tripId == other.tripId && key == other.key;
  }

  @override
  int get hashCode => tripId.hashCode ^ key.hashCode;
}
