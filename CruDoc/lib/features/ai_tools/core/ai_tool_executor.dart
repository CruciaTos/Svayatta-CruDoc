import 'package:flutter/foundation.dart';

import 'ai_tool.dart';
import 'ai_tool_registry.dart';

/// Asks the user to approve a [AiToolRisk.confirm] call. Returns true to run.
typedef AiConfirm = Future<bool> Function(AiTool tool, String text);

/// One executed (or refused) call, for the audit trail.
class AiToolLogEntry {
  AiToolLogEntry({
    required this.tool,
    required this.args,
    required this.ok,
    required this.uid,
    this.error,
  }) : at = DateTime.now();

  final String tool;
  final Map<String, Object?> args;
  final bool ok;
  final String? uid;
  final String? error;
  final DateTime at;
}

/// Where audit entries go. In memory for now; a Firestore sink
/// (`ai_tool_logs`) needs a rules change first.
class AiToolAudit {
  AiToolAudit._();
  static final instance = AiToolAudit._();

  static const _max = 500;
  final List<AiToolLogEntry> _entries = [];

  List<AiToolLogEntry> get entries => List.unmodifiable(_entries);

  void add(AiToolLogEntry e) {
    _entries.add(e);
    if (_entries.length > _max) _entries.removeAt(0);
    debugPrint('[AiTool] ${e.tool} ok=${e.ok}${e.error == null ? '' : ' ${e.error}'}');
  }
}

/// Runs one model function call safely: known tool, permission, argument
/// check, confirm for risky tools, audit. Never throws; failures come back
/// as [AiToolResult.error] so the model can recover.
class AiToolExecutor {
  AiToolExecutor(this.registry, {this.confirm, AiToolAudit? audit})
    : audit = audit ?? AiToolAudit.instance;

  final AiToolRegistry registry;
  final AiConfirm? confirm;
  final AiToolAudit audit;

  Future<AiToolResult> execute(
    AiToolContext ctx,
    String name,
    Map<String, Object?> rawArgs,
  ) async {
    final tool = registry[name];
    if (tool == null) {
      return _log(ctx, name, rawArgs, AiToolResult.error('Unknown tool $name'));
    }
    if (!ctx.can(tool.permission)) {
      return _log(
        ctx,
        name,
        rawArgs,
        AiToolResult.error('This user is not allowed to do that'),
      );
    }

    final checked = validateArgs(tool.params, rawArgs);
    if (checked.error != null) {
      return _log(ctx, name, rawArgs, AiToolResult.error(checked.error!));
    }
    final args = checked.args;

    if (tool.risk == AiToolRisk.confirm) {
      final text = tool.confirmText?.call(args) ?? '${tool.name} $args';
      final ok = confirm != null && await confirm!(tool, text);
      if (!ok) {
        return _log(
          ctx,
          name,
          args,
          AiToolResult.error('The user declined. Do not retry unless asked.'),
        );
      }
    }

    AiToolResult result;
    try {
      result = await tool.run(ctx, args);
    } catch (e, st) {
      debugPrint('[AiTool] $name threw: $e\n$st');
      result = AiToolResult.error('Failed: $e');
    }
    return _log(ctx, name, args, result);
  }

  AiToolResult _log(
    AiToolContext ctx,
    String name,
    Map<String, Object?> args,
    AiToolResult r,
  ) {
    audit.add(
      AiToolLogEntry(
        tool: name,
        args: args,
        ok: r.ok,
        uid: ctx.access?.uid,
        error: r.error,
      ),
    );
    return r;
  }

  /// Checks and normalises the model's arguments against [params]: required
  /// present, enums in range, numbers parsed, dates `YYYY-MM-DD`, times
  /// `HH:MM`. Unknown keys are dropped.
  static ({Map<String, Object?> args, String? error}) validateArgs(
    Map<String, AiParam> params,
    Map<String, Object?> raw,
  ) {
    final out = <String, Object?>{};
    for (final e in params.entries) {
      final v = raw[e.key];
      if (v == null || (v is String && v.trim().isEmpty)) {
        if (e.value.required) {
          return (args: out, error: 'Missing ${e.key}');
        }
        continue;
      }
      final (value, err) = _coerce(e.key, e.value, v);
      if (err != null) return (args: out, error: err);
      out[e.key] = value;
    }
    return (args: out, error: null);
  }

  static final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final _time = RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$');

  static (Object?, String?) _coerce(String key, AiParam p, Object v) {
    switch (p.type) {
      case AiParamType.string:
        return (v.toString().trim(), null);
      case AiParamType.date:
        final s = v.toString().trim();
        if (!_date.hasMatch(s) || DateTime.tryParse(s) == null) {
          return (null, '$key must be YYYY-MM-DD');
        }
        return (s, null);
      case AiParamType.time:
        final s = v.toString().trim();
        if (!_time.hasMatch(s)) return (null, '$key must be HH:MM');
        return (s, null);
      case AiParamType.integer:
      case AiParamType.number:
        final n = v is num ? v : num.tryParse(v.toString());
        if (n == null) return (null, '$key must be a number');
        if (p.min != null && n < p.min!) return (null, '$key below ${p.min}');
        if (p.max != null && n > p.max!) return (null, '$key above ${p.max}');
        return (p.type == AiParamType.integer ? n.round() : n.toDouble(), null);
      case AiParamType.boolean:
        if (v is bool) return (v, null);
        final s = v.toString().toLowerCase();
        if (s == 'true' || s == 'false') return (s == 'true', null);
        return (null, '$key must be true or false');
      case AiParamType.enumeration:
        final s = v.toString().trim();
        if (!p.enumValues!.contains(s)) {
          return (null, '$key must be one of ${p.enumValues!.join(', ')}');
        }
        return (s, null);
      case AiParamType.list:
        if (v is! List) return (null, '$key must be a list');
        final items = <Object?>[];
        for (final item in v) {
          if (item == null) continue;
          final (value, err) = _coerce(key, p.items!, item);
          if (err != null) return (null, err);
          items.add(value);
        }
        return (items, null);
      case AiParamType.object:
        if (v is! Map) return (null, '$key must be an object');
        final r = validateArgs(p.properties!, v.cast<String, Object?>());
        return (r.args, r.error);
    }
  }
}
