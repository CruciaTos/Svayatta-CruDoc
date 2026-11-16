import 'ai_tool.dart';

/// Every tool the in-app AI can call. Tool group files add themselves in
/// [AiToolRegistry.all] (see `tools/all_tools.dart`).
class AiToolRegistry {
  AiToolRegistry(List<AiTool> tools) : _byName = {for (final t in tools) t.name: t} {
    assert(_byName.length == tools.length, 'Duplicate AI tool names');
  }

  final Map<String, AiTool> _byName;

  Iterable<AiTool> get tools => _byName.values;

  AiTool? operator [](String name) => _byName[name];

  /// Tools this user may call, limited to [groups] (core is always in).
  /// Pass `groups: null` for every group.
  List<AiTool> forRequest(
    AiToolContext ctx, {
    Set<AiToolGroup>? groups,
    bool phoneOnly = false,
  }) {
    return [
      for (final t in _byName.values)
        if (ctx.can(t.permission) &&
            (groups == null ||
                t.group == AiToolGroup.core ||
                groups.contains(t.group)) &&
            (!phoneOnly || t.phoneSafe))
          t,
    ];
  }

  /// Which groups fit a screen. Unknown screens get the front-desk set.
  static Set<AiToolGroup> groupsForScreen(String? screen) => switch (screen) {
    'patient_details' || 'patient' => {
      AiToolGroup.patients,
      AiToolGroup.appointments,
      AiToolGroup.clinical,
      AiToolGroup.dental,
      AiToolGroup.billing,
      AiToolGroup.files,
    },
    'charting' || 'dental' || 'perio' => {
      AiToolGroup.patients,
      AiToolGroup.dental,
      AiToolGroup.clinical,
    },
    'calendar' || 'appointments' || 'queue' || 'dashboard' => {
      AiToolGroup.patients,
      AiToolGroup.appointments,
      AiToolGroup.queue,
      AiToolGroup.messaging,
    },
    'revenue' || 'billing' => {
      AiToolGroup.patients,
      AiToolGroup.billing,
    },
    'inventory' => {AiToolGroup.inventory},
    'files' || 'radiology' => {AiToolGroup.patients, AiToolGroup.files},
    'campaigns' || 'messaging' => {
      AiToolGroup.patients,
      AiToolGroup.messaging,
    },
    'team' || 'settings' => {AiToolGroup.team},
    'tasks' || 'todos' => {AiToolGroup.tasks, AiToolGroup.patients},
    _ => {
      AiToolGroup.patients,
      AiToolGroup.appointments,
      AiToolGroup.queue,
      AiToolGroup.tasks,
    },
  };
}
