import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

@immutable
class Attendance {
  final String id;
  final DateTime date;
  final String termId;
  final DateTime updatedAt;
  final String updatedBy;
  final int weekNumber;
  final List<String> attendance;

  const Attendance({
    required this.id,
    required this.date,
    required this.termId,
    required this.updatedAt,
    required this.updatedBy,
    required this.weekNumber,
    required this.attendance,
  });

  factory Attendance.fromMap(Map<String, dynamic> data, String documentId) {
    return Attendance(
      id: documentId,
      date: (data['date'] as Timestamp).toDate(),
      termId: data['termId'],
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      updatedBy: data['updatedBy'],
      weekNumber: data['weekNum'] ?? 0,
      attendance: List<String>.from(data['attendance'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': Timestamp.fromDate(date),
      'termId': termId,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'updatedBy': updatedBy,
      'weekNum': weekNumber,
      'attendance': attendance,
    };
  }

  Attendance copyWith({
    String? id,
    DateTime? date,
    String? termId,
    DateTime? updatedAt,
    String? updatedBy,
    int? weekNumber,
    List<String>? attendance,
  }) {
    return Attendance(
      id: id ?? this.id,
      date: date ?? this.date,
      termId: termId ?? this.termId,
      updatedAt: updatedAt ?? this.date,
      updatedBy: updatedBy ?? this.updatedBy,
      weekNumber: weekNumber ?? this.weekNumber,
      attendance: attendance ?? this.attendance,
    );
  }
}
