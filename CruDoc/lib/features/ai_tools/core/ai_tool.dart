import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/misc.dart'
    show ProviderListenable, ProviderOrFamily;

import 'package:doctor_management_app/core/clinic/clinic_access.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';

/// How careful the executor must be before running a tool.
enum AiToolRisk {
  /// Look-up only. Runs at once.
  read,

  /// Changes data but returns an undo. Runs at once; the UI offers Undo.
  write,

  /// Money, outgoing messages, prescriptions, cancellations, anything that
  /// leaves the device. The user must approve a confirm card first.
  confirm,
}

/// Which screens a tool belongs to. The agent sends only the groups that fit
/// the current screen (plus [core]) so the model sees 15–25 tools, not 90.
enum AiToolGroup {
  core,
  patients,
  appointments,
  queue,
  dental,
  clinical,
  billing,
  inventory,
  tasks,
  files,
  messaging,
  team,
}

/// Reads a Riverpod provider. Fits `Ref.read`, `WidgetRef.read` and
/// `ProviderContainer.read`.
typedef AiRead = T Function<T>(ProviderListenable<T> provider);

/// One typed input. Turned into a firebase_ai [Schema] for the model and
/// used by the executor to check the model's arguments.
class AiParam {
  const AiParam._(
    this.type,
    this.description, {
    this.required = true,
    this.enumValues,
    this.items,
    this.properties,
    this.min,
    this.max,
  });

  const AiParam.string(String description, {bool required = true})
    : this._(AiParamType.string, description, required: required);

  /// `YYYY-MM-DD`.
  const AiParam.date(String description, {bool required = true})
    : this._(AiParamType.date, description, required: required);

  /// 24-hour `HH:MM`.
  const AiParam.time(String description, {bool required = true})
    : this._(AiParamType.time, description, required: required);

  const AiParam.integer(
    String description, {
    bool required = true,
    num? min,
    num? max,
  }) : this._(
         AiParamType.integer,
         description,
         required: required,
         min: min,
         max: max,
       );

  const AiParam.number(
    String description, {
    bool required = true,
    num? min,
    num? max,
  }) : this._(
         AiParamType.number,
         description,
         required: required,
         min: min,
         max: max,
       );

  const AiParam.boolean(String description, {bool required = true})
    : this._(AiParamType.boolean, description, required: required);

  const AiParam.enumOf(
    List<String> values,
    String description, {
    bool required = true,
  }) : this._(
         AiParamType.enumeration,
         description,
         required: required,
         enumValues: values,
       );

  const AiParam.list(AiParam items, String description, {bool required = true})
    : this._(AiParamType.list, description, required: required, items: items);

  const AiParam.object(
    Map<String, AiParam> properties,
    String description, {
    bool required = true,
  }) : this._(
         AiParamType.object,
         description,
         required: required,
         properties: properties,
       );

  final AiParamType type;
  final String description;
  final bool required;
  final List<String>? enumValues;
  final AiParam? items;
  final Map<String, AiParam>? properties;
  final num? min;
  final num? max;

  Schema toSchema() => switch (type) {
    AiParamType.string => Schema.string(description: description),
    AiParamType.date => Schema.string(
      description: '$description (YYYY-MM-DD)',
    ),
    AiParamType.time => Schema.string(
      description: '$description (24-hour HH:MM)',
    ),
    AiParamType.integer => Schema.integer(description: description),
    AiParamType.number => Schema.number(description: description),
    AiParamType.boolean => Schema.boolean(description: description),
    AiParamType.enumeration => Schema.enumString(
      enumValues: enumValues!,
      description: description,
    ),
    AiParamType.list => Schema.array(
      items: items!.toSchema(),
      description: description,
    ),
    AiParamType.object => Schema.object(
      properties: {
        for (final e in properties!.entries) e.key: e.value.toSchema(),
      },
      optionalProperties: [
        for (final e in properties!.entries)
          if (!e.value.required) e.key,
      ],
      description: description,
    ),
  };
}

enum AiParamType {
  string,
  date,
  time,
  integer,
  number,
  boolean,
  enumeration,
  list,
  object,
}

/// What a handler gets: provider access, who is asking, and UI hooks the
/// caller (agent screen, voice overlay) supplies.
class AiToolContext {
  const AiToolContext({
    required this.read,
    required this.access,
    this.invalidate,
    this.navigate,
    this.screen,
    this.openPatientId,
    this.selectedDate,
  });

  final AiRead read;

  /// Refreshes cached providers after a write so open screens show it.
  /// Pass `ref.invalidate`. Tools call `ctx.refresh(provider)`.
  final void Function(ProviderOrFamily provider)? invalidate;

  void refresh(ProviderOrFamily provider) => invalidate?.call(provider);

  /// Signed-in member's clinic access. Null only in single-doctor mode
  /// before the clinic session loads; then everything is allowed.
  final ClinicAccess? access;

  /// Moves the UI. `target` is a route path or a voice-navigation target id.
  final Future<void> Function(String target, {Map<String, Object?> args})?
  navigate;

  /// Screen the user is on (e.g. `patients`, `calendar`, `patient_details`).
  final String? screen;
  final String? openPatientId;
  final DateTime? selectedDate;

  bool can(ClinicPermission? p) =>
      p == null || access == null || access!.can(p);
}

/// What a handler returns. [data] goes back to the model, so keep it small:
/// IDs, names, dates, counts.
class AiToolResult {
  const AiToolResult._({
    required this.ok,
    required this.data,
    this.summary,
    this.undo,
    this.error,
  });

  factory AiToolResult.ok(
    Map<String, Object?> data, {
    String? summary,
    Future<void> Function()? undo,
  }) => AiToolResult._(ok: true, data: data, summary: summary, undo: undo);

  /// A failure the model should read and recover from (not found, two
  /// matches, missing field...).
  factory AiToolResult.error(String message, {Map<String, Object?>? data}) =>
      AiToolResult._(ok: false, data: data ?? const {}, error: message);

  final bool ok;
  final Map<String, Object?> data;

  /// One plain line for the UI ("Booked Rahul for 3 pm tomorrow").
  final String? summary;

  /// Present for [AiToolRisk.write] tools. Reverses the change.
  final Future<void> Function()? undo;
  final String? error;

  Map<String, Object?> toModelJson() => {
    'ok': ok,
    if (error != null) 'error': error,
    ...data,
  };
}

typedef AiToolHandler =
    Future<AiToolResult> Function(AiToolContext ctx, Map<String, Object?> args);

/// One tool the LLM can call.
class AiTool {
  const AiTool({
    required this.name,
    required this.description,
    required this.group,
    required this.risk,
    required this.run,
    this.permission,
    this.params = const {},
    this.phoneSafe = false,
    this.confirmText,
  });

  /// snake_case, unique.
  final String name;

  /// What it does and when to use it, written for the model.
  final String description;
  final AiToolGroup group;
  final AiToolRisk risk;
  final ClinicPermission? permission;
  final Map<String, AiParam> params;
  final AiToolHandler run;

  /// Allowed for the phone receptionist.
  final bool phoneSafe;

  /// Builds the confirm-card line from the arguments, for [AiToolRisk.confirm]
  /// tools. Falls back to the tool name and arguments.
  final String Function(Map<String, Object?> args)? confirmText;

  FunctionDeclaration toDeclaration() => FunctionDeclaration(
    name,
    description,
    parameters: {for (final e in params.entries) e.key: e.value.toSchema()},
    optionalParameters: [
      for (final e in params.entries)
        if (!e.value.required) e.key,
    ],
  );
}
