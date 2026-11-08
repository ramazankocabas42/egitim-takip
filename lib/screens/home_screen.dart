import 'package:flutter/material.dart';

import '../models.dart';
import '../services/db.dart';
import '../services/guncelleme.dart';
import '../services/notifications.dart';
import '../services/sms_aktarici.dart';
import '../widgets/common.dart';
import 'ogrenci_profil.dart';
import 'student_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.me});

  final AppUser me;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late Stream<List<Student>> _stream;
  late OdevIzleyici _izleyici;

  @override
  void initState() {
    super.initState();
    _stream = Db.myStudents(widget.me);
    _izleyici = OdevIzleyici(widget.me)..baslat();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Bildirim.izinIste();
      if (mounted) await Guncelleme.kontrolEt(context);
      if (mounted) await _smsTara();
    });
  }

  /// Kurum SMS'lerindeki yeni deneme sonuçlarını sessizce ekler.
  Future<void> _smsTara() async {
    final eklenen = await SmsAktarici.tara(widget.me);
    if (eklenen.isNotEmpty && mounted) {
      showInfo(
          context,
          eklenen.length == 1
              ? 'Yeni deneme eklendi: ${eklenen.first}'
              : '${eklenen.length} yeni deneme sonucu eklendi.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _smsTara();
  }

  @override
  void didUpdateWidget(HomeScreen old) {
    super.didUpdateWidget(old);
    if (old.me.uid != widget.me.uid || old.me.role != widget.me.role) {
      _stream = Db.myStudents(widget.me);
      _izleyici.durdur();
      _izleyici = OdevIzleyici(widget.me)..baslat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _izleyici.durdur();
    super.dispose();
  }

  AppUser get me => widget.me;

  String get _title => switch (me.role) {
        UserRole.parent => 'Çocuklarım',
        UserRole.teacher => 'Öğrencilerim',
        UserRole.student => 'Eğitim Takip',
      };

  String get _emptyText => switch (me.role) {
        UserRole.parent =>
          'Henüz öğrenci eklemediniz.\nAşağıdaki "Öğrenci Ekle" butonuyla çocuğunuzu ekleyin.\n\n'
              'Eşiniz çocuğu zaten eklediyse, onun paylaştığı "Veli kodu" ile sağ üstteki anahtar simgesinden katılabilirsiniz.',
        UserRole.teacher =>
          'Henüz öğrenciniz yok.\nVelinin paylaştığı davet koduyla "Kodla Katıl" butonuna basın.',
        UserRole.student =>
          'Velinden davet kodunu iste ve "Kodla Katıl" butonuna basarak yaz.',
      };

  void _openStudent(Student s) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StudentScreen(studentId: s.id, me: me),
    ));
  }

  Future<void> _addStudent() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AddStudentDialog(me: me),
    );
  }

  Future<void> _join() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _JoinDialog(me: me),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Student>>(
      stream: _stream,
      builder: (context, snap) {
        final list = snap.data ?? const <Student>[];
        final loading =
            snap.connectionState == ConnectionState.waiting && !snap.hasData;

        // Öğrenci hesabı tek bir öğrenciye bağlıysa doğrudan kendi sayfası açılır.
        if (me.role == UserRole.student && list.length == 1) {
          return StudentScreen(studentId: list.first.id, me: me, isRoot: true);
        }

        Widget body;
        if (loading) {
          body = const Loading();
        } else if (snap.hasError) {
          body = EmptyState(
              icon: Icons.error_outline, text: errorText(snap.error!));
        } else if (list.isEmpty && me.role == UserRole.student) {
          body = ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 24),
              Icon(Icons.school_outlined, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text('Hoş geldin ${me.name}!',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Kendi başıma kullanacağım',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 4),
                      const Text('YKS, KPSS, AGS ya da LGS hazırlığını kendin takip et. '
                          'ÖSYM sonuçlarını aktar, konu eksiklerini gör. İstersen sonra '
                          'koçunu ya da velini davet kodunla eklersin.'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => OgrenciProfilOlusturEkrani(me: me))),
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Kendi profilimi oluştur'),
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Velim / öğretmenim beni ekledi',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 4),
                      const Text('Velinden ya da öğretmeninden aldığın 6 haneli davet koduyla katıl.'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _join,
                        icon: const Icon(Icons.vpn_key_outlined),
                        label: const Text('Kodla katıl'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        } else if (list.isEmpty) {
          body = EmptyState(icon: Icons.groups_outlined, text: _emptyText);
        } else {
          body = ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                child: Text('Merhaba ${me.name} 👋',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              ...list.map((s) => _StudentCard(
                    student: s,
                    onTap: () => _openStudent(s),
                  )),
            ],
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(_title),
            actions: [
              if (me.role == UserRole.parent)
                IconButton(
                  tooltip: 'Davet koduyla katıl',
                  icon: const Icon(Icons.vpn_key_outlined),
                  onPressed: _join,
                ),
              const LogoutButton(),
            ],
          ),
          body: body,
          floatingActionButton: me.role == UserRole.parent
              ? FloatingActionButton.extended(
                  heroTag: 'home_fab',
                  onPressed: _addStudent,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Öğrenci Ekle'),
                )
              : FloatingActionButton.extended(
                  heroTag: 'home_fab',
                  onPressed: _join,
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: const Text('Kodla Katıl'),
                ),
        );
      },
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.student, required this.onTap});

  final Student student;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: onTap,
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: cs.primaryContainer,
          child: Text(
            student.name.isEmpty ? '?' : student.name[0].toUpperCase(),
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: cs.onPrimaryContainer),
          ),
        ),
        title: Text(student.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: StreamBuilder<int>(
          stream: Db.pendingHomeworkCount(student.id),
          builder: (context, snap) {
            final n = snap.data;
            final hw = n == null
                ? ''
                : (n == 0 ? ' • Bekleyen ödev yok' : ' • $n bekleyen ödev');
            return Text('${student.grade}$hw');
          },
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _AddStudentDialog extends StatefulWidget {
  const _AddStudentDialog({required this.me});

  final AppUser me;

  @override
  State<_AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<_AddStudentDialog> {
  final _name = TextEditingController();
  String _grade = grades[5];
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final ok = await runSafe(
      context,
      () => Db.addStudent(widget.me, name: name, grade: _grade),
      success: '$name eklendi. Davet kodunu öğrenci sayfasındaki kişiler simgesinden görebilirsiniz.',
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Öğrenci Ekle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
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
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Vazgeç')),
        FilledButton(
            onPressed: _busy ? null : _save, child: const Text('Ekle')),
      ],
    );
  }
}

class _JoinDialog extends StatefulWidget {
  const _JoinDialog({required this.me});

  final AppUser me;

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    final ok = await runSafe(
      context,
      () => Db.joinWithCode(widget.me, _code.text),
      success: 'Öğrenciye bağlandınız.',
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = switch (widget.me.role) {
      UserRole.teacher =>
        'Velinin size verdiği 6 haneli kodu yazın. Öğrenci listenize eklenecek.',
      UserRole.parent =>
        'Diğer velinin (ör. eşinizin) paylaştığı "Veli kodu"nu yazın. Çocuğu birlikte takip edebilirsiniz.',
      UserRole.student => 'Velinden aldığın 6 haneli kodu yaz.',
    };
    return AlertDialog(
      title: const Text('Davet Koduyla Katıl'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(info),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            style: const TextStyle(
                fontSize: 24, letterSpacing: 6, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(hintText: 'ABC123'),
            onSubmitted: (_) => _join(),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Vazgeç')),
        FilledButton(
            onPressed: _busy ? null : _join, child: const Text('Katıl')),
      ],
    );
  }
}
