import 'package:flutter/material.dart';
import 'package:tenacity/src/models/attendance_model.dart';
import 'package:tenacity/src/models/class_model.dart';
import 'package:tenacity/src/models/term_model.dart';
import 'package:tenacity/src/services/timetable_service.dart';

class TimetableController extends ChangeNotifier {
  final TimetableService _service;

  TimetableController({required TimetableService service}) : _service = service;

  bool isLoading = false;
  String? errorMessage;

  /// Terms
  List<Term> allTerms = [];
  Term? activeTerm;

  /// Classes
  List<ClassModel> allClasses = [];

  /// For example, which week the user is currently viewing.
  /// (Could be 1..activeTerm.totalWeeks, if activeTerm is not null)
  int currentWeek = 1;

  /// If you want to store or display attendance data for the selected classes/week
  /// You could keep a map: { classId: Attendance } or a list, etc.
  Map<String, Attendance> attendanceByClass = {};

  /// --- Public Methods ---

  /// 1) Load all terms from Firestore
  Future<void> loadAllTerms() async {
    _startLoading();
    try {
      final terms = await _service.fetchAllTerms();
      allTerms = terms;
      // Optionally, pick the active one from the list
      // activeTerm = terms.firstWhere((t) => t.isActive, orElse: () => null);
      _stopLoading();
    } catch (e) {
      _handleError('Failed to load terms: $e');
    }
  }

  /// 2) Fetch the active term
  Future<void> loadActiveTerm() async {
    print('loading active term');
    _startLoading();
    try {
      final term = await _service.fetchActiveOrUpcomingTerm();
      activeTerm = term;
      print(activeTerm);
      // Reset currentWeek to 1
      currentWeek = 1;
      _stopLoading();
    } catch (e) {
      print('no active term found');
      _handleError('Failed to load active term: $e');
    }
  }

  /// 3) Load all classes
  Future<void> loadAllClasses() async {
    _startLoading();
    try {
      final classes = await _service.fetchAllClasses();
      allClasses = classes;
      _stopLoading();
    } catch (e) {
      _handleError('Failed to load classes: $e');
    }
  }

  /// 4) Generate Attendance Docs for a given class/term
  Future<void> generateAttendanceForTerm({
    required ClassModel classModel,
    required Term term,
  }) async {
    _startLoading();
    try {
      await _service.generateAttendanceDocsForTerm(classModel, term);
      _stopLoading();
    } catch (e) {
      _handleError('Failed to generate attendance docs: $e');
    }
  }

  /// 5) Load attendance for all classes for the current week
  Future<void> loadAttendanceForWeek() async {
    if (activeTerm == null) {
      _handleError('No active term to load attendance from');
      return;
    }
    _startLoading();
    try {
      attendanceByClass.clear();
      final termId = activeTerm!.id;
      final docId = '${termId}_W$currentWeek'; // e.g., "2025_T1_W3"
      
      // Fetch attendance docs concurrently instead of sequentially.
      final futures = allClasses.map((c) async {
        final attendance = await _service.fetchAttendanceDoc(
          classId: c.id,
          attendanceDocId: docId,
        );
        if (attendance != null) {
          attendanceByClass[c.id] = attendance;
        }
      }).toList();
      
      await Future.wait(futures);
      _stopLoading();
    } catch (e) {
      _handleError('Failed to load attendance for week $currentWeek: $e');
    }
  }

  /// Moves the currentWeek forward by 1 (if within the term range)
  void incrementWeek() {
    if (activeTerm == null) return;
    if (currentWeek < activeTerm!.totalWeeks) {
      currentWeek++;
      notifyListeners();
    }
  }

  /// Moves currentWeek backward by 1 (if > 1)
  void decrementWeek() {
    if (currentWeek > 1) {
      currentWeek--;
      notifyListeners();
    }
  }

  /// --- Enrollment Methods ---

