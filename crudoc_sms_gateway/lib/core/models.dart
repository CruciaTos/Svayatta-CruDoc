/// Represents the current operational status of the SMS Gateway.
enum GatewayStatus {
  online,
  offline,
  noSim,
  permissionDenied,
  ready,
  busy,
  error;

  String get label {
    switch (this) {
      case GatewayStatus.online:
        return 'Online';
      case GatewayStatus.offline:
        return 'Offline';
      case GatewayStatus.noSim:
        return 'No SIM';
      case GatewayStatus.permissionDenied:
        return 'Permission Denied';
      case GatewayStatus.ready:
        return 'Ready';
      case GatewayStatus.busy:
        return 'Busy';
      case GatewayStatus.error:
        return 'Error';
    }
  }
}

/// Represents a single SMS log entry shown on the dashboard.
class SmsLogEntry {
  final String requestId;
  final String phone;
  final String message;
  final String status; // sent, failed, duplicate
  final String? error;
  final DateTime timestamp;

  const SmsLogEntry({
    required this.requestId,
    required this.phone,
    required this.message,
    required this.status,
    this.error,
    required this.timestamp,
  });
}
