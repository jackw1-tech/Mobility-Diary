import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:diary/model/entities/places/place_review.dart';
import 'package:diary/routers/auth_guard.dart';
import 'package:diary/ui/pages/analytics_page.dart';
import 'package:diary/ui/pages/home_page.dart';
import 'package:diary/ui/pages/place_detail_page.dart';
import 'package:diary/ui/pages/places_page.dart';
import 'package:diary/ui/pages/profile_page.dart';
import 'package:diary/ui/pages/trip_detail_page.dart';

part 'app_router.gr.dart';

@AutoRouterConfig()
class AppRouter extends RootStackRouter {
  final AuthGuard authGuard;

  AppRouter({
    required this.authGuard,
    super.navigatorKey,
  });

  @override
  List<AutoRoute> get routes => [
        AutoRoute(path: '/', page: HomeRoute.page, initial: true),
        AutoRoute(
          path: '/trips/:id',
          page: TripDetailRoute.page,
          guards: [authGuard],
        ),
        AutoRoute(
          path: '/places',
          page: PlacesRoute.page,
          guards: [authGuard],
        ),
        AutoRoute(
          path: '/analytics',
          page: AnalyticsRoute.page,
          guards: [authGuard],
        ),
        AutoRoute(
          path: '/places/detail',
          page: PlaceDetailRoute.page,
          guards: [authGuard],
        ),
        AutoRoute(
          path: '/profile',
          page: ProfileRoute.page,
          guards: [authGuard],
        ),
      ];
}
