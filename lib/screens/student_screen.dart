import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/db.dart';
import '../widgets/common.dart';
import 'modules/books_tab.dart';
import 'modules/homework_tab.dart';
import 'modules/lgs_tab.dart';
import 'modules/okul_tab.dart';
import 'modules/oneriler_tab.dart';
import 'modules/osym_tab.dart';
import 'modules/overview_tab.dart';
import 'modules/plan_tab.dart';
import 'modules/program_tab.dart';
import 'modules/soru_takibi_tab.dart';
import 'modules/test_books_tab.dart';
import 'modules/tests_tab.dart';

/// Bir öğrencinin tüm modüllerini sekmeler halinde gösterir.
class StudentScreen extends StatefulWidget {
  const StudentScreen({
    super.key,
    required this.studentId,
    required this.me,
    this.isRoot = false,
  });

  final String studentId;
  final AppUser me;

  /// Öğrenci hesabında bu ekran ana ekrandır (geri tuşu yok, çıkış butonu var).
  final bool isRoot;

  @override
  State<StudentScreen> createState() => _StudentScreenState();
}

class _StudentScreenState extends State<StudentScreen> {
  late final Stream<Student?> _stream = Db.studentStream(widget.studentId);

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    return StreamBuilder<Student?>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(actions: [if (widget.isRoot) const LogoutButton()]),
            body: const EmptyState(
                icon: Icons.lock_outline,
                text: 'Bu öğrenciye erişiminiz yok ya da bağlantınız kaldırıldı.'),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Scaffold(body: Loading());
        }
        final s = snap.data;
        if (s == null) {
          return Scaffold(
            appBar: AppBar(actions: [if (widget.isRoot) const LogoutButton()]),
            body: const EmptyState(
                icon: Icons.person_off_outlined, text: 'Öğrenci bulunamadı.'),
          );
        }
        final lgs = !okulDisi(s.grade) && (ortaokulVeAlti(s.grade) || s.grade.isEmpty);
        final osym = !ortaokulVeAlti(s.grade);
        final sekmeler = <(Tab, Widget)>[
          (const Tab(icon: Icon(Icons.dashboard_outlined), text: 'Özet'), OverviewTab(student: s, me: me)),
          (const Tab(icon: Icon(Icons.tips_and_updates_outlined), text: 'Önerilerim'), OnerilerTab(student: s, me: me)),
          if (osym)
            (const Tab(icon: Icon(Icons.workspace_premium_outlined), text: 'ÖSYM Sınavları'), OsymTab(student: s, me: me)),
          (const Tab(icon: Icon(Icons.assignment_outlined), text: 'Ödevler'), HomeworkTab(student: s, me: me)),
          (const Tab(icon: Icon(Icons.calendar_month_outlined), text: 'Plan'), PlanTab(student: s, me: me)),
          (const Tab(icon: Icon(Icons.schedule), text: 'Program'), ProgramTab(student: s, me: me)),
          (const Tab(icon: Icon(Icons.edit_note), text: 'Soru Takibi'), SoruTakibiTab(student: s, me: me)),
          if (lgs)
            (const Tab(icon: Icon(Icons.flag_outlined), text: 'LGS Deneme'), LgsTab(student: s, me: me)),
          if (!okulDisi(s.grade))
            (const Tab(icon: Icon(Icons.school_outlined), text: 'Okul'), OkulTab(student: s, me: me)),
          (const Tab(icon: Icon(Icons.menu_book_outlined), text: 'Kitaplar'), BooksTab(student: s, me: me)),
          (const Tab(icon: Icon(Icons.library_books_outlined), text: 'Test Kitapları'), TestBooksTab(student: s, me: me)),
          (const Tab(icon: Icon(Icons.quiz_outlined), text: 'Testler'), TestsTab(student: s, me: me)),
        ];
        return DefaultTabController(
          key: ValueKey(sekmeler.length),
          length: sekmeler.length,
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: !widget.isRoot,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name),
                  Text(s.grade, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Kişiler ve davet kodu',
                  icon: const Icon(Icons.group_outlined),
                  onPressed: () =>
                      openSheet<void>(context, StudentInfoSheet(student: s, me: me)),
                ),
                if (widget.isRoot) const LogoutButton(),
              ],
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [for (final x in sekmeler) x.$1],
              ),
            ),
            body: TabBarView(
              children: [for (final x in sekmeler) x.$2],
            ),
          ),
        );
      },
    );
  }
}

