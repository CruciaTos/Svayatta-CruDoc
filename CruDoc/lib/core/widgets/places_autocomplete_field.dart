import 'dart:async';
import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/services/google_places_service.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';

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
class PlacesAutocompleteField extends StatefulWidget {
  /// Controller whose text is kept in sync with the selected/typed
  /// address. Must be disposed by the caller.
  final TextEditingController controller;

  /// Fires when the user taps a suggestion and coordinates are resolved.
  final ValueChanged<PlaceSelection>? onPlaceSelected;

  /// Label shown above / inside the field.
  final String label;

  /// Hint text shown when the field is empty.
  final String? hint;

  /// Whether the field is enabled. Disabled during save operations.
  final bool enabled;

  /// Decoration style variant — `'sheet'` uses the bottom-sheet white
  /// style with rounded corners, `'dialog'` uses the dialog-style with
  /// cardSurface fill. Defaults to `'sheet'`.
  final String style;

  const PlacesAutocompleteField({
    super.key,
    required this.controller,
    this.onPlaceSelected,
    this.label = 'Address',
    this.hint,
    this.enabled = true,
    this.style = 'sheet',
  });

  @override
  State<PlacesAutocompleteField> createState() =>
      _PlacesAutocompleteFieldState();
}

class _PlacesAutocompleteFieldState extends State<PlacesAutocompleteField> {
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
      final results = await _places.autocomplete(trimmed);
      if (!mounted) return;
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
      widget.onPlaceSelected?.call(PlaceSelection(
        address: widget.controller.text,
        latitude: details.latitude,
        longitude: details.longitude,
      ));
    }
  }

  InputDecoration get _decoration {
    if (widget.style == 'dialog') {
      return InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        labelStyle: AppColors.bodyMedium,
        hintStyle: AppColors.bodySmall.copyWith(color: Colors.grey.shade600),
        filled: true,
        fillColor: AppColors.cardSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        suffixIcon: _loading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : const Icon(Icons.location_on_outlined,
                size: 20, color: AppColors.silver),
      );
    }

    // Default 'sheet' style — matches the existing bottom-sheet fields.
    return InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      labelStyle: AppColors.bodyMedium.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: AppColors.bodyMedium.copyWith(color: AppColors.textSecondary),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: AppColors.chartBarLight,
          width: 1.5,
        ),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      suffixIcon: _loading
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : const Icon(Icons.location_on_outlined,
              size: 20, color: AppColors.chartBarLight),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showSuggestions =
        _predictions.isNotEmpty && !_suppressSuggestions;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          style: widget.style == 'dialog'
              ? AppColors.bodyLarge
              : AppColors.bodyMedium,
          onChanged: _onChanged,
          decoration: _decoration,
        ),
        if (showSuggestions)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.chartBarLight.withValues(alpha: 0.25),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _predictions.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: AppColors.textSecondary.withValues(alpha: 0.10),
              ),
              itemBuilder: (context, index) {
                final p = _predictions[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.place_outlined,
                    size: 18,
                    color: AppColors.chartBarLight,
                  ),
                  title: Text(
                    p.mainText,
                    style: AppColors.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    p.secondaryText,
                    style: AppColors.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
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
