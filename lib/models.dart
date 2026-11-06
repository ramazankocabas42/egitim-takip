import 'package:cloud_firestore/cloud_firestore.dart';

// ---------------------------------------------------------------------------
// Yardımcı dönüştürücüler
// ---------------------------------------------------------------------------
DateTime? _ts(dynamic v) => v is Timestamp ? v.toDate() : null;
int _int(dynamic v) => v is num ? v.toInt() : 0;
String _str(dynamic v) => v == null ? '' : v.toString();
List<String> _strList(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : <String>[];

// ---------------------------------------------------------------------------
// Roller
// ---------------------------------------------------------------------------
enum UserRole { parent, student, teacher }

extension UserRoleX on UserRole {
  String get label {
    switch (this) {
      case UserRole.parent:
        return 'Veli';
      case UserRole.student:
        return 'Öğrenci';
      case UserRole.teacher:
        return 'Öğretmen';
    }
  }

  /// Veli ve öğretmen "yetişkin" rolüdür: ödev kontrol edebilir, silebilir.
  bool get isAdult => this != UserRole.student;
}

UserRole roleFromString(String? s) => UserRole.values
    .firstWhere((r) => r.name == s, orElse: () => UserRole.parent);

// ---------------------------------------------------------------------------
// Kullanıcı
// ---------------------------------------------------------------------------
class AppUser {
  AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
  });

  final String uid;
  final String name;
  final String email;
  final UserRole role;

  String get displayName => '$name (${role.label})';

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return AppUser(
      uid: d.id,
      name: _str(m['name']),
      email: _str(m['email']),
      role: roleFromString(m['role'] as String?),
    );
  }
}

// ---------------------------------------------------------------------------
// Öğrenci
// ---------------------------------------------------------------------------
class Student {
  Student({
    required this.id,
    required this.name,
    required this.grade,
    required this.inviteCode,
    required this.parentIds,
    required this.teacherIds,
    required this.studentUid,
  });

  final String id;
  final String name;
  final String grade;
  final String inviteCode;
  final List<String> parentIds;
  final List<String> teacherIds;
  final String? studentUid;

  bool isParent(String uid) => parentIds.contains(uid);
  bool isTeacher(String uid) => teacherIds.contains(uid);

  factory Student.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return Student(
      id: d.id,
      name: _str(m['name']),
      grade: _str(m['grade']),
      inviteCode: _str(m['inviteCode']),
      parentIds: _strList(m['parentIds']),
      teacherIds: _strList(m['teacherIds']),
      studentUid: m['studentUid'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Ödev
// ---------------------------------------------------------------------------
class Homework {
  Homework({
    required this.id,
    required this.title,
    required this.subject,
    required this.description,
    required this.dueDate,
    required this.done,
    required this.doneAt,
    required this.doneBy,
    required this.checked,
    required this.checkedBy,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String subject;
  final String description;
  final DateTime? dueDate;
  final bool done;
  final DateTime? doneAt;
  final String doneBy;
  final bool checked;
  final String checkedBy;
  final String createdBy;
  final String createdByName;
  final DateTime? createdAt;

  factory Homework.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return Homework(
      id: d.id,
      title: _str(m['title']),
      subject: _str(m['subject']),
      description: _str(m['description']),
      dueDate: _ts(m['dueDate']),
      done: m['done'] == true,
      doneAt: _ts(m['doneAt']),
      doneBy: _str(m['doneBy']),
      checked: m['checked'] == true,
      checkedBy: _str(m['checkedBy']),
      createdBy: _str(m['createdBy']),
      createdByName: _str(m['createdByName']),
      createdAt: _ts(m['createdAt']),
    );
  }
}

// ---------------------------------------------------------------------------
// Kitap ve okuma kaydı
// ---------------------------------------------------------------------------
class Book {
  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.totalPages,
    required this.currentPage,
    required this.finished,
    required this.createdBy,
    this.durum = '',
  });

  final String id;
  final String durum;

  /// 'istek' (almayı düşündüklerim), 'devam' ya da 'bitti'
  String get durumu => durum.isNotEmpty ? durum : (finished ? 'bitti' : 'devam');
  final String title;
  final String author;
  final int totalPages;
  final int currentPage;
  final bool finished;
  final String createdBy;

  double get progress =>
      totalPages > 0 ? (currentPage / totalPages).clamp(0, 1).toDouble() : 0;

  factory Book.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return Book(
      id: d.id,
      title: _str(m['title']),
      author: _str(m['author']),
      totalPages: _int(m['totalPages']),
      currentPage: _int(m['currentPage']),
      finished: m['finished'] == true,
      createdBy: _str(m['createdBy']),
      durum: _str(m['durum']),
    );
  }
}

class ReadingLog {
  ReadingLog({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.fromPage,
    required this.toPage,
    required this.pages,
    required this.minutes,
    required this.date,
    required this.createdByName,
  });

