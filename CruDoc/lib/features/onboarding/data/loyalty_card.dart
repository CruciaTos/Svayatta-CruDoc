import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/demo_session_service.dart';

/// Months a doctor collects before the next one is free.
const int kLoyaltySlots = 5;

/// The doctor's loyalty card: one stamp per month with CruDoc, at most one
/// per calendar month. After [kLoyaltySlots] stamps the next month is free.
/// Joining stamps the first slot. Stored on `users/{uid}.loyalty`, so the
/// Super Admin sees it with the rest of the profile.
class LoyaltyCard {
  const LoyaltyCard({
    required this.stamps,
    required this.stampedMonths,
    this.freeMonthsClaimed = 0,
    this.joinedAt,
  });

  /// 0–[kLoyaltySlots] in the current cycle.
  final int stamps;

  /// Month keys ("2026-10") stamped in the current cycle.
  final List<String> stampedMonths;
  final int freeMonthsClaimed;

  /// When the card was first stamped; null until the server time lands.
  final DateTime? joinedAt;

  bool get freeMonthReady => stamps >= kLoyaltySlots;

  static LoyaltyCard? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return LoyaltyCard(
      stamps: ((raw['stamps'] as num?) ?? 0).toInt().clamp(0, kLoyaltySlots),
      stampedMonths: [
        for (final m in (raw['stampedMonths'] as List?) ?? const []) '$m',
      ],
      freeMonthsClaimed: ((raw['freeMonthsClaimed'] as num?) ?? 0).toInt(),
      joinedAt: raw['joinedAt'] is Timestamp
          ? (raw['joinedAt'] as Timestamp).toDate()
          : null,
    );
  }
}

String loyaltyMonthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// The signed-in doctor's card; null until it is first created.
final loyaltyCardProvider = StreamProvider<LoyaltyCard?>((ref) {
  if (DemoSessionService.isDemoMode) {
    return Stream.value(
      const LoyaltyCard(
        stamps: 3,
        stampedMonths: ['2026-08', '2026-09', '2026-10'],
        freeMonthsClaimed: 0,
      ),
    );
  }
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .snapshots()
      .map((doc) => LoyaltyCard.fromMap(doc.data()?['loyalty']));
});

class LoyaltyService {
  LoyaltyService._();

  static DocumentReference<Map<String, dynamic>>? _doc() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  /// Stamps this month's slot. Does nothing if this month is already
  /// stamped or the card is full (the free month must be claimed first).
  /// Creates the card on first use, so joining stamps slot one.
  static Future<LoyaltyCard?> stampThisMonth() async {
    final ref = _doc();
    if (ref == null) return null;
    final month = loyaltyMonthKey(DateTime.now());
    return FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final card =
          LoyaltyCard.fromMap(snap.data()?['loyalty']) ??
          const LoyaltyCard(stamps: 0, stampedMonths: []);
      if (card.freeMonthReady || card.stampedMonths.contains(month)) {
        return card;
      }
      final next = LoyaltyCard(
        stamps: card.stamps + 1,
        stampedMonths: [...card.stampedMonths, month],
        freeMonthsClaimed: card.freeMonthsClaimed,
        joinedAt: card.joinedAt,
      );
      tx.set(ref, {
        'loyalty': {
          'stamps': next.stamps,
          'stampedMonths': next.stampedMonths,
          'freeMonthsClaimed': next.freeMonthsClaimed,
          'lastStampAt': FieldValue.serverTimestamp(),
          if (card.stamps == 0 && card.freeMonthsClaimed == 0)
            'joinedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
      return next;
    });
  }

  /// Uses a full card: adds 30 days to the plan (from its expiry, or from
  /// today if it already ran out) and starts a new card.
  static Future<void> claimFreeMonth() async {
    final ref = _doc();
    if (ref == null) return;
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? const {};
      final card = LoyaltyCard.fromMap(data['loyalty']);
      if (card == null || !card.freeMonthReady) return;
      final now = DateTime.now();
      final raw = data['expiresDate'];
      final expires = raw is Timestamp
          ? raw.toDate()
          : raw is String
          ? DateTime.tryParse(raw)
          : null;
      final from = expires != null && expires.isAfter(now) ? expires : now;
      tx.set(ref, {
        'expiresDate': Timestamp.fromDate(from.add(const Duration(days: 30))),
        'loyalty': {
          'stamps': 0,
          'stampedMonths': <String>[],
          'freeMonthsClaimed': card.freeMonthsClaimed + 1,
          'lastClaimAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    });
  }
}
