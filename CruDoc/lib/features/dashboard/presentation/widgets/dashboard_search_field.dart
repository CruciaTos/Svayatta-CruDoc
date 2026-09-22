import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/utils/search_normalisation.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

sealed class _Option {
  const _Option();
}

class _PatientOption extends _Option {
  const _PatientOption(this.patient);
  final Patient patient;
}

class _AskOption extends _Option {
  const _AskOption(this.query);
  final String query;
}

/// "Search patients or ask CruDoc". Matching patients open their record;
/// anything else (or Enter on an empty field) opens the assistant, which
/// replaces the old floating chat button.
class DashboardSearchField extends ConsumerStatefulWidget {
  const DashboardSearchField({super.key, this.focusNode, this.width});

  final FocusNode? focusNode;

  /// Null to fill the available width.
  final double? width;

  @override
  ConsumerState<DashboardSearchField> createState() =>
      _DashboardSearchFieldState();
}

class _DashboardSearchFieldState extends ConsumerState<DashboardSearchField> {
  final _controller = TextEditingController();
  FocusNode? _ownFocus;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void dispose() {
    _controller.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  Iterable<_Option> _options(TextEditingValue value) {
    final q = normalizeForSearch(value.text);
    if (q.isEmpty) return const [];
    final digits = normalizePhoneDigits(q);
    final patients = ref.read(patientsStreamProvider).value ?? const [];
    final matches = patients
        .where((p) => !p.isArchived)
        .where((p) =>
            normalizeForSearch(p.fullName).contains(q) ||
            (digits.length >= 3 &&
                normalizePhoneDigits(p.phone).contains(digits)))
        .take(5)
        .map<_Option>(_PatientOption.new);
    return [...matches, _AskOption(value.text.trim())];
  }

  void _select(_Option option) {
    _controller.clear();
    _focus.unfocus();
    switch (option) {
      case _PatientOption(:final patient):
        DashboardActions.openPatient(context, patient);
      case _AskOption(:final query):
        DashboardActions.openAssistant(context, query);
    }
  }

  String get _shortcut =>
      defaultTargetPlatform == TargetPlatform.macOS ? '⌘K' : 'Ctrl K';

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return SizedBox(
      width: widget.width,
      height: CruSize.control,
      child: RawAutocomplete<_Option>(
        textEditingController: _controller,
        focusNode: _focus,
        optionsBuilder: _options,
        displayStringForOption: (_) => '',
        onSelected: _select,
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
          return DecoratedBox(
            decoration: ShapeDecoration(
              color: c.surface,
              shape: cruShape(
                CruRadius.control,
                side: BorderSide(color: c.hairline),
              ),
              shadows: c.cardShadow,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
              child: Row(
                children: [
                  CruIcon(CruIcons.search, size: 16, strokeWidth: 2,
                      color: c.label3),
                  const SizedBox(width: CruSpace.s8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      style: CruType.text.tint(c.label),
                      cursorColor: c.accent,
                      cursorHeight: 18,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Search patients or ask CruDoc',
                        hintStyle: CruType.text.tint(c.label3),
                      ),
                      onSubmitted: (v) {
                        if (v.trim().isEmpty) {
                          focusNode.unfocus();
                          DashboardActions.openAssistant(context);
                        } else {
                          onSubmitted();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: CruSpace.s8),
                  CruKeycap(_shortcut),
                ],
              ),
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) =>
            _OptionsView(options: options.toList(), onSelected: onSelected),
      ),
    );
  }
}

class _OptionsView extends StatelessWidget {
  const _OptionsView({required this.options, required this.onSelected});

  final List<_Option> options;
  final AutocompleteOnSelected<_Option> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final highlighted = AutocompleteHighlightedOption.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: CruSpace.s6),
        child: Material(
          color: c.surface,
          elevation: c.isEvening ? 0 : 8,
          shadowColor: c.label.withValues(alpha: 0.2),
          shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360, maxHeight: 320),
            child: ListView(
              padding: const EdgeInsets.all(CruSpace.s6),
              shrinkWrap: true,
              children: [
                for (var i = 0; i < options.length; i++)
                  _OptionRow(
                    option: options[i],
                    highlighted: i == highlighted,
                    onTap: () => onSelected(options[i]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.highlighted,
    required this.onTap,
  });

  final _Option option;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      builder: (context, hovered) => Container(
        height: CruSize.control,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
        decoration: ShapeDecoration(
          color: highlighted || hovered ? c.inset : c.surface,
          shape: cruShape(CruRadius.control - 6),
        ),
        child: Row(
          children: switch (option) {
            _PatientOption(:final patient) => [
                CruMonogram(name: patient.fullName, size: 26),
                const SizedBox(width: CruSpace.s10),
                Expanded(
                  child: Text(
                    patient.fullName,
                    style: CruType.callout.tint(c.label),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(patient.phone, style: CruType.caption.tabular.tint(c.label3)),
              ],
            _AskOption(:final query) => [
                SizedBox(
                  width: 26,
                  child: CruIcon(CruIcons.sparkle, size: 18, color: c.ai),
                ),
                const SizedBox(width: CruSpace.s10),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: 'Ask CruDoc  ',
                        style: CruType.callout.tint(c.ai),
                      ),
                      TextSpan(
                        text: query,
                        style: CruType.text.tint(c.label2),
                      ),
                    ]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
          },
        ),
      ),
    );
  }
}
