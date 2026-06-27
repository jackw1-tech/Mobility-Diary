import 'package:auto_route/auto_route.dart';
import 'package:diary/network/service/trip_track_service.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit.dart';
import 'package:diary/ui/pages/trip_diary_tabs.dart';
import 'package:diary/ui/pages/trip_map_page.dart';
import 'package:diary/ui/widgets/trip_privacy_export_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

@RoutePage()
class TripDetailPage extends StatelessWidget {
  final int tripId;

  const TripDetailPage({
    @PathParam('id') required this.tripId,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          TripTrackCubit(context.read<TripTrackService>())..load(tripId),
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Dettaglio viaggio'),
            actions: [
              Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.ios_share),
                  tooltip: 'Export diario',
                  onPressed: () => showTripPrivacyExportSheet(context, tripId),
                ),
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
          body: const TabBarView(
            physics: NeverScrollableScrollPhysics(),
            children: [
              TripMapPage(),
              TripDiaryTab(),
              TripStatsTab(),
            ],
          ),
        ),
      ),
    );
  }
}
