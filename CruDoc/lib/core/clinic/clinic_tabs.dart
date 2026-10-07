import 'package:doctor_management_app/core/clinic/clinic_access.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';

/// Whether this person's role (and their own feature choice) lets them open
/// desktop [tab]. Pages they can't open are left out of the sidebar, not
/// shown as an upgrade. No clinic access yet (or a solo doctor): every tab.
bool clinicAllowsDesktopTab(ClinicAccess? access, int tab) {
  if (access == null || access.isOwner) return true;
  if (tab == DesktopTab.dashboard || tab == DesktopTab.settings) return true;
  // Dental and radiology pages read clinical records, except the
  // sterilization log (stock) and the procedure list (clinic settings).
  if (tab == DesktopTab.sterilization) {
    return access.can(ClinicPermission.inventory) ||
        access.can(ClinicPermission.clinicalView);
  }
  if (tab == DesktopTab.procedures) {
    return access.can(ClinicPermission.settings) ||
        access.can(ClinicPermission.clinicalView);
  }
  if (DesktopTab.isDental(tab) || DesktopTab.isRadiology(tab)) {
    return access.can(ClinicPermission.clinicalView);
  }
  if (tab == DesktopTab.appointments) {
    return access.allowsModule('appointments') || access.allowsModule('queue');
  }
  return access.allowsModule(DoctorFeatureGuard.getModuleKeyForDesktopTab(tab));
}

/// The same for the phone's bottom tabs.
bool clinicAllowsMobileTab(ClinicAccess? access, int tab) {
  if (access == null || access.isOwner) return true;
  return switch (tab) {
    MobileTab.schedule =>
      access.allowsModule('appointments') || access.allowsModule('queue'),
    MobileTab.patients => access.allowsModule('patients'),
    MobileTab.revenue => access.allowsModule('revenue'),
    _ => true,
  };
}
