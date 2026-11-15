import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/services/ai_consent.dart';
import 'package:doctor_management_app/core/services/api_usage_service.dart';
import 'package:doctor_management_app/core/services/gemini_json_client.dart';

import 'ai_tool.dart';
import 'ai_tool_executor.dart';
import 'ai_tool_registry.dart';

/// One step the agent took, for the UI (tool chips, Undo buttons).
class AiAgentStep {
  const AiAgentStep(this.tool, this.args, this.result);
  final String tool;
  final Map<String, Object?> args;
  final AiToolResult result;
}

class AiAgentReply {
  const AiAgentReply({required this.text, required this.steps});

  /// What the model says back to the user.
  final String text;
  final List<AiAgentStep> steps;

  /// Undo for every write that ran, newest first.
  List<Future<void> Function()> get undos => [
    for (final s in steps.reversed)
      if (s.result.undo != null) s.result.undo!,
  ];
}

/// Runs a request through Gemini with function calling: send tools, run the
/// calls the model asks for, feed results back, until it answers in text or
/// [maxSteps] tool rounds pass. Keeps chat history between [send] calls.
class AiAgent {
  AiAgent({
    required this.registry,
    required this.executor,
    this.maxSteps = 8,
    GeminiJsonClient? modelSource,
  }) : _modelSource = modelSource ?? GeminiJsonClient();

  final AiToolRegistry registry;
  final AiToolExecutor executor;
  final int maxSteps;
  final GeminiJsonClient _modelSource;

  final List<Content> _history = [];

  void reset() => _history.clear();

  static String systemPrompt(AiToolContext ctx) {
    final today = DateTime.now();
    final d =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return '''
You are the assistant inside CruDoc, a clinic management app used in India.
You act only through the tools you are given. Today is $d (local time, India).
Rules:
- Write tools need IDs. Find the patient/appointment first with a find or list tool.
- If a search returns more than one match, ask the user which one. Never guess.
- Never invent clinical facts, doses, fees or dates the user did not give.
- If a tool says the user declined, stop and say so.
- If you lack a tool for something, say what the user can open instead.
- Answer in one or two short sentences, in the user's language (English, Hindi or Marathi).
- Times are 24-hour HH:MM in tool calls; dates are YYYY-MM-DD.
${ctx.screen == null ? '' : 'The user is on the "${ctx.screen}" screen.'}
${ctx.openPatientId == null ? '' : 'The open patient has id ${ctx.openPatientId}; "this patient" means them.'}
''';
  }

  Future<AiAgentReply> send(
    AiToolContext ctx,
    String userText, {
    Set<AiToolGroup>? groups,
  }) async {
    if (!await AiConsent.granted) throw const AiConsentRequired();

    final tools = registry.forRequest(
      ctx,
      groups: groups ?? AiToolRegistry.groupsForScreen(ctx.screen),
    );
    final model = FirebaseAI.googleAI().generativeModel(
      model: await _modelSource.modelName(),
      systemInstruction: Content.system(systemPrompt(ctx)),
      generationConfig: GenerationConfig(temperature: 0.1),
      tools: [
        Tool.functionDeclarations([for (final t in tools) t.toDeclaration()]),
      ],
    );

    _history.add(Content.text(userText));
    final steps = <AiAgentStep>[];

    for (var round = 0; round <= maxSteps; round++) {
      final GenerateContentResponse response;
      try {
        response = await model.generateContent(_history);
      } catch (e) {
        ApiUsage.record(ApiService.gemini, feature: 'ai_agent', error: true);
        rethrow;
      }
      final usage = response.usageMetadata;
      ApiUsage.record(
        ApiService.gemini,
        feature: 'ai_agent',
        inputTokens: usage?.promptTokenCount ?? 0,
        outputTokens: usage?.candidatesTokenCount ?? 0,
      );

      final candidate = response.candidates.firstOrNull;
      if (candidate == null) break;
      _history.add(candidate.content);

      final calls = response.functionCalls.toList();
      if (calls.isEmpty) {
        return AiAgentReply(text: response.text?.trim() ?? '', steps: steps);
      }
      if (round == maxSteps) break;

      final responses = <FunctionResponse>[];
      for (final call in calls) {
        final result = await executor.execute(ctx, call.name, call.args);
        steps.add(AiAgentStep(call.name, call.args, result));
        responses.add(
          FunctionResponse(call.name, result.toModelJson(), id: call.id),
        );
      }
      _history.add(Content.functionResponses(responses));
    }

    debugPrint('[AiAgent] stopped after $maxSteps tool rounds');
    return AiAgentReply(
      text: steps.isEmpty
          ? 'Sorry, I could not do that.'
          : 'I stopped partway. Check what was done.',
      steps: steps,
    );
  }
}
