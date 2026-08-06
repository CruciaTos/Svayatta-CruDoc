import 'package:flutter/foundation.dart';

@immutable
class InvoiceModel {
  final String id;
  final String doctorId;
  final String? patientId;
  final String patientName;
  final String service;
  final double amount;
  final String status; // 'Paid', 'Pending', 'Overdue'
  final DateTime date;
  final DateTime? dueDate;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const InvoiceModel({
    required this.id,
    required this.doctorId,
    this.patientId,
    required this.patientName,
    required this.service,
    required this.amount,
    required this.status,
    required this.date,
    this.dueDate,
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPaid => status.toLowerCase() == 'paid';
  bool get isPending => status.toLowerCase() == 'pending';
  bool get isOverdue => status.toLowerCase() == 'overdue';

  InvoiceModel copyWith({
    String? id,
    String? doctorId,
    String? patientId,
    String? patientName,
    String? service,
    double? amount,
    String? status,
    DateTime? date,
    DateTime? dueDate,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InvoiceModel(
      id: id ?? this.id,
      doctorId: doctorId ?? this.doctorId,
      patientId: patientId ?? this.patientId,
      patientName: patientName ?? this.patientName,
      service: service ?? this.service,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      date: date ?? this.date,
      dueDate: dueDate ?? this.dueDate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'doctorId': doctorId,
      'patientId': patientId,
      'patientName': patientName,
      'service': service,
      'amount': amount,
      'status': status,
      'date': date.millisecondsSinceEpoch,
      'dueDate': dueDate?.millisecondsSinceEpoch,
      'notes': notes,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory InvoiceModel.fromMap(Map<String, dynamic> map) {
    return InvoiceModel(
      id: (map['id'] ?? '').toString(),
      doctorId: (map['doctorId'] ?? '').toString(),
      patientId: map['patientId'] as String?,
      patientName: (map['patientName'] ?? '').toString(),
      service: (map['service'] ?? '').toString(),
      amount: map['amount'] is num
          ? (map['amount'] as num).toDouble()
          : (map['amount'] is String
              ? (double.tryParse(map['amount'] as String) ?? 0.0)
              : 0.0),
      status: (map['status'] ?? 'Pending').toString(),
      date: map['date'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['date'] as int)
          : (map['date'] is String
              ? DateTime.tryParse(map['date'] as String) ?? DateTime.now()
              : DateTime.now()),
      dueDate: map['dueDate'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['dueDate'] as int)
          : null,
      notes: (map['notes'] ?? '').toString(),
      createdAt: map['createdAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int)
          : DateTime.now(),
      updatedAt: map['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : DateTime.now(),
    );
  }
}
