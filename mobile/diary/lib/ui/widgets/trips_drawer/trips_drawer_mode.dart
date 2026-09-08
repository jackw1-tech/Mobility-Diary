import 'package:flutter/material.dart';

enum TripsDrawerMode { list, days, reloadable }

class TripsDrawerModeToggle extends StatelessWidget {
  final TripsDrawerMode value;
  final ValueChanged<TripsDrawerMode> onChanged;

  const TripsDrawerModeToggle({
    required this.value,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TripsDrawerMode>(
      segments: const [
        ButtonSegment(
          value: TripsDrawerMode.list,
          icon: Icon(Icons.format_list_bulleted),
        ),
        ButtonSegment(
          value: TripsDrawerMode.days,
          icon: Icon(Icons.calendar_month_outlined),
        ),
        ButtonSegment(
          value: TripsDrawerMode.reloadable,
          icon: Icon(Icons.replay_outlined),
        ),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (selected) => onChanged(selected.first),
    );
  }
}
