import 'package:diary/model/entities/trips/trip_list_item.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/widgets/trips_drawer/drawer_message.dart';
import 'package:diary/ui/widgets/trips_drawer/trip_tile.dart';
import 'package:diary/ui/widgets/trips_drawer_presenter.dart';
import 'package:diary/utils/date_time_utils.dart';
import 'package:flutter/material.dart';

/// Elenco piatto dei viaggi, usato sia in modalita' lista sia in modalita'
/// "solo ricaricabili".
class TripsListView extends StatelessWidget {
  final List<TripListItem> trips;
  final bool reloadable;

  const TripsListView({
    required this.trips,
    this.reloadable = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: trips.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => TripTile(
        trip: trips[index],
        reloadable: reloadable,
      ),
    );
  }
}

/// Vista a due livelli: prima i giorni, poi i viaggi del giorno scelto.
class TripsByDayView extends StatelessWidget {
  final List<TripDayGroup> groups;
  final TripDayGroup? selectedDay;
  final ValueChanged<TripDayGroup> onSelectDay;
  final VoidCallback onBackToDays;

  const TripsByDayView({
    required this.groups,
    required this.selectedDay,
    required this.onSelectDay,
    required this.onBackToDays,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final day = selectedDay;
    if (day != null) {
      return _DayTripsView(
        group: day,
        onBack: onBackToDays,
      );
    }

    if (groups.isEmpty) {
      return const DrawerMessage(
        icon: Icons.calendar_month_outlined,
        text: 'Nessun giorno con percorsi disponibili',
      );
    }

    return ListView.separated(
      itemCount: groups.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _DayGroupTile(
        group: groups[index],
        onTap: () => onSelectDay(groups[index]),
      ),
    );
  }
}

class _DayGroupTile extends StatelessWidget {
  final TripDayGroup group;
  final VoidCallback onTap;

  const _DayGroupTile({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = group.trips.length;
    return ListTile(
      leading: const Icon(Icons.calendar_today_outlined),
      title: Text(DateTimeUtils.formatDate(group.day)),
      subtitle: Text(count == 1 ? '1 percorso' : '$count percorsi'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _DayTripsView extends StatelessWidget {
  final TripDayGroup group;
  final VoidCallback onBack;

  const _DayTripsView({
    required this.group,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: Dimensions.paddingMedium),
      children: [
        ListTile(
          leading: IconButton(
            tooltip: 'Torna ai giorni',
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
          ),
          title: Text(DateTimeUtils.formatDate(group.day)),
          subtitle: Text('${group.trips.length} percorsi nella giornata'),
        ),
        const Divider(height: 1),
        for (final trip in group.trips) TripTile(trip: trip),
      ],
    );
  }
}
