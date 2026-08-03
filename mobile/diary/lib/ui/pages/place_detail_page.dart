import 'package:auto_route/auto_route.dart';
import 'package:diary/model/entities/places/place_review.dart';
import 'package:diary/repositories/places_repository.dart';
import 'package:diary/state_management/cubits/place_detail_cubit/place_detail_cubit.dart';
import 'package:diary/state_management/cubits/place_detail_cubit/place_detail_state.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/pages/place_presenter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Dettaglio di un Luogo Significativo: mappa con il centro del luogo e le
/// visite di supporto (evidenza), il contesto, e le azioni manuali di review.
@RoutePage()
class PlaceDetailPage extends StatelessWidget {
  final PlaceReview place;

  const PlaceDetailPage({required this.place, super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          PlaceDetailCubit(context.read<PlacesRepository>(), place)
            ..loadReviewStatus(),
      child: const _PlaceDetailView(),
    );
  }
}

class _PlaceDetailView extends StatelessWidget {
  const _PlaceDetailView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PlaceDetailCubit, PlaceDetailState>(
      listenWhen: (previous, current) =>
          current.error != null && current.error != previous.error,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.error!),
            backgroundColor: ColorPalette.error,
          ),
        );
      },
      builder: (context, state) {
        final place = state.place;
        return Scaffold(
          appBar: AppBar(centerTitle: true, title: Text(place.label)),
          body: Column(
            children: [
              Expanded(child: _PlaceMap(place: place)),
              _PlaceEvidencePanel(place: place),
              _PlaceActionBar(state: state),
            ],
          ),
        );
      },
    );
  }
}

class _PlaceMap extends StatefulWidget {
  final PlaceReview place;

  const _PlaceMap({required this.place});

  @override
  State<_PlaceMap> createState() => _PlaceMapState();
}

class _PlaceMapState extends State<_PlaceMap> {
  MapboxMap? _map;
  bool _styleReady = false;

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    await map.compass.updateSettings(CompassSettings(enabled: false));
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData _) async {
    _styleReady = true;
    await _drawPlace();
  }

  Future<void> _drawPlace() async {
    final map = _map;
    if (map == null || !_styleReady) return;
    final place = widget.place;

    final circleManager = await map.annotations.createCircleAnnotationManager();
    // Evidenza: ogni visita di supporto come punto neutro.
    for (final visit in place.visits) {
      await circleManager.create(
        CircleAnnotationOptions(
          geometry:
              Point(coordinates: Position(visit.longitude, visit.latitude)),
          circleColor: ColorPalette.textSecondary.toARGB32(),
          circleRadius: 6,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2,
        ),
      );
    }
    // Centro del luogo, colorato per stato.
    await circleManager.create(
      CircleAnnotationOptions(
        geometry: Point(coordinates: Position(place.longitude, place.latitude)),
        circleColor: placeStateColor(place).toARGB32(),
        circleRadius: 11,
        circleStrokeColor: Colors.white.toARGB32(),
        circleStrokeWidth: 3,
      ),
    );

    final coordinates = [
      Point(coordinates: Position(place.longitude, place.latitude)),
      for (final visit in place.visits)
        Point(coordinates: Position(visit.longitude, visit.latitude)),
    ];
    final camera = await map.cameraForCoordinatesPadding(
      coordinates,
      CameraOptions(zoom: 15),
      MbxEdgeInsets(top: 80, left: 60, bottom: 80, right: 60),
      null,
      null,
    );
    await map.flyTo(camera, MapAnimationOptions(duration: 500));
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    return MapWidget(
      key: const ValueKey('place-detail-map'),
      styleUri: MapboxStyles.MAPBOX_STREETS,
      // ignore: deprecated_member_use
      cameraOptions: CameraOptions(
        center: Point(coordinates: Position(place.longitude, place.latitude)),
        zoom: 15,
      ),
      onMapCreated: _onMapCreated,
      onStyleLoadedListener: _onStyleLoaded,
    );
  }
}

class _PlaceEvidencePanel extends StatelessWidget {
  final PlaceReview place;

  const _PlaceEvidencePanel({required this.place});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimensions.paddingLarge,
        Dimensions.paddingMedium,
        Dimensions.paddingLarge,
        0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(placeStateIcon(place), color: placeStateColor(place)),
              const SizedBox(width: Dimensions.paddingSmall),
              Text(
                placeStateLabel(place.state),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: Dimensions.paddingSmall),
          Text(
            placeWhyProposed(place),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: ColorPalette.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _PlaceActionBar extends StatelessWidget {
  final PlaceDetailState state;

  const _PlaceActionBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PlaceDetailCubit>();
    final place = state.place;
    if (state.busy) {
      return const SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.all(Dimensions.paddingMedium),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (!state.canReview) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(Dimensions.paddingMedium),
          child: Text(
            'Review temporaneamente bloccata: l’analisi dei luoghi non e\' ancora pronta.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: ColorPalette.textSecondary,
                ),
          ),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingMedium),
        child: Wrap(
          spacing: Dimensions.paddingSmall,
          runSpacing: Dimensions.paddingSmall,
          alignment: WrapAlignment.center,
          children: [
            if (!place.isConfirmed && !place.isRejected)
              FilledButton.icon(
                onPressed: cubit.confirm,
                icon: const Icon(Icons.check),
                label: const Text('Conferma'),
              ),
            if (place.isRejected)
              FilledButton.icon(
                onPressed: cubit.reactivate,
                icon: const Icon(Icons.undo),
                label: const Text('Riattiva'),
              ),
            if (!place.isRejected)
              OutlinedButton.icon(
                onPressed: cubit.reject,
                icon: const Icon(Icons.block),
                label: const Text('Rifiuta'),
              ),
            if (!place.isRejected)
              OutlinedButton.icon(
                onPressed: () => _openLabelDialog(context, cubit, place),
                icon: const Icon(Icons.label_outline),
                label: const Text('Etichetta'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLabelDialog(
    BuildContext context,
    PlaceDetailCubit cubit,
    PlaceReview place,
  ) async {
    final result = await showDialog<({String category, String customName})>(
      context: context,
      builder: (_) => _LabelDialog(place: place),
    );
    if (result != null) {
      await cubit.label(result.category, result.customName);
    }
  }
}

class _LabelDialog extends StatefulWidget {
  final PlaceReview place;

  const _LabelDialog({required this.place});

  @override
  State<_LabelDialog> createState() => _LabelDialogState();
}

class _LabelDialogState extends State<_LabelDialog> {
  late String _category = widget.place.category.isEmpty
      ? placeCategories.first
      : widget.place.category;
  late final TextEditingController _name =
      TextEditingController(text: widget.place.customName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Etichetta luogo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Categoria'),
            items: [
              for (final category in placeCategories)
                DropdownMenuItem(
                  value: category,
                  child: Text(placeCategoryLabel(category)),
                ),
            ],
            onChanged: (value) =>
                setState(() => _category = value ?? _category),
          ),
          const SizedBox(height: Dimensions.paddingSmall),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Nome (opzionale)',
              hintText: 'es. Bicocca',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            (category: _category, customName: _name.text.trim()),
          ),
          child: const Text('Salva'),
        ),
      ],
    );
  }
}