  /// Permanently enroll a student in a class
  Future<void> enrollStudentPermanent({
    required String classId,
    required String studentId,
  }) async {
    _startLoading();
    try {
      await _service.enrollStudentPermanent(classId: classId, studentId: studentId);
      _stopLoading();
    } catch (e) {
      _handleError('Failed to permanently enroll student: $e');
    }
  }

  /// Unenroll from a class permanently
  Future<void> unenrollStudentPermanent({
    required String classId,
    required String studentId,
  }) async {
    _startLoading();
    try {
      await _service.unenrollStudentPermanent(classId: classId, studentId: studentId);
      _stopLoading();
    } catch (e) {
      _handleError('Failed to permanently unenroll student: $e');
    }
  }

  /// One-off booking
  Future<void> enrollStudentOneOff({
    required String classId,
    required String studentId,
    required String attendanceDocId,
  }) async {
    _startLoading();
    try {
      await _service.enrollStudentOneOff(
        classId: classId,
        studentId: studentId,
        attendanceDocId: attendanceDocId,
      );
      _stopLoading();
    } catch (e) {
      _handleError('Failed to book one-off class: $e');
    }
  }

  /// Cancel for a specific week
  Future<void> cancelStudentForWeek({
    required String classId,
    required String studentId,
    required String attendanceDocId,
  }) async {
    _startLoading();
    try {
      await _service.cancelStudentForWeek(
        classId: classId,
        studentId: studentId,
        attendanceDocId: attendanceDocId,
      );
      _stopLoading();
    } catch (e) {
      _handleError('Failed to cancel class for week: $e');
    }
  }

  /// Reschedule to a different class
  Future<void> rescheduleToDifferentClass({
    required String oldClassId,
    required String oldAttendanceDocId,
    required String newClassId,
    required String newAttendanceDocId,
    required String studentId,
  }) async {
    _startLoading();
    try {
      await _service.rescheduleToDifferentClass(
        oldClassId: oldClassId,
        oldAttendanceDocId: oldAttendanceDocId,
        newClassId: newClassId,
        newAttendanceDocId: newAttendanceDocId,
        studentId: studentId,
      );
      _stopLoading();
    } catch (e) {
      _handleError('Failed to reschedule student: $e');
    }
  }

  /// Example of directly incrementing tokens (if needed)
  Future<void> incrementTokens(String studentId, int count) async {
    _startLoading();
    try {
      await _service.incrementLessonTokens(studentId, count);
      _stopLoading();
    } catch (e) {
      _handleError('Failed to increment tokens: $e');
    }
  }

  /// Example of directly decrementing tokens
  Future<void> decrementTokens(String studentId, int count) async {
    _startLoading();
    try {
      await _service.decrementLessonTokens(studentId, count);
      _stopLoading();
    } catch (e) {
      _handleError('Failed to decrement tokens: $e');
    }
  }

  /// --- Internal Helpers ---

  void _startLoading() {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
  }

  void _stopLoading() {
    isLoading = false;
    notifyListeners();
  }

  void _handleError(String message) {
    isLoading = false;
    errorMessage = message;
    notifyListeners();
  }

  Future<void> createNewClass(ClassModel newClass) async {
    _startLoading();
    try {
      await _service.createClass(newClass);
      // Immediately generate attendance docs for this new class if an active term exists.
      if (activeTerm != null) {
        await _service.generateAttendanceDocsForTerm(newClass, activeTerm!);
      }
      await loadAllClasses();
      _stopLoading();
    } catch (e) {
      _handleError('Failed to add new class: $e');
    }
  }

  Future<void> populateAttendanceDocsForActiveTerm() async {
    if (activeTerm == null) return;
    _startLoading();
    try {
      // Run for all classes concurrently.
      await Future.wait(
        allClasses.map((classModel) =>
            _service.generateAttendanceDocsForTerm(classModel, activeTerm!))
      );
      _stopLoading();
    } catch (e) {
      _handleError("Error populating attendance docs: $e");
    }
  }

}