  final String id;
  final String bookId;
  final String bookTitle;
  final int fromPage;
  final int toPage;
  final int pages;
  final int minutes;
  final DateTime? date;
  final String createdByName;

  factory ReadingLog.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return ReadingLog(
      id: d.id,
      bookId: _str(m['bookId']),
      bookTitle: _str(m['bookTitle']),
      fromPage: _int(m['fromPage']),
      toPage: _int(m['toPage']),
      pages: _int(m['pages']),
      minutes: _int(m['minutes']),
      date: _ts(m['date']),
      createdByName: _str(m['createdByName']),
    );
  }
}

// ---------------------------------------------------------------------------
// Test kitabı
// ---------------------------------------------------------------------------
class Topic {
  const Topic({required this.name, this.start = 0, this.end = 0});

  final String name;
  final int start; // konunun başladığı sayfa (0 = belirtilmedi)
  final int end; // konunun bittiği sayfa

  bool get hasRange => start > 0 && end >= start;
  int get pageCount => hasRange ? end - start + 1 : 0;
  List<int> get pages =>
      hasRange ? List.generate(pageCount, (i) => start + i) : const <int>[];

  Map<String, dynamic> toMap() => {'name': name, 'start': start, 'end': end};

  factory Topic.fromMap(Map<dynamic, dynamic> m) => Topic(
        name: _str(m['name']),
        start: _int(m['start']),
        end: _int(m['end']),
      );
}

class TestBook {
  TestBook({
    required this.id,
    required this.title,
    required this.publisher,
    required this.subject,
    required this.totalPages,
    required this.topics,
    required this.solvedPages,
    required this.completedTopics,
    required this.createdBy,
    this.isbn = '',
    this.durum = '',
  });

  final String id;
  final String isbn;
  final String durum;

  /// 'istek' (almayı düşündüklerim), 'devam' ya da 'bitti'
  String get durumu => durum.isNotEmpty ? durum : (progress >= 1 ? 'bitti' : 'devam');
  final String title;
  final String publisher;
  final String subject;
  final int totalPages;
  final List<Topic> topics;
  final Set<int> solvedPages;
  final Set<String> completedTopics;
  final String createdBy;

  int solvedInTopic(Topic t) => t.hasRange
      ? solvedPages.where((p) => p >= t.start && p <= t.end).length
      : 0;

  /// Konu, elle "bitti" işaretlendiyse ya da tüm sayfaları çözüldüyse tamamdır.
  bool isTopicDone(Topic t) =>
      completedTopics.contains(t.name) ||
      (t.hasRange && solvedInTopic(t) == t.pageCount);

  int get doneTopicCount => topics.where(isTopicDone).length;

  double get progress => totalPages > 0
      ? (solvedPages.length / totalPages).clamp(0, 1).toDouble()
      : (topics.isEmpty ? 0.0 : doneTopicCount / topics.length);

  factory TestBook.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    final rawTopics = m['topics'];
    final rawPages = m['solvedPages'];
    return TestBook(
      id: d.id,
      title: _str(m['title']),
      publisher: _str(m['publisher']),
      subject: _str(m['subject']),
      totalPages: _int(m['totalPages']),
      topics: rawTopics is List
          ? rawTopics.whereType<Map>().map(Topic.fromMap).toList()
          : <Topic>[],
      solvedPages: rawPages is List
          ? rawPages.whereType<num>().map((e) => e.toInt()).toSet()
          : <int>{},
      completedTopics: _strList(m['completedTopics']).toSet(),
      createdBy: _str(m['createdBy']),
      isbn: _str(m['isbn']),
      durum: _str(m['durum']),
    );
  }
}

// ---------------------------------------------------------------------------
// Test / deneme sonucu
// ---------------------------------------------------------------------------
class TestResult {
  TestResult({
    required this.id,
    required this.name,
    required this.subject,
    required this.correct,
    required this.wrong,
    required this.blank,
    required this.penalty,
    required this.date,
    required this.createdBy,
  });

  final String id;
  final String name;
  final String subject;
  final int correct;
  final int wrong;
  final int blank;

  /// Kaç yanlış bir doğruyu götürür (0 = götürmez, 3 = LGS, 4 = YKS).
  final int penalty;
  final DateTime? date;
  final String createdBy;

  int get total => correct + wrong + blank;
  double get net => penalty > 0 ? correct - wrong / penalty : correct.toDouble();

  factory TestResult.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return TestResult(
      id: d.id,
      name: _str(m['name']),
      subject: _str(m['subject']),
      correct: _int(m['correct']),
      wrong: _int(m['wrong']),
      blank: _int(m['blank']),
      penalty: _int(m['penalty']),
      date: _ts(m['date']),
      createdBy: _str(m['createdBy']),
    );
  }
}

/// Kitaplık durumları.
const kitapDurumlari = <String, String>{
  'istek': 'Almayı düşündüklerim',
  'devam': 'Devam edenler',
  'bitti': 'Tamamlananlar',
};
