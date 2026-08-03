import 'package:auto_route/auto_route.dart';
import 'package:diary/model/entities/trips/trip_list_item.dart';
import 'package:diary/repositories/trip_track_repository.dart';
import 'package:diary/repositories/trips_repository.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/pages/trip_diary_tabs.dart';
import 'package:diary/ui/pages/trip_map_page.dart';
import 'package:diary/ui/widgets/trip_privacy_export_sheet.dart';
import 'package:diary/ui/widgets/trips_drawer_presenter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

@RoutePage()
class TripDetailPage extends StatefulWidget {
  final int tripId;

  const TripDetailPage({
    @PathParam('id') required this.tripId,
    Key? key,
  }) : super(key: key);

  @override
  State<TripDetailPage> createState() => _TripDetailPageState();
}

class _TripDetailPageState extends State<TripDetailPage> {
  late int _currentTripId;
  List<TripListItem> _trips = const [];
  bool _didLoadTrips = false;

  @override
  void initState() {
    super.initState();
    _currentTripId = widget.tripId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadTrips) return;
    _didLoadTrips = true;
    _loadTrips();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TripTrackCubit(context.read<TripTrackRepository>())
        ..load(widget.tripId),
      child: Builder(
        builder: (context) {
          final sameDayTrips = sameLocalDayTrackTrips(_trips, _currentTripId);
          final selector = sameDayTrips.length > 1
              ? _SameDayTripSelector(
                  trips: sameDayTrips,
                  selectedTripId: _currentTripId,
                  onSelectTrip: (trip) => _selectTrip(context, trip),
                )
              : null;

          return DefaultTabController(
            length: 3,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Dettaglio viaggio'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.ios_share),
                    tooltip: 'Export diario',
                    onPressed: () =>
                        showTripPrivacyExportSheet(context, _currentTripId),
                  ),
                ],
                bottom: const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.map), text: 'Mappa'),
                    Tab(icon: Icon(Icons.timeline), text: 'Diario'),
                    Tab(icon: Icon(Icons.bar_chart), text: 'Statistiche'),
                  ],
                ),
              ),
              body: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  TripMapPage(topLeftOverlay: selector),
                  const TripDiaryTab(),
                  const TripStatsTab(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadTrips() async {
    final result = await context.read<TripsRepository>().fetchTrips();
    if (!mounted || result.isFailure) return;
    setState(() => _trips = result.requireValue);
  }

  void _selectTrip(BuildContext context, TripListItem trip) {
    if (trip.id == _currentTripId) return;
    setState(() => _currentTripId = trip.id);
    context.read<TripTrackCubit>().load(trip.id);
  }
}

class _SameDayTripSelector extends StatefulWidget {
  final List<TripListItem> trips;
  final int selectedTripId;
  final ValueChanged<TripListItem> onSelectTrip;

  const _SameDayTripSelector({
    required this.trips,
    required this.selectedTripId,
    required this.onSelectTrip,
  });

  @override
  State<_SameDayTripSelector> createState() => _SameDayTripSelectorState();
}

class _SameDayTripSelectorState extends State<_SameDayTripSelector> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = widget.trips.indexWhere(
      (trip) => trip.id == widget.selectedTripId,
    );
    final safeIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final selectedTrip = widget.trips[safeIndex];

    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkResponse(
            onTap: () => setState(() => _open = !_open),
            radius: 24,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: ColorPalette.primary,
                borderRadius:
                    BorderRadius.circular(Dimensions.borderRadiusPill),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Center(
                child: Icon(Icons.more_vert, color: Colors.white, size: 20),
              ),
            ),
          ),
          if (_open) ...[
            const SizedBox(height: Dimensions.paddingSmall),
            DecoratedBox(
              decoration: BoxDecoration(
                color: ColorPalette.surface.withValues(alpha: 0.96),
                borderRadius:
                    BorderRadius.circular(Dimensions.borderRadiusMedium),
                border: Border.all(color: ColorPalette.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.all(Dimensions.paddingSmall),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(selectedTrip.startedAt.toLocal()),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    SizedBox(
                      width: 48,
                      height: 160,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Slider(
                          value: safeIndex.toDouble(),
                          min: 0,
                          max: (widget.trips.length - 1).toDouble(),
                          divisions: widget.trips.length - 1,
                          label: _formatTime(selectedTrip.startedAt.toLocal()),
                          onChanged: (value) {
                            final index = value.round();
                            widget.onSelectTrip(widget.trips[index]);
                          },
                        ),
                      ),
                    ),
                    Text(
                      '${safeIndex + 1}/${widget.trips.length}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ColorPalette.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.hour)}:${two(dt.minute)}';
}
