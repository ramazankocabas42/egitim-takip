import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models.dart';

/// Tüm Firestore okuma/yazma işlemleri burada toplanır.
///
/// Veri yapısı:
///   users/{uid}                         -> ad, e-posta, rol
///   invites/{KOD}                       -> davet kodu -> öğrenci eşlemesi
///   students/{sid}                      -> öğrenci kartı (veliler, öğretmenler, öğrenci hesabı)
///   students/{sid}/homeworks/{id}       -> ödevler
///   students/{sid}/books/{id}           -> okunan kitaplar
///   students/{sid}/readingLogs/{id}     -> okuma kayıtları
///   students/{sid}/testBooks/{id}       -> test kitapları (konular + çözülen sayfalar)
///   students/{sid}/testResults/{id}     -> test / deneme sonuçları
class Db {
  Db._();

  static final FirebaseFirestore _fs = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _users =>
      _fs.collection('users');
  static CollectionReference<Map<String, dynamic>> get _students =>
      _fs.collection('students');
  static CollectionReference<Map<String, dynamic>> get _invites =>
      _fs.collection('invites');
  static CollectionReference<Map<String, dynamic>> _sub(
          String sid, String name) =>
      _students.doc(sid).collection(name);

  static Timestamp _now() => Timestamp.now();

  static const subCollections = [
    'homeworks',
    'books',
    'readingLogs',
    'testBooks',
    'testResults',
    'soruGirisleri',
    'lgsDenemeleri',
    'haftalikPlan',
    'ayarlar',
    'okulSinavlari',
    'yilSonuNotlari',
    'programEtkinlikleri',
    'osymSinavlari',
  ];

  // -------------------------------------------------------------------------
  // Kullanıcılar
  // -------------------------------------------------------------------------
  static Stream<AppUser?> userStream(String uid) => _users
      .doc(uid)
      .snapshots()
      .map((d) => d.exists ? AppUser.fromDoc(d) : null);

  static Future<void> createProfile({
    required String uid,
    required String name,
    required String email,
    required UserRole role,
  }) =>
      _users.doc(uid).set({
        'name': name,
        'email': email,
        'role': role.name,
        'createdAt': _now(),
      });

  /// Hesap türünü (rolü) ve adı değiştirir.
  static Future<void> updateRole(String uid, UserRole role) =>
      _users.doc(uid).update({'role': role.name, 'updatedAt': _now()});

