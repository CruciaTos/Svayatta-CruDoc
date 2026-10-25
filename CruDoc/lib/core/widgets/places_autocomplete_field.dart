import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/google_places_service.dart';
import 'package:doctor_management_app/core/theme/cru_theme.dart';
import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';

/// Result returned by [PlacesAutocompleteField] when the user selects a
/// place from the suggestions, containing both the address text and the
/// resolved lat/lng so the caller never needs a separate geocoding step.
class PlaceSelection {
  final String address;
  final double latitude;
  final double longitude;

  const PlaceSelection({
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}

/// A text field with Google Places Autocomplete suggestions.
///
/// Drop-in replacement for a plain `TextField`: the caller supplies a
/// [controller] and an [onPlaceSelected] callback that fires when the
/// user taps a suggestion. If the user types a free-text address
/// without selecting a suggestion, the controller's text is still
/// available — matching the existing "optional address" behaviour the
/// app already has.
///
/// Works on all platforms (Android, iOS, Windows, Web) because it uses
/// the Places API REST endpoint via [GooglePlacesService], not a
/// platform-specific SDK.
class PlacesAutocompleteField extends ConsumerStatefulWidget {
  /// Controller whose text is kept in sync with the selected/typed
  /// address. Must be disposed by the caller.
  final TextEditingController controller;

  /// Fires when the user taps a suggestion and coordinates are resolved.
  final ValueChanged<PlaceSelection>? onPlaceSelected;

  /// Hint text shown when the field is empty.
  final String? hint;

  /// Whether the field is enabled. Disabled during save operations.
  final bool enabled;

  const PlacesAutocompleteField({
    super.key,
    required this.controller,
    this.onPlaceSelected,
    this.hint,
    this.enabled = true,
  });

  @override
  ConsumerState<PlacesAutocompleteField> createState() =>
      _PlacesAutocompleteFieldState();
}

class _PlacesAutocompleteFieldState
    extends ConsumerState<PlacesAutocompleteField> {
  final _places = GooglePlacesService.instance;
  final _focusNode = FocusNode();

  List<PlacePrediction> _predictions = [];
  bool _loading = false;
  bool _suppressSuggestions = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && mounted) {
      // Clear suggestions when the field loses focus (with a small
      // delay so onTap on a suggestion can fire first).
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_focusNode.hasFocus) {
          setState(() => _predictions = []);
        }
      });
    }
  }

  void _onChanged(String value) {
    _suppressSuggestions = false;
    _debounce?.cancel();

    final trimmed = value.trim();
    if (trimmed.length < 3) {
      setState(() {
        _predictions = [];
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);

    // Debounce 350 ms so we don't hit the API on every keystroke.
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      // Nearest to the doctor (or else the clinic) first.
      final near = await searchOriginNow(ref);
      final results = await _places.autocomplete(trimmed, near: near);
      if (!mounted || widget.controller.text.trim() != trimmed) return;
      setState(() {
        _predictions = results;
        _loading = false;
      });
    });
  }

  Future<void> _onPredictionTap(PlacePrediction prediction) async {
    // Fill the field immediately with the description.
    widget.controller.text = prediction.description;
    setState(() {
      _predictions = [];
      _suppressSuggestions = true;
      _loading = true;
    });

    // Resolve lat/lng from the Place ID.
    final details = await _places.getPlaceDetails(prediction.placeId);
    if (!mounted) return;

    setState(() => _loading = false);

    if (details != null) {
      // Use the formatted address from the API if available.
      if (details.formattedAddress.isNotEmpty) {
        widget.controller.text = details.formattedAddress;
      }
      widget.onPlaceSelected?.call(
        PlaceSelection(
          address: widget.controller.text,
          latitude: details.latitude,
          longitude: details.longitude,
        ),
      );
    }
  }

  /// The Calm Clinical field (the caller shows the label above it). Dense
  /// with a control-sized icon box, so 44 px like the other Cru fields.
  InputDecoration get _decoration {
    final c = context.cru;
    return InputDecoration(
      hintText: widget.hint,
      isDense: true,
      suffixIconConstraints: const BoxConstraints(
        minWidth: CruSize.control,
        minHeight: CruSize.control,
      ),
      suffixIcon: _loading
          ? Padding(
              padding: const EdgeInsets.all(CruSpace.s12),
              child: SizedBox.square(
                dimension: CruSpace.s16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.accent,
                ),
              ),
            )
          : Icon(Icons.place_outlined, size: CruSpace.s20, color: c.label3),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Start finding where the doctor is while they type.
    ref.watch(addressSearchOriginProvider);
    final showSuggestions = _predictions.isNotEmpty && !_suppressSuggestions;

    final c = context.cru;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          style: CruType.input.tint(c.label),
          onChanged: _onChanged,
          decoration: _decoration,
        ),
        if (showSuggestions)
          Container(
            margin: const EdgeInsets.only(top: CruSpace.s4),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(CruRadius.control),
              border: Border.all(color: c.cardBorder),
            ),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _predictions.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: c.separator),
              itemBuilder: (context, index) {
                final p = _predictions[index];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.place_outlined,
                    size: CruSpace.s18,
                    color: c.label3,
                  ),
                  title: Text(
                    p.mainText,
                    style: CruType.callout.tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    p.secondaryText,
                    style: CruType.caption.tint(c.label2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _onPredictionTap(p),
                );
              },
            ),
          ),
      ],
    );
  }
}
