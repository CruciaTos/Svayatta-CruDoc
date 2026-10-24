import 'dart:convert';

class InvoiceBillItem {
  const InvoiceBillItem({
    required this.name,
    this.qty = 1,
    required this.ratePaise,
    this.taxPct = 0,
    this.kind = 'treatment',
    this.note = '',
  });

  final String name;
  final int qty;
  final int ratePaise;
  final double taxPct;
  final String kind; // 'treatment' | 'medicine' | 'other'
  final String note;

  int get amountPaise => qty * ratePaise;
  int get taxPaise => (amountPaise * taxPct / 100).round();

  InvoiceBillItem copyWith({
    String? name,
    int? qty,
    int? ratePaise,
    double? taxPct,
    String? kind,
    String? note,
  }) {
    return InvoiceBillItem(
      name: name ?? this.name,
      qty: qty ?? this.qty,
      ratePaise: ratePaise ?? this.ratePaise,
      taxPct: taxPct ?? this.taxPct,
      kind: kind ?? this.kind,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'qty': qty,
    'rate': ratePaise,
    'tax': taxPct,
    'kind': kind,
    'note': note,
  };

  factory InvoiceBillItem.fromMap(Map<String, dynamic> m) {
    return InvoiceBillItem(
      name: (m['name'] ?? '').toString(),
      qty: (m['qty'] as num?)?.toInt() ?? 1,
      ratePaise: (m['rate'] as num?)?.toInt() ?? 0,
      taxPct: (m['tax'] as num?)?.toDouble() ?? 0.0,
      kind: (m['kind'] ?? 'treatment').toString(),
      note: (m['note'] ?? '').toString(),
    );
  }
}

class InvoiceBill {
  const InvoiceBill({
    this.items = const [],
    this.discountPaise = 0,
    this.roundOff = true,
    this.paidPaise = 0,
    this.paymentMode = '',
    this.templateId = '',
    this.signedByUid = '',
  });

  final List<InvoiceBillItem> items;
  final int discountPaise;
  final bool roundOff;
  final int paidPaise;
  final String paymentMode;
  final String templateId;
  final String signedByUid;

  InvoiceBill copyWith({
    List<InvoiceBillItem>? items,
    int? discountPaise,
    bool? roundOff,
    int? paidPaise,
    String? paymentMode,
    String? templateId,
    String? signedByUid,
  }) {
    return InvoiceBill(
      items: items ?? this.items,
      discountPaise: discountPaise ?? this.discountPaise,
      roundOff: roundOff ?? this.roundOff,
      paidPaise: paidPaise ?? this.paidPaise,
      paymentMode: paymentMode ?? this.paymentMode,
      templateId: templateId ?? this.templateId,
      signedByUid: signedByUid ?? this.signedByUid,
    );
  }

  Map<String, dynamic> toMap() => {
    'v': 1,
    'items': items.map((i) => i.toMap()).toList(),
    'discount': discountPaise,
    'roundOff': roundOff,
    'paid': paidPaise,
    'paymentMode': paymentMode,
    'templateId': templateId,
    'signedByUid': signedByUid,
  };

  String toJson() => jsonEncode(toMap());

  static InvoiceBill fromJson(String s) {
    if (s.trim().isEmpty) return const InvoiceBill();
    try {
      final decoded = jsonDecode(s);
      if (decoded is! Map) return const InvoiceBill();
      final map = Map<String, dynamic>.from(decoded);
      return InvoiceBill.fromMap(map);
    } catch (_) {
      return const InvoiceBill();
    }
  }

  factory InvoiceBill.fromMap(Map<String, dynamic> m) {
    final rawItems = m['items'];
    final items = <InvoiceBillItem>[];
    if (rawItems is List) {
      for (final it in rawItems) {
        if (it is Map) {
          items.add(InvoiceBillItem.fromMap(Map<String, dynamic>.from(it)));
        }
      }
    }
    return InvoiceBill(
      items: items,
      discountPaise: (m['discount'] as num?)?.toInt() ?? 0,
      roundOff: m['roundOff'] is bool ? m['roundOff'] as bool : true,
      paidPaise: (m['paid'] as num?)?.toInt() ?? 0,
      paymentMode: (m['paymentMode'] ?? '').toString(),
      templateId: (m['templateId'] ?? '').toString(),
      signedByUid: (m['signedByUid'] ?? '').toString(),
    );
  }
}

class InvoiceTotals {
  const InvoiceTotals({
    required this.subtotal,
    required this.tax,
    required this.discount,
    required this.roundOff,
    required this.grand,
    required this.paid,
    required this.balance,
  });

  final int subtotal;
  final int tax;
  final int discount;
  final int roundOff;
  final int grand;
  final int paid;
  final int balance;

  static InvoiceTotals of(InvoiceBill b) {
    final subtotal = b.items.fold<int>(0, (s, i) => s + i.amountPaise);
    final tax = b.items.fold<int>(0, (s, i) => s + i.taxPaise);
    final gross = subtotal + tax;
    final discount = b.discountPaise.clamp(0, gross).toInt();
    final net = gross - discount;
    final roundOff = b.roundOff ? (net / 100).round() * 100 - net : 0;
    final grand = net + roundOff;
    final paid = b.paidPaise.clamp(0, grand).toInt();
    return InvoiceTotals(
      subtotal: subtotal,
      tax: tax,
      discount: discount,
      roundOff: roundOff,
      grand: grand,
      paid: paid,
      balance: grand - paid,
    );
  }
}