  static Future<List<AppUser>> getUsers(Iterable<String> uids) async {
    final out = <AppUser>[];
    for (final id in uids.toSet()) {
      final d = await _users.doc(id).get();
      if (d.exists) out.add(AppUser.fromDoc(d));
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Öğrenciler
  // -------------------------------------------------------------------------
  static Stream<List<Student>> myStudents(AppUser me) {
    final Query<Map<String, dynamic>> q = switch (me.role) {
      UserRole.parent => _students.where('parentIds', arrayContains: me.uid),
      UserRole.teacher => _students.where('teacherIds', arrayContains: me.uid),
      UserRole.student => _students.where('studentUid', isEqualTo: me.uid),
    };
    List<Student> liste(QuerySnapshot<Map<String, dynamic>> s) =>
        s.docs.map(Student.fromDoc).toList();
    if (me.role != UserRole.teacher) {
      return q.snapshots().map((s) => liste(s)..sort((a, b) => a.name.compareTo(b.name)));
    }
    // Öğretmen: öğrencileri + kendi (bireysel) profili
    final kendi = _students.where('studentUid', isEqualTo: me.uid);
    late StreamController<List<Student>> c;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? a, b;
    var la = <Student>[], lb = <Student>[];
    void yay() {
      final m = <String, Student>{for (final s in [...lb, ...la]) s.id: s};
      c.add(m.values.toList()..sort((x, y) => x.name.compareTo(y.name)));
    }

    c = StreamController<List<Student>>(
      onListen: () {
        a = q.snapshots().listen((s) {
          la = liste(s);
          yay();
        }, onError: c.addError);
        b = kendi.snapshots().listen((s) {
          lb = liste(s);
          yay();
        }, onError: c.addError);
      },
      onCancel: () async {
        await a?.cancel();
        await b?.cancel();
      },
    );
    return c.stream;
  }

  static Stream<Student?> studentStream(String sid) => _students
      .doc(sid)
      .snapshots()
      .map((d) => d.exists ? Student.fromDoc(d) : null);

  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String _randomCode() {
    final r = Random.secure();
    return List.generate(6, (_) => _alphabet[r.nextInt(_alphabet.length)])
        .join();
  }

  static Future<String> _freeCode() async {
    for (var i = 0; i < 10; i++) {
      final code = _randomCode();
      final d = await _invites.doc(code).get();
      if (!d.exists) return code;
    }
    throw Exception('Davet kodu üretilemedi, lütfen tekrar deneyin.');
  }

  static Future<void> addStudent(
    AppUser me, {
    required String name,
    required String grade,
  }) async {
    final code = await _freeCode();
    final ref = _students.doc();
    await ref.set({
      'name': name,
      'grade': grade,
      'parentIds': [me.uid],
      'teacherIds': <String>[],
      'studentUid': null,
      'inviteCode': code,
      'createdBy': me.uid,
      'createdAt': _now(),
    });
    await _invites.doc(code).set({
      'studentId': ref.id,
      'kind': 'member',
      'createdBy': me.uid,
      'createdAt': _now(),
    });
    await _newParentCode(me, ref.id);
  }

  /// Öğrencinin kendi başına açtığı profil (YKS / KPSS / AGS hazırlığı).
  /// Öğrenci hem profilin sahibi hem de öğrencisidir; isterse davet koduyla
  /// koçunu, öğretmenini ya da velisini ekleyebilir.
  static Future<void> createOwnProfile(
    AppUser me, {
    required String name,
    required String grade,
    Map<String, Object?> ayarlar = const {},
  }) async {
    final code = await _freeCode();
    final ref = _students.doc();
    await ref.set({
      ...ayarlar,
      'name': name,
      'grade': grade,
      'parentIds': [me.uid],
      'teacherIds': <String>[],
      'studentUid': me.uid,
      'inviteCode': code,
      'bireysel': true,
      'createdBy': me.uid,
      'createdAt': _now(),
    });
    await _invites.doc(code).set({
      'studentId': ref.id,
      'kind': 'member',
      'createdBy': me.uid,
      'createdAt': _now(),
    });
    await _newParentCode(me, ref.id);
  }

  /// Hedef sınav, alan, doğum yılı, dersler, gizli sekmeler.
  static Future<void> updateStudentAyarlar(String sid, Map<String, Object?> ayarlar) =>
      _students.doc(sid).update(ayarlar);

  static Future<void> updateStudent(String sid,
          {required String name, required String grade}) =>
      _students.doc(sid).update({'name': name, 'grade': grade});

  /// Öğretmen / öğrenci davet kodunu yeniler. Eski kod artık çalışmaz.
  static Future<void> regenerateCode(AppUser me, Student s) async {
    final code = await _freeCode();
    await _invites.doc(code).set({
      'studentId': s.id,
      'kind': 'member',
      'createdBy': me.uid,
      'createdAt': _now(),
    });
    await _students.doc(s.id).update({'inviteCode': code});
    try {
      await _invites.doc(s.inviteCode).delete();
    } catch (_) {
      // Eski kod zaten silinmiş olabilir.
    }
  }

  // ---- Veli kodu: yalnızca velilerin görebildiği, tek kullanımlık kod ----
  static DocumentReference<Map<String, dynamic>> _codesDoc(String sid) =>
      _sub(sid, 'private').doc('codes');

  /// Yalnızca veliler okuyabilir (Firestore kuralı).
  static Stream<String?> parentCodeStream(String sid) => _codesDoc(sid)
      .snapshots()
      .map((d) => d.data()?['parentCode'] as String?);

  /// Yeni veli kodu üretir, eskisini iptal eder.
  static Future<void> _newParentCode(AppUser me, String sid,
      {String? oldCode}) async {
    final code = await _freeCode();
    await _invites.doc(code).set({
      'studentId': sid,
      'kind': 'parent',
      'createdBy': me.uid,
      'createdAt': _now(),
    });
    await _codesDoc(sid).set({'parentCode': code});
    if (oldCode != null) {
      try {
        await _invites.doc(oldCode).delete();
      } catch (_) {}
    }
  }

  static Future<void> regenerateParentCode(AppUser me, String sid) async {
    final old = await _codesDoc(sid).get();
    await _newParentCode(me, sid,
        oldCode: old.data()?['parentCode'] as String?);
  }

  /// Velinin paylaştığı kodla öğretmen / ikinci veli / öğrenci hesabı bağlanır.
  static Future<String> joinWithCode(AppUser me, String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty) throw Exception('Lütfen davet kodunu yazın.');
    final inv = await _invites.doc(code).get();
    if (!inv.exists) throw Exception('Bu davet kodu bulunamadı.');
    final sid = inv.data()!['studentId'] as String;

    final Map<String, Object?> data = switch (me.role) {
      UserRole.teacher => {
          'teacherIds': FieldValue.arrayUnion([me.uid]),
          'joinCode': code,
        },
      UserRole.parent => {
          'parentIds': FieldValue.arrayUnion([me.uid]),
          'joinCode': code,
        },
      UserRole.student => {
          'studentUid': me.uid,
          'joinCode': code,
        },
    };

    final kind = inv.data()!['kind'] as String? ?? 'member';
    if (me.role == UserRole.parent && kind != 'parent') {
      throw Exception('Bu kod öğretmen/öğrenci kodu. Veli olarak katılmak için '
          'diğer velinin "Veli kodu"nu kullanın.');
    }
    if (me.role != UserRole.parent && kind == 'parent') {
      throw Exception('Bu bir veli kodu. Öğretmen ve öğrenciler için '
          'velinin paylaştığı "Davet kodu"nu kullanın.');
    }

    try {
      await _students.doc(sid).update(data);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw Exception(me.role == UserRole.student
            ? 'Bu öğrenci zaten başka bir öğrenci hesabına bağlı.'
            : 'Katılım reddedildi. Kodun güncel olduğundan emin olun.');
      }
      rethrow;
    }

    // Veli kodu tek kullanımlıktır: katılan veli kodu iptal edip yenisini üretir
    // ve öğrenci kartındaki joinCode alanını temizler.
    if (me.role == UserRole.parent) {
      try {
        await _students.doc(sid).update({'joinCode': FieldValue.delete()});
        await _newParentCode(me, sid, oldCode: code);
      } catch (_) {}
    }
    return sid;
  }

