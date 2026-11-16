import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai_tool.dart';
import '../core/ai_tool_registry.dart';
import 'appointment_tools.dart';
import 'billing_tools.dart';
import 'clinical_tools.dart';
import 'core_tools.dart';
import 'dental_tools.dart';
import 'file_tools.dart';
import 'inventory_tools.dart';
import 'messaging_tools.dart';
import 'patient_tools.dart';
import 'queue_tools.dart';
import 'task_tools.dart';
import 'team_tools.dart';

/// Every tool, in one list. Spec: docs/ai_tool_registry.md.
List<AiTool> allAiTools() => [
  ...coreTools(),
  ...patientTools(),
  ...appointmentTools(),
  ...queueTools(),
  ...dentalTools(),
  ...clinicalTools(),
  ...billingTools(),
  ...inventoryTools(),
  ...taskTools(),
  ...fileTools(),
  ...messagingTools(),
  ...teamTools(),
];

final aiToolRegistryProvider = Provider<AiToolRegistry>(
  (ref) => AiToolRegistry(allAiTools()),
);