/// Davet kodu, bağlı kişiler ve öğrenci yönetimi.
class StudentInfoSheet extends StatefulWidget {
  const StudentInfoSheet({super.key, required this.student, required this.me});

  final Student student;
  final AppUser me;

  @override
  State<StudentInfoSheet> createState() => _StudentInfoSheetState();
}

class _StudentInfoSheetState extends State<StudentInfoSheet> {
  late Future<List<AppUser>> _members;

  Student get s => widget.student;
  AppUser get me => widget.me;
  bool get _isParent => s.isParent(me.uid);

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  void _loadMembers() {
    _members = Db.getUsers([
      ...s.parentIds,
      ...s.teacherIds,
      if (s.studentUid != null) s.studentUid!,
    ]);
  }

  Future<void> _removeMember(AppUser u) async {
    final ok = await confirm(context,
        title: 'Bağlantıyı kaldır',
        message: '${u.displayName} artık ${s.name} bilgilerini göremeyecek. Emin misiniz?',
        ok: 'Kaldır',
        destructive: true);
    if (!ok || !mounted) return;
    final done = await runSafe(context, () async {
      if (s.teacherIds.contains(u.uid)) {
        await Db.removeTeacher(s.id, u.uid);
      } else if (s.studentUid == u.uid) {
        await Db.unlinkStudentAccount(s.id);
      } else {
        await Db.removeParent(s.id, u.uid);
      }
    }, success: 'Bağlantı kaldırıldı.');
    if (done && mounted) Navigator.pop(context);
  }

  Future<void> _regenerate() async {
    final ok = await confirm(context,
        title: 'Yeni davet kodu',
        message: 'Eski kod çalışmaz hale gelir. Daha önce bağlananlar etkilenmez.',
        ok: 'Yenile');
    if (!ok || !mounted) return;
    final done = await runSafe(context, () => Db.regenerateCode(me, s),
        success: 'Yeni davet kodu oluşturuldu.');
    if (done && mounted) Navigator.pop(context);
  }

  Future<void> _edit() async {
    final nav = Navigator.of(context);
    await showDialog<void>(
      context: context,
      builder: (_) => _EditStudentDialog(student: s),
    );
    nav.pop();
  }

  Future<void> _delete() async {
    final ok = await confirm(context,
        title: '${s.name} silinsin mi?',
        message: 'Öğrencinin tüm ödev, kitap, test kitabı ve deneme kayıtları kalıcı olarak silinir.',
        ok: 'Sil',
        destructive: true);
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    final done = await runSafe(context, () => Db.deleteStudent(s),
        success: 'Öğrenci silindi.');
    if (done) nav.popUntil((r) => r.isFirst);
  }