  static Future<void> removeTeacher(String sid, String uid) =>
      _students.doc(sid).update({
        'teacherIds': FieldValue.arrayRemove([uid])
      });

  static Future<void> removeParent(String sid, String uid) =>
      _students.doc(sid).update({
        'parentIds': FieldValue.arrayRemove([uid])
      });

  static Future<void> unlinkStudentAccount(String sid) =>
      _students.doc(sid).update({'studentUid': null});

  /// Öğretmenin kendi isteğiyle öğrenciden ayrılması.
  static Future<void> leaveAsTeacher(String sid, String uid) =>
      removeTeacher(sid, uid);

  /// Öğrenciyi ve tüm kayıtlarını siler (yalnızca veli).
  static Future<void> deleteStudent(Student s) async {
    try {
      final codes = await _codesDoc(s.id).get();
      final pc = codes.data()?['parentCode'] as String?;
      if (pc != null) await _invites.doc(pc).delete();
    } catch (_) {}
    for (final name in [...subCollections, 'private']) {
      final docs = await _sub(s.id, name).get();
      for (final d in docs.docs) {
        await d.reference.delete();
      }
    }
    await _students.doc(s.id).delete();
    try {
      await _invites.doc(s.inviteCode).delete();
    } catch (_) {}
  }

  static Future<void> deleteDoc(String sid, String collection, String id) =>
      _sub(sid, collection).doc(id).delete();

