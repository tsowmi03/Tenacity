import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:tenacity/src/controllers/auth_controller.dart';
import 'package:tenacity/src/controllers/timetable_controller.dart';
import 'package:tenacity/src/helpers/action_option.dart';
import 'package:tenacity/src/helpers/student_names.dart';
import 'package:tenacity/src/models/attendance_model.dart';
import 'package:tenacity/src/models/class_model.dart';
import 'package:tenacity/src/models/parent_model.dart';
import 'package:tenacity/src/models/student_model.dart';

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  TimetableScreenState createState() => TimetableScreenState();
}

class TimetableScreenState extends State<TimetableScreen> {
  final List<String> _daysOfWeek = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  final List<String> _timeSlots = [
    '16:00', '16:30', '17:00', '17:30', '18:00', '18:30',
    '19:00', '19:30', '20:00', '20:30', '21:00', '21:30', '22:00'
  ];

  final List<int> _capacities = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

  // For parents, store the computed current week based on the term's start date.
  int? _parentComputedWeek;

  @override
  void initState() {
    super.initState();
    final timetableController =
        Provider.of<TimetableController>(context, listen: false);
    _initData(timetableController);
  }

  Future<void> _initData(TimetableController controller) async {
    await controller.loadActiveTerm(); // This now calculates current week from term.startDate.
    await controller.loadAllClasses();
    await controller.loadAttendanceForWeek();

    // If the current user is a parent, compute and store their "current" week.
    final authController = Provider.of<AuthController>(context, listen: false);
    final currentUser = authController.currentUser;
    if (currentUser != null && currentUser.role == 'parent' && controller.activeTerm != null) {
      final term = controller.activeTerm!;
      final now = DateTime.now();
      int computedWeek;
      if (now.isBefore(term.startDate)) {
        computedWeek = 1;
      } else {
        computedWeek = (now.difference(term.startDate).inDays ~/ 7) + 1;
        if (computedWeek > term.totalWeeks) {
          computedWeek = term.totalWeeks;
        }
      }
      setState(() {
        _parentComputedWeek = computedWeek;
      });
      controller.currentWeek = computedWeek;
    }
  }

