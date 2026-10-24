import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/pdf_text.dart';
import '../templates/doc_template.dart';
import 'doc_repository.dart';

class DocNumbering {
  static Future<String> next(DocKind kind, DateTime date) async {
    final settings = await DocRepository.instance.clinicSettingsOnce();
    final prefix = settings.prefixFor(kind);
    final fy = financialYear(date);
    final tenant = DocRepository.instance.tenantOrNull;
    if (tenant == null) return _offline(prefix, kind, fy);
    final ref = FirebaseFirestore.instance
        .collection('clinics')
        .doc(tenant)
        .collection('doc_counters')
        .doc('${kind.name}_$fy');
    try {
      final n = await FirebaseFirestore.instance
          .runTransaction<int>((tx) async {
            final snap = await tx.get(ref);
            final last = (snap.data()?['last'] as num?)?.toInt() ?? 0;
            tx.set(ref, {
              'last': last + 1,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            return last + 1;
          })
          .timeout(const Duration(seconds: 6));
      return '$prefix-$fy/${n.toString().padLeft(4, '0')}';
    } catch (_) {
      return _offline(prefix, kind, fy);
    }
  }

  static Future<String> _offline(String prefix, DocKind kind, String fy) async {
    final prefs = await SharedPreferences.getInstance();
    var code = prefs.getString('docs.deviceCode');
    if (code == null || code.length != 2) {
      const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      final rnd = Random();
      code = '${letters[rnd.nextInt(26)]}${letters[rnd.nextInt(26)]}';
      await prefs.setString('docs.deviceCode', code);
    }
    final key = 'docs.localSeq.${kind.name}.$fy';
    final seq = (prefs.getInt(key) ?? 0) + 1;
    await prefs.setInt(key, seq);
    return '$prefix-$fy/$code${seq.toString().padLeft(3, '0')}';
  }

  static bool isValidPrefix(String p) =>
      RegExp(r'^[A-Za-z0-9]{1,5}$').hasMatch(p);
}
