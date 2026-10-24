import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/storage_sync_queue.dart';

import '../templates/doc_presets.dart';
import '../templates/doc_template.dart';
import 'doc_settings_models.dart';

class DocTemplateConflict implements Exception {
  const DocTemplateConflict([
    this.message = 'Template was modified concurrently',
  ]);
  final String message;
  @override
  String toString() => message;
}

class DocRepository {
  DocRepository._();
  static final instance = DocRepository._();

  String? get _tenant {
    final t = ClinicSession.instance.tenantId;
    if (t == null || t.isEmpty || t == kLocalDoctorId) return null;
    return t;
  }

  String? get tenantOrNull => _tenant;

  String? get _me => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _clinic(String t) =>
      FirebaseFirestore.instance.collection('clinics').doc(t);

  // ---------------------------------------------------------------------------
  // One-shot reads (never throw)
  // ---------------------------------------------------------------------------

  Future<ClinicDocSettings> clinicSettingsOnce() async {
    final t = _tenant;
    if (t == null) return const ClinicDocSettings();
    final ref = _clinic(t).collection('doc_settings').doc('clinic');
    return _getDocOnce(
      ref,
      parse: (m) => ClinicDocSettings.fromMap(m),
      fallback: const ClinicDocSettings(),
    );
  }

  Future<DoctorDocProfile?> doctorProfileOnce(String uid) async {
    final t = _tenant;
    if (t == null || uid.isEmpty) return null;
    final ref = _clinic(t).collection('doc_doctors').doc(uid);
    return _getDocOnce(
      ref,
      parse: (m) => m == null ? null : DoctorDocProfile.fromMap(m),
      fallback: null,
    );
  }

  Future<Map<String, dynamic>?> memberOnce(String uid) async {
    final t = _tenant;
    if (t == null || uid.isEmpty) return null;
    final ref = _clinic(t).collection('members').doc(uid);
    return _getDocOnce(ref, parse: (m) => m, fallback: null);
  }

  Future<List<DocTemplate>> templatesOnce() async {
    final t = _tenant;
    if (t == null) return builtinTemplates;
    final col = _clinic(t).collection('doc_templates');
    try {
      final snap = await col.get().timeout(const Duration(seconds: 4));
      return [
        ...builtinTemplates,
        for (final doc in snap.docs) DocTemplate.fromMap(doc.id, doc.data()),
      ];
    } catch (_) {
      try {
        final snap = await col.get(const GetOptions(source: Source.cache));
        return [
          ...builtinTemplates,
          for (final doc in snap.docs) DocTemplate.fromMap(doc.id, doc.data()),
        ];
      } catch (_) {
        return builtinTemplates;
      }
    }
  }

  Future<Map<String, dynamic>?> myLegacyProfileOnce() async {
    final me = _me;
    if (me == null || me.isEmpty) return null;
    final ref = FirebaseFirestore.instance.collection('users').doc(me);
    return _getDocOnce(ref, parse: (m) => m, fallback: null);
  }

  Future<List<ClinicMember>> activeDoctorsOnce() async {
    final t = _tenant;
    if (t == null) return const [];
    final col = _clinic(t).collection('members');
    QuerySnapshot<Map<String, dynamic>>? snap;
    try {
      snap = await col
          .where('active', isEqualTo: true)
          .get()
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      try {
        snap = await col
            .where('active', isEqualTo: true)
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        return const [];
      }
    }
    return [
      for (final doc in snap.docs)
        if (doc.data()['kind'] == 'doctor')
          ClinicMember.fromMap(doc.id, doc.data()),
    ];
  }

