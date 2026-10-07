/// What a clinic member may do. The keys are stored in Firestore and checked
/// by firestore.rules and storage.rules: never rename one.
enum ClinicPermission {
  patientsView('patients.view', 'See patients', 'Patients'),
  patientsEdit('patients.edit', 'Add and edit patients', 'Patients'),
  clinicalView('clinical.view', 'See clinical records', 'Clinical'),
  clinicalEdit('clinical.edit', 'Write clinical records', 'Clinical'),
  schedule('schedule', 'Appointments, queue and home visits', 'Front desk'),
  billing('billing', 'Invoices and payments', 'Money'),
  revenue('revenue', 'Revenue and reports', 'Money'),
  inventory('inventory', 'Inventory and sterilization', 'Stock'),
  messaging('messaging', 'WhatsApp and reminders', 'Front desk'),
  ai('ai', 'AI assistant and voice scribe', 'Clinical'),
  team('team', 'Manage team and roles', 'Admin'),
  settings('settings', 'Clinic settings and letterhead', 'Admin');

  const ClinicPermission(this.key, this.label, this.group);
  final String key;
  final String label;
  final String group;

  static ClinicPermission? fromKey(String key) {
    for (final p in ClinicPermission.values) {
      if (p.key == key) return p;
    }
    return null;
  }
}

/// Adds implied permissions (see Design B) and drops unknown keys.
Set<ClinicPermission> normalizePermissions(Iterable<String> keys) {
  final result = <ClinicPermission>{};
  for (final k in keys) {
    final p = ClinicPermission.fromKey(k);
    if (p != null) {
      result.add(p);
    }
  }

  // Implied permissions:
  // patients.edit -> patients.view
  // clinical.view -> patients.view
  // clinical.edit -> clinical.view + patients.view
  if (result.contains(ClinicPermission.clinicalEdit)) {
    result.add(ClinicPermission.clinicalView);
    result.add(ClinicPermission.patientsView);
  }
  if (result.contains(ClinicPermission.clinicalView)) {
    result.add(ClinicPermission.patientsView);
  }
  if (result.contains(ClinicPermission.patientsEdit)) {
    result.add(ClinicPermission.patientsView);
  }
  return result;
}