  @override
  Widget build(BuildContext context) {
    final timetableController = context.watch<TimetableController>();
    final authController = context.watch<AuthController>();

    final userRole = authController.currentUser?.role ?? 'parent';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Timetable",
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1C71AF), Color(0xFF1B3F71)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: _buildBody(timetableController, authController),
      floatingActionButton: userRole == 'admin'
          ? FloatingActionButton(
              onPressed: () {
                _showAddClassDialog(context);
              },
              backgroundColor: const Color(0xFF1C71AF),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildBody(TimetableController timetableController, AuthController authController) {
    if (timetableController.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (timetableController.errorMessage != null) {
      return Center(child: Text(timetableController.errorMessage!));
    }
    if (timetableController.activeTerm == null) {
      return const Center(child: Text('No active term found.'));
    }
    final allClasses = timetableController.allClasses;
    if (allClasses.isEmpty) {
      return const Center(child: Text('No classes available.'));
    }
    return _buildTimetableContent(timetableController, authController);
  }

  Widget _buildTimetableContent(TimetableController timetableController, AuthController authController) {
    final currentWeek = timetableController.currentWeek;
    final activeTerm = timetableController.activeTerm!;
    final startOfCurrentWeek = activeTerm.startDate.add(Duration(days: (currentWeek - 1) * 7));
    final formattedStart = DateFormat('dd/MM').format(startOfCurrentWeek);

    final currentUser = authController.currentUser;
    final userRole = currentUser?.role ?? 'parent';
    List<String> userStudentIds = [];
    if (currentUser != null && currentUser.role == 'parent') {
      final parentUser = currentUser as Parent;
      userStudentIds = parentUser.students;
    }

    // For parents, allowed weeks are only parent's computed week and parent's computed week + 1.
    int allowedMinWeek, allowedMaxWeek;
    if (userRole == 'parent') {
      allowedMinWeek = _parentComputedWeek ?? currentWeek;
      allowedMaxWeek = (allowedMinWeek < activeTerm.totalWeeks) ? allowedMinWeek + 1 : allowedMinWeek;
    } else {
      allowedMinWeek = 1;
      allowedMaxWeek = activeTerm.totalWeeks;
    }

    // "Your Classes": classes where the attendance document contains one of the parent's children.
    final yourClasses = timetableController.allClasses.where((c) {
      final attendance = timetableController.attendanceByClass[c.id];
      if (attendance != null) {
        return attendance.attendance.any((id) => userStudentIds.contains(id));
      }
      return false;
    }).toList();

    // Organize all classes by day.
    final Map<String, List<ClassModel>> classesByDay = {};
    for (var c in timetableController.allClasses) {
      final day = c.dayOfWeek.isEmpty ? "Unknown" : c.dayOfWeek;
      classesByDay.putIfAbsent(day, () => []);
      classesByDay[day]!.add(c);
    }

    return Column(
      children: [
        // Week Selector with restricted navigation for parents.
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Back button is enabled only if currentWeek > parent's computed week.
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: (timetableController.currentWeek > allowedMinWeek)
                    ? () async {
                        timetableController.decrementWeek();
                        if (!mounted) return;
                        await timetableController.loadAttendanceForWeek();
                      }
                    : null,
              ),
              Text(
                'Week ${timetableController.currentWeek} ($formattedStart)',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              // Forward button is enabled only if currentWeek < allowedMaxWeek.
              IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: (timetableController.currentWeek < allowedMaxWeek)
                    ? () async {
                        timetableController.incrementWeek();
                        if (!mounted) return;
                        await timetableController.loadAttendanceForWeek();
                      }
                    : null,
              ),
            ],
          ),
        ),
        // Main Content
        Expanded(
          child: ListView(
            children: [
              // "Your Classes" Section – classes where parent's children appear in the attendance document.
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                child: Text(
                  'Your Classes',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              if (yourClasses.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'No classes with your attendance data for this week.',
                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                  ),
                )
              else
                ...yourClasses.map((classInfo) {
                  final attendance = timetableController.attendanceByClass[classInfo.id];
                  final currentlyEnrolled = attendance?.attendance.length ?? 0;
                  final spotsRemaining = classInfo.capacity - currentlyEnrolled;
                  // For parent's own classes, only consider children in the attendance doc.
                  final relevantChildIds = (attendance?.attendance ?? [])
                      .where((id) => userStudentIds.contains(id))
                      .toList();
                  return _buildClassCard(
                    classInfo: classInfo,
                    spotsRemaining: spotsRemaining,
                    barColor: const Color(0xFF1C71AF),
                    onTap: () {
                      _showClassOptionsDialog(
                        classInfo,
                        true, // isOwnClass
                        attendance,
                        userStudentIds,
                        relevantChildIds: relevantChildIds,
                      );
                    },
                    // For parents, display a “Your child(ren)” line.
                    showStudentNames: (userRole == 'admin' || userRole == 'tutor'),
                    studentIdsToShow: attendance?.attendance ?? [],
                    relevantChildIds: relevantChildIds,
                  );
                }),
              // "All Classes" Section (for classes not in the parent's attendance).
              if (classesByDay.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  child: Text(
                    'All Classes',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                ...classesByDay.entries.map((entry) {
                  final day = entry.key;
                  final dayClasses = entry.value;
                  dayClasses.sort((a, b) => a.startTime.compareTo(b.startTime));
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          day,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...dayClasses.map((classInfo) {
                        final attendance = timetableController.attendanceByClass[classInfo.id];
                        final currentlyEnrolled = attendance?.attendance.length ?? 0;
                        final spotsRemaining = classInfo.capacity - currentlyEnrolled;
                        final bool isOwnClass = classInfo.enrolledStudents.any((id) => userStudentIds.contains(id));
                        final relevantChildIds = isOwnClass
                            ? (attendance?.attendance.where((id) => userStudentIds.contains(id)).toList() ?? [])
                            : userStudentIds;
                        return _buildClassCard(
                          classInfo: classInfo,
                          spotsRemaining: spotsRemaining,
                          barColor: isOwnClass
                              ? const Color(0xFF1C71AF)
                              : (spotsRemaining > 2
                                  ? const Color.fromARGB(255, 50, 151, 53)
                                  : (spotsRemaining == 2 || spotsRemaining == 1
                                      ? Colors.amber
                                      : const Color.fromARGB(255, 244, 51, 37))),
                          onTap: () {
                            _showClassOptionsDialog(
                              classInfo,
                              isOwnClass,
                              attendance,
                              userStudentIds,
                              relevantChildIds: isOwnClass ? relevantChildIds : userStudentIds,
                            );
                          },
                          showStudentNames: (userRole == 'admin' || userRole == 'tutor'),
                          studentIdsToShow: attendance?.attendance ?? [],
                          relevantChildIds: isOwnClass ? relevantChildIds : null,
                        );
                      }),
                    ],
                  );
                }),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // Build a card for a class.
  Widget _buildClassCard({
    required ClassModel classInfo,
    required int spotsRemaining,
    required Color barColor,
    required VoidCallback onTap,
    required bool showStudentNames,
    List<String>? studentIdsToShow,
    List<String>? relevantChildIds,
  }) {
    final formattedStartTime = DateFormat("h:mm a")
        .format(DateFormat("HH:mm").parse(classInfo.startTime));
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 8,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20.0, 16.0, 16.0, 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${classInfo.dayOfWeek} $formattedStartTime',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Available Spots: $spotsRemaining',
                      style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                    ),
                    if (showStudentNames) ...[
                      const SizedBox(height: 8),
                      studentIdsToShow != null && studentIdsToShow.isNotEmpty
                          ? StudentNamesWidget(studentIds: studentIdsToShow)
                          : Text(
                              'Students: [No attendance data]',
                              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                            ),
                    ],
                    if (relevantChildIds != null && relevantChildIds.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: _buildYourChildList(relevantChildIds),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // This widget fetches and displays the names of the parent's children in this class.
  Widget _buildYourChildList(List<String> childIds) {
    final authController = Provider.of<AuthController>(context, listen: false);
    return FutureBuilder<List<String>>(
      future: Future.wait(childIds.map((id) async {
        final Student? student = await authController.fetchStudentData(id);
        return student?.firstName ?? "Unknown";
      })),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Text("Loading your child(ren)...", style: TextStyle(fontSize: 16, color: Colors.grey));
        }
        if (snapshot.hasError) {
          return const Text("Error loading child data", style: TextStyle(fontSize: 16, color: Colors.grey));
        }
        final names = snapshot.data ?? [];
        if (names.isEmpty) return const SizedBox();
        return Text(
          names.join(', '),
          style: const TextStyle(fontSize: 16, color: Colors.black),
        );
      },
    );
  }

  // When a class card is tapped, show an options bottom sheet.
  void _showClassOptionsDialog(
    ClassModel classInfo,
    bool isOwnClass,
    Attendance? attendance,
    List<String> userStudentIds, {
    List<String>? relevantChildIds,
  }) {
    final timetableController = Provider.of<TimetableController>(context, listen: false);
    final attendanceDocId = '${timetableController.activeTerm!.id}_W${timetableController.currentWeek}';

    // Rename for clarity.
    final bool isOneOffBooking = attendance != null &&
        attendance.attendance.any((id) => userStudentIds.contains(id)) &&
        !classInfo.enrolledStudents.any((id) => userStudentIds.contains(id));

    List<ActionOption> options;
    if (isOwnClass) {
      if (isOneOffBooking) {
        options = [
          ActionOption("Swap (This Week)"), 
          ActionOption("Cancel this class")
        ];
      } else {
        // For permanent enrollments, show two distinct swap options.
        options = [
          ActionOption("Notify of absence"),
          ActionOption("Swap (This Week)"), // one‑week only swap
          ActionOption("Swap (Permanent)"), // update permanent enrolment
          ActionOption("Unenrol")
        ];
      }
    } else {
      options = [
        ActionOption("Book one-off class"),
        ActionOption("Enrol permanent"),
        ActionOption("Swap for one of my classes")
      ];
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: Text(
                  'Select an Action',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1, thickness: 1),
              ...options.map((option) {
                return ListTile(
                  title: Text(option.title),
                  onTap: () {
                    Navigator.pop(context); // close bottom sheet

                    // For swap actions, chain to child selection then class selection.
                    if (isOwnClass &&
                        (option.title == "Swap (This Week)" ||
                            option.title == "Swap (Permanent)")) {
                      _showChildSelectionDialog(
                        option.title,
                        classInfo,
                        attendanceDocId,
                        isOwnClass ? (relevantChildIds ?? []) : userStudentIds,
                      );
                    } else {
                      // For other actions, follow the existing flow.
                      if (isOwnClass &&
                          (relevantChildIds?.length ?? 0) == 1 &&
                          (option.title == "Enrol permanent" ||
                              option.title == "Book one-off class")) {
                        _showActionConfirmationDialog(
                          option.title,
                          relevantChildIds!,
                          classInfo,
                          attendanceDocId,
                        );
                      } else {
                        _showChildSelectionDialog(
                          option.title,
                          classInfo,
                          attendanceDocId,
                          isOwnClass ? (relevantChildIds ?? []) : userStudentIds,
                        );
                      }
                    }
                  },
                );
              }),
              const Divider(height: 1, thickness: 1),
              ListTile(
                title: const Text('Back', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showChildSelectionDialog(
    String action,
    ClassModel classInfo,
    String attendanceDocId,
    List<String> availableChildIds,
  ) {
    List<String> selectedChildIds = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
                    child: Text(
                      "Select Students for '$action'",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Divider(height: 1, thickness: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: availableChildIds.map((childId) {
                          final isSelected = selectedChildIds.contains(childId);
                          return _buildChildCheckboxTile(
                            childId,
                            isSelected,
                            (bool? value) {
                              setState(() {
                                if (value ?? false) {
                                  selectedChildIds.add(childId);
                                } else {
                                  selectedChildIds.remove(childId);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const Divider(height: 1, thickness: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Cancel"),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColorDark,
                          ),
                          onPressed: selectedChildIds.isEmpty
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  // If this is a swap action, show the class selection dialog.
                                  if (action == "Swap (This Week)" || action == "Swap (Permanent)") {
                                    _showNewClassSelectionDialog(
                                      action,
                                      classInfo,
                                      attendanceDocId,
                                      selectedChildIds,
                                    );
                                  } else {
                                    // For other actions, show the standard confirmation.
                                    _showActionConfirmationDialog(
                                      action,
                                      selectedChildIds,
                                      classInfo,
                                      attendanceDocId,
                                    );
                                  }
                                },
                          child: const Text("Confirm", style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showNewClassSelectionDialog(
    String action,
    ClassModel oldClass,
    String attendanceDocId,
    List<String> selectedChildIds,
  ) {
    final timetableController = Provider.of<TimetableController>(context, listen: false);
    // Filter out the current class and classes that are full.
    final availableClasses = timetableController.allClasses.where((c) {
      if (c.id == oldClass.id) return false;
      final attendance = timetableController.attendanceByClass[c.id];
      final enrolledCount = attendance?.attendance.length ?? 0;
      return enrolledCount < c.capacity;
    }).toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Select a New Class",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: availableClasses.length,
                  itemBuilder: (context, index) {
                    final newClass = availableClasses[index];
                    final formattedTime = DateFormat("h:mm a").format(
                      DateFormat("HH:mm").parse(newClass.startTime),
                    );
                    return ListTile(
                      title: Text("${newClass.dayOfWeek} $formattedTime"),
                      subtitle: Text("Capacity: ${newClass.capacity}"),
                      onTap: () {
                        Navigator.pop(context);
                        // Instead of performing the swap immediately,
                        // show the confirmation dialog.
                        _showSwapConfirmationDialog(
                          action,
                          oldClass,
                          newClass,
                          attendanceDocId,
                          selectedChildIds,
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<List<String>> _fetchChildNames(List<String> childIds, BuildContext context) async {
    final authController = Provider.of<AuthController>(context, listen: false);
    final List<Student?> students = await Future.wait(childIds.map((id) => authController.fetchStudentData(id)));
    return students.map((student) => student?.firstName ?? "Unknown").toList();
  }

  // This dialog confirms the parent's selection before making the backend call.
  void _showActionConfirmationDialog(
    String action,
    List<String> selectedChildIds,
    ClassModel classInfo,
    String attendanceDocId,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) {
        return SafeArea(
          child: FutureBuilder<List<String>>(
            future: _fetchChildNames(selectedChildIds, context),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text("Error loading child names: ${snapshot.error}"),
                );
              }
              final childNames = snapshot.data ?? [];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(
                      "Confirm '$action'",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Divider(height: 1, thickness: 1),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      "Are you sure you want to confirm '$action' for ${childNames.join(', ')}?",
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const Divider(height: 1, thickness: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Cancel"),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColorDark,
                          ),
                          onPressed: () async {
                            // BOOK ONE-OFF CLASS FUNCTIONALITY
                            if (action == "Book one-off class") {
                              // Check available spots.
                              final currentAtt = Provider.of<TimetableController>(context, listen: false)
                                  .attendanceByClass[classInfo.id];
                              final currentCount = currentAtt?.attendance.length ?? 0;
                              final availableSpots = classInfo.capacity - currentCount;
                              if (selectedChildIds.length > availableSpots) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Not enough available spots.")),
                                );
                                return;
                              }
                              final timetableController = Provider.of<TimetableController>(context, listen: false);
                              for (var childId in selectedChildIds) {
                                await timetableController.enrollStudentOneOff(
                                  classId: classInfo.id,
                                  studentId: childId,
                                  attendanceDocId: attendanceDocId,
                                );
                              }
                            }
                            // (Other actions like Enrol permanent would be handled similarly.)
                            await Provider.of<TimetableController>(context, listen: false).loadAttendanceForWeek();
                            if (!mounted) return;
                            Navigator.pop(context);
                          },
                          child: const Text("Confirm", style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildChildCheckboxTile(String childId, bool isSelected, Function(bool?) onChanged) {
    final authController = Provider.of<AuthController>(context, listen: false);
    return FutureBuilder<Student?>(
      future: authController.fetchStudentData(childId),
      builder: (context, snapshot) {
        String childName = "Loading...";
        if (snapshot.hasData) {
          final Student? student = snapshot.data;
          childName = student?.firstName ?? "Unknown";
        } else if (snapshot.hasError) {
          childName = "Unknown";
        }
        return CheckboxListTile(
          title: Text(childName),
          value: isSelected,
          onChanged: onChanged,
        );
      },
    );
  }

  void _showSwapConfirmationDialog(
    String action,
    ClassModel oldClass,
    ClassModel newClass,
    String attendanceDocId,
    List<String> selectedChildIds,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) {
        return SafeArea(
          child: FutureBuilder<List<String>>(
            future: _fetchChildNames(selectedChildIds, context),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text("Error loading child names: ${snapshot.error}"),
                );
              }
              final childNames = snapshot.data ?? [];
              final oldTime = DateFormat("h:mm a")
                  .format(DateFormat("HH:mm").parse(oldClass.startTime));
              final newTime = DateFormat("h:mm a")
                  .format(DateFormat("HH:mm").parse(newClass.startTime));
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(
                      "Confirm '$action'",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Divider(height: 1, thickness: 1),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      "Swap from ${oldClass.dayOfWeek} at $oldTime to ${newClass.dayOfWeek} at $newTime for ${childNames.join(', ')}?",
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const Divider(height: 1, thickness: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Cancel"),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColorDark,
                          ),
                          onPressed: () async {
                            Navigator.pop(context);
                            final timetableController = Provider.of<TimetableController>(context, listen: false);
                            if (action == "Swap (This Week)") {
                              // One‑week swap: update the attendance doc only.
                              for (var childId in selectedChildIds) {
                                await timetableController.rescheduleToDifferentClass(
                                  oldClassId: oldClass.id,
                                  oldAttendanceDocId: attendanceDocId,
                                  newClassId: newClass.id,
                                  newAttendanceDocId: attendanceDocId,
                                  studentId: childId,
                                );
                              }
                            } else if (action == "Swap (Permanent)") {
                              // Permanent swap: update the permanent enrolment.
                              for (var childId in selectedChildIds) {
                                await timetableController.swapPermanentEnrollment(
                                  oldClassId: oldClass.id,
                                  newClassId: newClass.id,
                                  studentId: childId,
                                );
                              }
                            }
                            await timetableController.loadAttendanceForWeek();
                          },
                          child: const Text("Confirm", style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showAddClassDialog(BuildContext context) {
    String classType = '';
    String selectedDay = _daysOfWeek.first;
    String selectedStartTime = _timeSlots.first;
    String selectedEndTime = _timeSlots.first;
    int selectedCapacity = _capacities.first;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add New Class'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(labelText: 'Class Type'),
                  onChanged: (val) => classType = val,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Day of Week'),
                  value: selectedDay,
                  items: _daysOfWeek.map((day) {
                    return DropdownMenuItem<String>(
                      value: day,
                      child: Text(day),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        selectedDay = val;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Start Time'),
                  value: selectedStartTime,
                  items: _timeSlots.map((time) {
                    final formattedTime = DateFormat("h:mm a").format(DateFormat("HH:mm").parse(time));
                    return DropdownMenuItem<String>(
                      value: time,
                      child: Text(formattedTime),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        selectedStartTime = val;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'End Time'),
                  value: selectedEndTime,
                  items: _timeSlots.map((time) {
                    final formattedTime = DateFormat("h:mm a").format(DateFormat("HH:mm").parse(time));
                    return DropdownMenuItem<String>(
                      value: time,
                      child: Text(formattedTime),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        selectedEndTime = val;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'Capacity'),
                  value: selectedCapacity,
                  items: _capacities.map((cap) {
                    return DropdownMenuItem<int>(
                      value: cap,
                      child: Text(cap.toString()),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        selectedCapacity = val;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final newClass = ClassModel(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  type: classType.trim(),
                  dayOfWeek: selectedDay,
                  startTime: selectedStartTime,
                  endTime: selectedEndTime,
                  capacity: selectedCapacity,
                  enrolledStudents: const [],
                );
                final timetableController = Provider.of<TimetableController>(context, listen: false);
                await timetableController.createNewClass(newClass);
                Navigator.pop(ctx);
              },
              child: const Text('Add Class'),
            ),
          ],
        );
      },
    );
  }
}