  // -------------------------------------------------------------------------
  // Ödevler
  // -------------------------------------------------------------------------
  static Stream<List<Homework>> homeworks(String sid) => _sub(sid, 'homeworks')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Homework.fromDoc).toList());

  static Stream<int> pendingHomeworkCount(String sid) => _sub(sid, 'homeworks')
      .where('done', isEqualTo: false)
      .snapshots()
      .map((s) => s.size);

  static Future<void> addHomework(
    String sid,
    AppUser me, {
    required String title,
    required String subject,
    required String description,
    DateTime? dueDate,
    List<OdevKitabi> kitaplar = const [],
    String sayfa = '',
  }) =>
      _sub(sid, 'homeworks').add({
        'title': title,
        'subject': subject,
        'description': description,
        if (kitaplar.isNotEmpty) 'kitaplar': kitaplar.map((k) => k.toMap()).toList(),
        if (sayfa.isNotEmpty) 'sayfa': sayfa,
        'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate),
        'done': false,
        'doneAt': null,
        'doneBy': null,
        'checked': false,
        'checkedBy': null,
        'checkedAt': null,
        'createdBy': me.uid,
        'createdByName': me.displayName,
        'createdAt': _now(),
      });

  /// Öğrencinin "Yaptım" butonu.
  static Future<void> setHomeworkDone(
      String sid, String hid, AppUser me, bool done) {
    final data = <String, Object?>{
      'done': done,
      'doneAt': done ? _now() : null,
      'doneBy': done ? me.name : null,
    };
    if (!done) {
      data['checked'] = false;
      data['checkedBy'] = null;
      data['checkedAt'] = null;
    }
    return _sub(sid, 'homeworks').doc(hid).update(data);
  }

  /// Veli / öğretmen kontrolü.
  static Future<void> setHomeworkChecked(
          String sid, String hid, AppUser me, bool checked) =>
      _sub(sid, 'homeworks').doc(hid).update({
        'checked': checked,
        'checkedBy': checked ? me.displayName : null,
        'checkedAt': checked ? _now() : null,
      });

  // -------------------------------------------------------------------------
  // Kitaplar
  // -------------------------------------------------------------------------
  static Stream<List<Book>> books(String sid) => _sub(sid, 'books')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Book.fromDoc).toList());

  static Future<void> addBook(
    String sid,
    AppUser me, {
    required String title,
    required String author,
    required int totalPages,
    String isbn = '',
    String durum = 'devam',
  }) =>
      _sub(sid, 'books').add({
        if (isbn.isNotEmpty) 'isbn': isbn,
        'durum': durum,
        'title': title,
        'author': author,
        'totalPages': totalPages,
        'currentPage': 0,
        'finished': false,
        'createdBy': me.uid,
        'createdAt': _now(),
      });

  static Stream<List<ReadingLog>> readingLogs(String sid) =>
      _sub(sid, 'readingLogs')
          .orderBy('date', descending: true)
          .limit(300)
          .snapshots()
          .map((s) => s.docs.map(ReadingLog.fromDoc).toList());

  static Stream<List<ReadingLog>> readingLogsOfBook(String sid, String bookId) =>
      _sub(sid, 'readingLogs')
          .where('bookId', isEqualTo: bookId)
          .snapshots()
          .map((s) {
        final list = s.docs.map(ReadingLog.fromDoc).toList();
        list.sort((a, b) => (b.date ?? DateTime(2000))
            .compareTo(a.date ?? DateTime(2000)));
        return list;
      });

  /// Bugün okunan sayfa sayısını kaydeder ve kitabın kaldığı sayfayı ilerletir.
  static Future<void> addReading(
    String sid,
    AppUser me,
    Book book, {
    required int pages,
    required int minutes,
  }) async {
    var toPage = book.currentPage + pages;
    if (book.totalPages > 0 && toPage > book.totalPages) {
      toPage = book.totalPages;
    }
    final realPages = toPage - book.currentPage;
    final batch = _fs.batch();
    batch.set(_sub(sid, 'readingLogs').doc(), {
      'bookId': book.id,
      'bookTitle': book.title,
      'fromPage': book.currentPage,
      'toPage': toPage,
      'pages': realPages,
      'minutes': minutes,
      'date': _now(),
      'createdBy': me.uid,
      'createdByName': me.name,
    });
    batch.update(_sub(sid, 'books').doc(book.id), {
      'currentPage': toPage,
      'finished': book.totalPages > 0 && toPage >= book.totalPages,
      'durum': book.totalPages > 0 && toPage >= book.totalPages ? 'bitti' : 'devam',
      'updatedAt': _now(),
    });
    await batch.commit();
  }

  /// Kitabın kitaplık durumunu değiştirir (istek / devam / bitti).
  static Future<void> setDurum(String sid, String coll, String id, String durum,
          {Book? book}) =>
      _sub(sid, coll).doc(id).update({
        'durum': durum,
        if (coll == 'books') 'finished': durum == 'bitti',
        if (book != null && durum == 'bitti' && book.totalPages > 0)
          'currentPage': book.totalPages,
      });

  static Future<void> setBookFinished(String sid, Book book, bool finished) =>
      _sub(sid, 'books').doc(book.id).update({
        'finished': finished,
        'durum': finished ? 'bitti' : 'devam',
        if (finished && book.totalPages > 0) 'currentPage': book.totalPages,
      });

  // -------------------------------------------------------------------------
  // Test kitapları
  // -------------------------------------------------------------------------
  static Stream<List<TestBook>> testBooks(String sid) => _sub(sid, 'testBooks')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(TestBook.fromDoc).toList());

  static Stream<TestBook?> testBookStream(String sid, String id) =>
      _sub(sid, 'testBooks')
          .doc(id)
          .snapshots()
          .map((d) => d.exists ? TestBook.fromDoc(d) : null);

  static Future<void> addTestBook(
    String sid,
    AppUser me, {
    required String title,
    required String publisher,
    required String subject,
    required int totalPages,
    required List<Topic> topics,
    String isbn = '',
    String durum = 'devam',
  }) =>
      _sub(sid, 'testBooks').add({
        if (isbn.isNotEmpty) 'isbn': isbn,
        'durum': durum,
        'title': title,
        'publisher': publisher,
        'subject': subject,
        'totalPages': totalPages,
        'topics': topics.map((t) => t.toMap()).toList(),
        'solvedPages': <int>[],
        'completedTopics': <String>[],
        'createdBy': me.uid,
        'createdAt': _now(),
      });

  static Future<void> updateTestBookTopics(
          String sid, String id, List<Topic> topics) =>
      _sub(sid, 'testBooks')
          .doc(id)
          .update({'topics': topics.map((t) => t.toMap()).toList()});

  static Future<void> setPagesSolved(
      String sid, String id, List<int> pages, bool solved) {
    if (pages.isEmpty) return Future.value();
    return _sub(sid, 'testBooks').doc(id).update({
      'solvedPages': solved
          ? FieldValue.arrayUnion(pages)
          : FieldValue.arrayRemove(pages),
      'lastActivity': _now(),
    });
  }

  static Future<void> setTopicDone(
          String sid, String id, String topic, bool done) =>
      _sub(sid, 'testBooks').doc(id).update({
        'completedTopics': done
            ? FieldValue.arrayUnion([topic])
            : FieldValue.arrayRemove([topic]),
        'lastActivity': _now(),
      });

  // -------------------------------------------------------------------------
  // Test / deneme sonuçları
  // -------------------------------------------------------------------------
  static Stream<List<TestResult>> testResults(String sid) =>
      _sub(sid, 'testResults')
          .orderBy('date', descending: true)
          .snapshots()
          .map((s) => s.docs.map(TestResult.fromDoc).toList());

  static Future<void> addTestResult(
    String sid,
    AppUser me, {
    required String name,
    required String subject,
    required int correct,
    required int wrong,
    required int blank,
    required int penalty,
    required DateTime date,
  }) =>
      _sub(sid, 'testResults').add({
        'name': name,
        'subject': subject,
        'correct': correct,
        'wrong': wrong,
        'blank': blank,
        'penalty': penalty,
        'date': Timestamp.fromDate(date),
        'createdBy': me.uid,
        'createdAt': _now(),
      });
}