  Future<void> _leave() async {
    final ok = await confirm(context,
        title: 'Öğrenciden ayrıl',
        message: '${s.name} listenizden çıkarılacak.',
        ok: 'Ayrıl',
        destructive: true);
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    final done = await runSafe(context, () => Db.leaveAsTeacher(s.id, me.uid));
    if (done) nav.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SheetFrame(
      title: s.name,
      children: [
        if (me.role.isAdult || s.isParent(me.uid)) ...[
          Card(
            color: cs.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('Öğretmen / öğrenci davet kodu',
                      style: TextStyle(color: cs.onPrimaryContainer)),
                  const SizedBox(height: 4),
                  SelectableText(
                    s.inviteCode,
                    style: TextStyle(
                        fontSize: 32,
                        letterSpacing: 6,
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bu kodu öğretmenle ve çocuğunuzun kendi hesabıyla paylaşın. '
                    'Uygulamada "Kodla Katıl" deyip yazmaları yeterli.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(
                              text: 'Eğitim Takip uygulamasında ${s.name} için '
                                  'davet kodu: ${s.inviteCode}'));
                          if (context.mounted) {
                            showInfo(context, 'Kod kopyalandı.');
                          }
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Kopyala'),
                      ),
                      if (_isParent)
                        TextButton.icon(
                          onPressed: _regenerate,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Kodu yenile'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_isParent) _ParentCodeCard(student: s, me: me),
        const SectionTitle('Bağlı kişiler'),
        FutureBuilder<List<AppUser>>(
          future: _members,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                  padding: EdgeInsets.all(16), child: Loading());
            }
            final users = [...snap.data!];
            if (s.studentUid == null && me.role.isAdult) {
              users.add(AppUser(
                  uid: '',
                  name: 'Öğrenci hesabı henüz bağlanmadı',
                  email: '',
                  role: UserRole.student));
            }
            return Column(
              children: users.map((u) {
                final canRemove =
                    _isParent && u.uid.isNotEmpty && u.uid != me.uid;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Icon(roleIcon(u.role))),
                  title: Text(u.name),
                  subtitle: Text(u.uid.isEmpty
                      ? 'Çocuğunuz kendi telefonundan "Öğrenci" hesabı açıp kodu girebilir.'
                      : u.role.label + (u.uid == me.uid ? ' (siz)' : '')),
                  trailing: canRemove
                      ? IconButton(
                          tooltip: 'Kaldır',
                          icon: const Icon(Icons.person_remove_outlined),
                          onPressed: () => _removeMember(u),
                        )
                      : null,
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 12),
        if (_isParent) ...[
          OutlinedButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Adı / sınıfı düzenle'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cs.error),
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Öğrenciyi sil'),
          ),
        ],
        if (s.isTeacher(me.uid))
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cs.error),
            onPressed: _leave,
            icon: const Icon(Icons.logout),
            label: const Text('Bu öğrenciden ayrıl'),
          ),
      ],
    );
  }
}

/// Yalnızca velilerin gördüğü, eşi / diğer veliyi eklemek için tek kullanımlık kod.
class _ParentCodeCard extends StatefulWidget {
  const _ParentCodeCard({required this.student, required this.me});

  final Student student;
  final AppUser me;

  @override
  State<_ParentCodeCard> createState() => _ParentCodeCardState();
}

class _ParentCodeCardState extends State<_ParentCodeCard> {
  late final Stream<String?> _stream = Db.parentCodeStream(widget.student.id);

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: StreamBuilder<String?>(
          stream: _stream,
          builder: (context, snap) {
            final code = snap.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Veli kodu (eşiniz / diğer veli için)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text(
                    'Tam yetki verir ve tek kullanımlıktır. Öğretmenle paylaşmayın.'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        code ?? '—',
                        style: const TextStyle(
                            fontSize: 22,
                            letterSpacing: 4,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kopyala',
                      icon: const Icon(Icons.copy),
                      onPressed: code == null
                          ? null
                          : () async {
                              await Clipboard.setData(ClipboardData(
                                  text: 'Eğitim Takip uygulamasında ${s.name} '
                                      'için veli kodu: $code'));
                              if (context.mounted) {
                                showInfo(context, 'Veli kodu kopyalandı.');
                              }
                            },
                    ),
                    IconButton(
                      tooltip: code == null ? 'Kod oluştur' : 'Kodu yenile',
                      icon: const Icon(Icons.refresh),
                      onPressed: () => runSafe(
                        context,
                        () => Db.regenerateParentCode(widget.me, s.id),
                        success: 'Yeni veli kodu oluşturuldu.',
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EditStudentDialog extends StatefulWidget {
  const _EditStudentDialog({required this.student});

  final Student student;

  @override
  State<_EditStudentDialog> createState() => _EditStudentDialogState();
}

class _EditStudentDialogState extends State<_EditStudentDialog> {
  late final _name = TextEditingController(text: widget.student.name);
  late String _grade =
      grades.contains(widget.student.grade) ? widget.student.grade : grades[5];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Öğrenciyi düzenle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Adı Soyadı'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _grade,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Sınıfı'),
            items: grades
                .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                .toList(),
            onChanged: (v) => setState(() => _grade = v ?? _grade),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () async {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            final nav = Navigator.of(context);
            final ok = await runSafe(context,
                () => Db.updateStudent(widget.student.id, name: name, grade: _grade));
            if (ok) nav.pop();
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