  Future<T> _getDocOnce<T>(
    DocumentReference<Map<String, dynamic>> ref, {
    required T Function(Map<String, dynamic>? data) parse,
    required T fallback,
  }) async {
    try {
      final snap = await ref.get().timeout(const Duration(seconds: 4));
      if (snap.exists && snap.data() != null) {
        return parse(snap.data());
      }
      return fallback;
    } catch (_) {
      try {
        final snap = await ref.get(const GetOptions(source: Source.cache));
        if (snap.exists && snap.data() != null) {
          return parse(snap.data());
        }
        return fallback;
      } catch (_) {
        return fallback;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Template visibility & resolution
  // ---------------------------------------------------------------------------

  List<DocTemplate> visibleTemplates(
    List<DocTemplate> all,
    ClinicDocSettings s, {
    DocKind? kind,
  }) {
    final me = _me;
    final filtered = all.where((t) {
      if (kind != null && !t.appliesTo(kind)) return false;
      if (t.isBuiltin) return true;
      if (t.scope == DocScope.clinic) return true;
      if (t.scope == DocScope.doctor && t.ownerUid == me && !s.lockTemplates) {
        return true;
      }
      return false;
    }).toList();

    if (s.lockTemplates) {
      final hasClinic = filtered.any((t) => t.scope == DocScope.clinic);
      if (hasClinic) {
        return filtered.where((t) => !t.isBuiltin).toList();
      }
    }
    return filtered;
  }

  Future<DocTemplate> resolveTemplate(
    DocKind kind, {
    String? issuingDoctorUid,
    String? explicitId,
  }) async {
    final all = await templatesOnce();
    final settings = await clinicSettingsOnce();

    // A template that doesn't fit this kind (an 80 mm receipt for a
    // prescription) or comes from a newer app is passed over, so the next
    // choice in line is used.
    DocTemplate? find(String? id) {
      if (id == null || id.isEmpty) return null;
      for (final t in all) {
        if (t.id == id) return t.appliesTo(kind) && !t.tooNew ? t : null;
      }
      return null;
    }

    // 1. Stored on document
    DocTemplate? selected = find(explicitId);

    // 2. Doctor default
    if (selected == null &&
        !settings.lockTemplates &&
        issuingDoctorUid != null &&
        issuingDoctorUid.isNotEmpty) {
      final prof = await doctorProfileOnce(issuingDoctorUid);
      final docDef = prof?.defaults[kind.name];
      selected = find(docDef);
    }

    // 3. Clinic default
    if (selected == null) {
      final clinicDef = settings.defaults[kind.name];
      selected = find(clinicDef);
    }

    // 4. Fallback builtin
    return selected ?? builtinById('builtin.classic');
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  Future<void> saveClinicSettings(ClinicDocSettings s) async {
    final t = _tenant;
    if (t == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final me = _me ?? '';
    final updated = s.copyWith(updatedAt: now);
    final map = updated.toMap()..['updatedByUid'] = me;
    await _clinic(t)
        .collection('doc_settings')
        .doc('clinic')
        .set(map, SetOptions(merge: false));
  }

  Future<void> saveMyProfile(DoctorDocProfile p) async {
    final t = _tenant;
    final me = _me;
    if (p.uid != me) {
      throw StateError(
        'Cannot save profile for another doctor: ${p.uid} != $me',
      );
    }
    if (t == null || me == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = p.copyWith(updatedAt: now);
    final map = updated.toMap()..['updatedByUid'] = me;
    await _clinic(
      t,
    ).collection('doc_doctors').doc(me).set(map, SetOptions(merge: false));
  }

  Future<DocTemplate> saveTemplate(
    DocTemplate t, {
    required int loadedUpdatedAt,
    bool force = false,
  }) async {
    final tenant = _tenant;
    if (tenant == null) throw StateError('No active clinic');
    final me = _me ?? '';
    final col = _clinic(tenant).collection('doc_templates');
    final String docId = (t.isBuiltin || t.id.isEmpty) ? col.doc().id : t.id;
    final ref = col.doc(docId);

    if (!t.isBuiltin && t.id.isNotEmpty && !force) {
      final snap = await ref.get().timeout(const Duration(seconds: 4));
      if (snap.exists && snap.data() != null) {
        final currentUpdated =
            (snap.data()!['updatedAt'] as num?)?.toInt() ?? 0;
        if (currentUpdated != loadedUpdatedAt) {
          throw const DocTemplateConflict();
        }
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final saved = t.copyWith(id: docId, updatedAt: now, updatedByUid: me);
    await ref.set(saved.toMap(), SetOptions(merge: false));
    return saved;
  }

  Future<void> deleteTemplate(DocTemplate t) async {
    final tenant = _tenant;
    if (tenant == null) return;
    final col = _clinic(tenant).collection('doc_templates');
    await col.doc(t.id).delete();

    final hasSettings =
        ClinicSession.instance.access == null ||
        ClinicSession.instance.access?.can(ClinicPermission.settings) == true;
    if (hasSettings) {
      final s = await clinicSettingsOnce();
      final newDefaults = Map<String, String>.from(s.defaults)
        ..removeWhere((k, v) => v == t.id);
      if (newDefaults.length != s.defaults.length) {
        await saveClinicSettings(s.copyWith(defaults: newDefaults));
      }
    }

    final me = _me;
    if (me != null) {
      final p = await doctorProfileOnce(me);
      if (p != null) {
        final newDefaults = Map<String, String>.from(p.defaults)
          ..removeWhere((k, v) => v == t.id);
        if (newDefaults.length != p.defaults.length) {
          await saveMyProfile(p.copyWith(defaults: newDefaults));
        }
      }
    }
  }

  Future<void> setDefault(
    DocKind kind,
    String templateId, {
    required bool forClinic,
  }) async {
    if (forClinic) {
      final s = await clinicSettingsOnce();
      final newDefaults = Map<String, String>.from(s.defaults)
        ..[kind.name] = templateId;
      await saveClinicSettings(s.copyWith(defaults: newDefaults));
    } else {
      final me = _me;
      if (me != null) {
        final p = (await doctorProfileOnce(me)) ?? DoctorDocProfile(uid: me);
        final newDefaults = Map<String, String>.from(p.defaults)
          ..[kind.name] = templateId;
        await saveMyProfile(p.copyWith(defaults: newDefaults));
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Riverpod Streams
// -----------------------------------------------------------------------------

final clinicDocSettingsProvider = StreamProvider<ClinicDocSettings>((ref) {
  ref.watch(clinicAccessProvider);
  final tenant = DocRepository.instance.tenantOrNull;
  if (tenant == null) return Stream.value(const ClinicDocSettings());
  final refDoc = FirebaseFirestore.instance
      .collection('clinics')
      .doc(tenant)
      .collection('doc_settings')
      .doc('clinic');
  return refDoc
      .snapshots()
      .map((snap) {
        if (!snap.exists || snap.data() == null) {
          return const ClinicDocSettings();
        }
        return ClinicDocSettings.fromMap(snap.data());
      })
      .transform(
        StreamTransformer.fromHandlers(
          handleError: (e, st, sink) => sink.add(const ClinicDocSettings()),
        ),
      );
});

final myDocProfileProvider = StreamProvider<DoctorDocProfile?>((ref) {
  ref.watch(clinicAccessProvider);
  final tenant = DocRepository.instance.tenantOrNull;
  final me = FirebaseAuth.instance.currentUser?.uid;
  if (tenant == null || me == null) return Stream.value(null);
  final refDoc = FirebaseFirestore.instance
      .collection('clinics')
      .doc(tenant)
      .collection('doc_doctors')
      .doc(me);
  return refDoc
      .snapshots()
      .map((snap) {
        if (!snap.exists || snap.data() == null) return null;
        return DoctorDocProfile.fromMap(snap.data());
      })
      .transform(
        StreamTransformer.fromHandlers(
          handleError: (e, st, sink) => sink.add(null),
        ),
      );
});

final docTemplatesProvider = StreamProvider<List<DocTemplate>>((ref) {
  ref.watch(clinicAccessProvider);
  final tenant = DocRepository.instance.tenantOrNull;
  if (tenant == null) return Stream.value(builtinTemplates);
  final col = FirebaseFirestore.instance
      .collection('clinics')
      .doc(tenant)
      .collection('doc_templates');
  return col
      .snapshots()
      .map((snap) {
        final stored = [
          for (final doc in snap.docs) DocTemplate.fromMap(doc.id, doc.data()),
        ];
        return [...builtinTemplates, ...stored];
      })
      .transform(
        StreamTransformer.fromHandlers(
          handleError: (e, st, sink) => sink.add(builtinTemplates),
        ),
      );
});
