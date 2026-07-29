// CruDoc Super Admin Panel
// Barrel export file for the Super Admin module.
// Import this file to access all Super Admin features.

export 'config/app_constants.dart';
export 'config/enums.dart';

// Models
export 'models/super_admin_model.dart';
export 'models/doctor_model.dart';
export 'models/subscription_model.dart';
export 'models/plan_model.dart';
export 'models/feature_flag_model.dart';
export 'models/analytics_model.dart';
export 'models/support_ticket_model.dart';
export 'models/audit_log_model.dart';
export 'models/dashboard_stats_model.dart';

// Services
export 'services/firebase_service.dart';
export 'services/auth_service.dart';
export 'services/doctor_service.dart';
export 'services/subscription_service.dart';
export 'services/analytics_service.dart';
export 'services/audit_log_service.dart';
export 'services/support_service.dart';
export 'services/feature_module_service.dart';

// Providers
export 'providers/auth_provider.dart';
export 'providers/doctor_provider.dart';
export 'providers/dashboard_provider.dart';
export 'providers/ui_provider.dart';

// Middleware
export 'middleware/auth_middleware.dart';

// Screens
export 'screens/auth/login_screen.dart';
export 'screens/main_shell.dart';
export 'screens/dashboard/dashboard_screen.dart';
export 'screens/dashboard/doctors_screen.dart';