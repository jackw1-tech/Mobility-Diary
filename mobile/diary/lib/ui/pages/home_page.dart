import 'package:auto_route/auto_route.dart';
import 'package:diary/repositories/privacy_settings_repository.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';
import 'package:diary/state_management/cubits/auth_cubit/auth_cubit.dart';
import 'package:diary/state_management/cubits/auth_cubit/auth_cubit_state.dart';
import 'package:diary/state_management/cubits/privacy_settings_cubit/privacy_settings_cubit.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit_state.dart';
import 'package:diary/routers/app_router.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/ui/pages/auth_page.dart';
import 'package:diary/ui/pages/home_sync_presenter.dart';
import 'package:diary/ui/widgets/home/core_metrics.dart';
import 'package:diary/ui/widgets/home/home_map_overlays.dart';
import 'package:diary/ui/widgets/home/sheet_handle.dart';
import 'package:diary/ui/widgets/home/tracking_header.dart';
import 'package:diary/ui/widgets/live_map.dart';
import 'package:diary/ui/widgets/privacy_onboarding_dialog.dart';
import 'package:diary/ui/widgets/route_assistant_search_sheet.dart';
import 'package:diary/ui/widgets/trips_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

@RoutePage()
class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthCubitState>(
      builder: (context, authState) {
        if (authState.status == AuthStatus.initial ||
            authState.status == AuthStatus.loading) {
          return const _AuthLoadingPage();
        }

        if (!authState.isAuthenticated) {
          return const AuthPage();
        }

        return BlocProvider<PrivacySettingsCubit>(
          create: (context) => PrivacySettingsCubit(
            context.read<PrivacySettingsRepository>(),
          )..load(),
          child: _AuthenticatedHomePage(userLabel: authState.user?.displayName),
        );
      },
    );
  }
}

class _AuthenticatedHomePage extends StatefulWidget {
  final String? userLabel;

  const _AuthenticatedHomePage({required this.userLabel});

  @override
  State<_AuthenticatedHomePage> createState() => _AuthenticatedHomePageState();
}

class _AuthenticatedHomePageState extends State<_AuthenticatedHomePage> {
  static const double _initialSheetExtent = 0.30;
  static const double _minSheetExtent = 0.05;
  static const double _maxSheetExtent = 0.38;

  double _sheetExtent = _initialSheetExtent;

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<PrivacySettingsCubit, PrivacySettingsState>(
          listenWhen: (previous, current) => current.needsPrivacyOnboarding,
          listener: (context, state) => showPrivacyOnboardingDialog(context),
        ),
        BlocListener<AcquisitionCubit, AcquisitionCubitState>(
          listenWhen: (previous, current) =>
              !previous.syncSnapshot.canOpenCoreDetail &&
              current.syncSnapshot.canOpenCoreDetail,
          listener: (context, state) {
            final tripId = state.syncSnapshot.remoteTripId;
            if (tripId != null) {
              context.router.push(TripDetailRoute(tripId: tripId));
            }
          },
        ),
        BlocListener<AcquisitionCubit, AcquisitionCubitState>(
          listenWhen: (previous, current) => shouldShowSyncDebugSnack(
            previous.syncSnapshot,
            current.syncSnapshot,
          ),
          listener: (context, state) {
            final snack = syncDebugSnackBar(state.syncSnapshot);
            if (snack != null) {
              ScaffoldMessenger.of(context).showSnackBar(snack);
            }
          },
        ),
        BlocListener<AcquisitionCubit, AcquisitionCubitState>(
          listenWhen: (previous, current) =>
              previous.completedReplayTripId != current.completedReplayTripId &&
              current.completedReplayTripId != null,
          listener: (context, state) {
            final tripId = state.completedReplayTripId;
            if (tripId != null) {
              context.router.push(TripDetailRoute(tripId: tripId));
            }
          },
        ),
      ],
      child: BlocBuilder<AcquisitionCubit, AcquisitionCubitState>(
        buildWhen: (previous, current) =>
            previous.snapshot.replaySecondsRemaining !=
            current.snapshot.replaySecondsRemaining,
        builder: (context, state) {
          return Scaffold(
            drawer: const TripsDrawer(),
            appBar: AppBar(
              centerTitle: true,
              title: Text(
                widget.userLabel == null ? 'Mobile Edge' : widget.userLabel!,
              ),
              actions: [
                IconButton(
                  tooltip: 'Assistente percorso',
                  icon: const Icon(Icons.alt_route),
                  onPressed: () => showRouteAssistantSearch(context),
                ),
                IconButton(
                  tooltip: 'Statistiche',
                  icon: const Icon(Icons.bar_chart_outlined),
                  onPressed: () => context.router.push(const AnalyticsRoute()),
                ),
                IconButton(
                  tooltip: 'I miei luoghi',
                  icon: const Icon(Icons.place_outlined),
                  onPressed: () => context.router.push(const PlacesRoute()),
                ),
              ],
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                final replaySecondsRemaining =
                    state.snapshot.replaySecondsRemaining;
                return Stack(
                  children: [
                    const Positioned.fill(child: LiveMap()),
                    BlocBuilder<RouteAssistantCubit, RouteAssistantState>(
                      buildWhen: (previous, current) =>
                          previous.route != current.route ||
                          previous.routeUpdatedAt != current.routeUpdatedAt,
                      builder: (context, assistantState) {
                        if (assistantState.route == null &&
                            replaySecondsRemaining == null) {
                          return const SizedBox.shrink();
                        }
                        return Positioned(
                          left: Dimensions.paddingMedium,
                          right: Dimensions.paddingMedium,
                          bottom: constraints.maxHeight * _sheetExtent +
                              Dimensions.paddingSmall,
                          child: HomeMapOverlays(
                            route: assistantState.route,
                            routeUpdatedAt: assistantState.routeUpdatedAt,
                            replaySecondsRemaining: replaySecondsRemaining,
                          ),
                        );
                      },
                    ),
                    NotificationListener<DraggableScrollableNotification>(
                      onNotification: (notification) {
                        if ((notification.extent - _sheetExtent).abs() >
                            0.001) {
                          setState(() => _sheetExtent = notification.extent);
                        }
                        return false;
                      },
                      child: DraggableScrollableSheet(
                        initialChildSize: _initialSheetExtent,
                        minChildSize: _minSheetExtent,
                        maxChildSize: _maxSheetExtent,
                        builder: (context, scrollController) {
                          return DecoratedBox(
                            decoration: const BoxDecoration(
                              color: ColorPalette.background,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(
                                  Dimensions.borderRadiusLarge,
                                ),
                              ),
                              border: Border(
                                top: BorderSide(color: ColorPalette.hairline),
                              ),
                            ),
                            child: ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.all(
                                Dimensions.paddingMedium,
                              ),
                              children: [
                                const SheetHandle(),
                                const SizedBox(
                                  height: Dimensions.paddingSmall,
                                ),
                                TrackingHeader(state: state),
                                const SizedBox(
                                  height: Dimensions.paddingMedium,
                                ),
                                CoreMetrics(state: state),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _AuthLoadingPage extends StatelessWidget {
  const _AuthLoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: ColorPalette.background,
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
