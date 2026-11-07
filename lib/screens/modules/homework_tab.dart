import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

/// ÖDEV KONTROL MODÜLÜ
/// - Veli, öğretmen ya da öğrenci ödev ekler.
/// - Öğrenci ödevini yapınca "Yaptım" butonuna basar.
/// - Veli / öğretmen "Kontrol Et" ile onaylar.
class HomeworkTab extends StatefulWidget {
  const HomeworkTab({super.key, required this.student, required this.me});

  final Student student;
  final AppUser me;

  @override
  State<HomeworkTab> createState() => _HomeworkTabState();
}

class _HomeworkTabState extends State<HomeworkTab> {
  late final LiveValue<List<Homework>> _hw =
      LiveValue(Db.homeworks(widget.student.id));
  int _filter = 0; // 0: bekleyen, 1: tamamlanan, 2: tümü

  @override
  void dispose() {
    _hw.dispose();
    super.dispose();
  }

  List<Homework> _filtered(List<Homework> all) {
    final far = DateTime(2100);
    switch (_filter) {
      case 0:
        return all.where((h) => !h.done).toList()
          ..sort((a, b) => (a.dueDate ?? far).compareTo(b.dueDate ?? far));
      case 1:
        return all.where((h) => h.done).toList()
          ..sort((a, b) => (b.doneAt ?? DateTime(2000))
              .compareTo(a.doneAt ?? DateTime(2000)));
      default:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _hw,
        builder: (context, _) {
          if (_hw.error != null) {
            return EmptyState(
                icon: Icons.error_outline, text: errorText(_hw.error!));
          }
          if (_hw.loading) return const Loading();
          final all = _hw.value!;
          final list = _filtered(all);
          final pendingCount = all.where((h) => !h.done).length;
          final doneCount = all.length - pendingCount;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 0, label: Text('Bekleyen ($pendingCount)')),
                  ButtonSegment(value: 1, label: Text('Yapılan ($doneCount)')),
                  const ButtonSegment(value: 2, label: Text('Tümü')),
                ],
                selected: {_filter},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                EmptyState(
                  icon: _filter == 0
                      ? Icons.celebration_outlined
                      : Icons.assignment_outlined,
                  text: _filter == 0
                      ? 'Bekleyen ödev yok! 🎉'
                      : 'Burada henüz ödev yok.',
                )
              else
                ...list.map((h) => HomeworkCard(
                    student: widget.student, me: widget.me, hw: h)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_homework',
        onPressed: () => openSheet<void>(
            context, AddHomeworkSheet(student: widget.student, me: widget.me)),
        icon: const Icon(Icons.add),
        label: const Text('Ödev Ekle'),
      ),
    );
  }
}

/// Tek bir ödev kartı. Özet sekmesinde de kullanılır.
class HomeworkCard extends StatelessWidget {
  const HomeworkCard({
    super.key,
    required this.student,
    required this.me,
    required this.hw,
  });

  final Student student;
  final AppUser me;
  final Homework hw;

  bool get _isStudent => me.role == UserRole.student;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final overdue =
        !hw.done && hw.dueDate != null && hw.dueDate!.isBefore(today());
    final dueToday = !hw.done &&
        hw.dueDate != null &&
        DateUtils.isSameDay(hw.dueDate, DateTime.now());
    final canDelete = me.role.isAdult || hw.createdBy == me.uid;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hw.done ? Icons.check_circle : Icons.assignment_outlined,
                  color: hw.done ? Colors.green : cs.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(hw.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (canDelete)
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v != 'delete') return;
                      final ok = await confirm(context,
                          title: 'Ödev silinsin mi?',
                          message: hw.title,
                          ok: 'Sil',
                          destructive: true);
                      if (!ok || !context.mounted) return;
                      await runSafe(context,
                          () => Db.deleteDoc(student.id, 'homeworks', hw.id));
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'delete', child: Text('Sil')),
                    ],
                  )
                else
                  const SizedBox(height: 40),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (hw.subject.isNotEmpty)
                        Chip(
                          label: Text(hw.subject),
                          visualDensity: VisualDensity.compact,
                        ),
                      for (final k in hw.kitaplar)
                        Chip(
                          avatar: Icon(
                              k.tur == 'okuma'
                                  ? Icons.menu_book_outlined
                                  : Icons.library_books_outlined,
                              size: 16),
                          label: Text(k.ad),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (hw.sayfa.isNotEmpty)
                        Chip(
                          avatar: const Icon(Icons.bookmark_outline, size: 16),
                          label: Text(hw.sayfa),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (hw.dueDate != null)
                        Chip(
                          avatar: Icon(Icons.event,
                              size: 16,
                              color: overdue ? cs.onErrorContainer : null),
                          label: Text(overdue
                              ? 'Gecikti: ${fmtShort(hw.dueDate)}'
                              : dueToday
                                  ? 'Bugün teslim'
                                  : 'Teslim: ${fmtShort(hw.dueDate)}'),
                          backgroundColor: overdue ? cs.errorContainer : null,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  if (hw.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(hw.description),
                  ],
                  const SizedBox(height: 4),
                  Text('Ekleyen: ${hw.createdByName}',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 10),
                  _statusArea(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusArea(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Henüz yapılmadı
    if (!hw.done) {
      if (_isStudent) {
        return FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            textStyle:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          onPressed: () => runSafe(
            context,
            () => Db.setHomeworkDone(student.id, hw.id, me, true),
            success: 'Aferin! Ödevin "yapıldı" olarak işaretlendi 🎉',
          ),
          icon: const Icon(Icons.check),
          label: const Text('Yaptım'),
        );
      }
      return Row(
        children: [
          Icon(Icons.hourglass_empty, size: 18, color: cs.outline),
          const SizedBox(width: 6),
          const Expanded(child: Text('Öğrenci henüz "Yaptım" demedi')),
          TextButton(
            onPressed: () =>
                runSafe(context, () => Db.setHomeworkDone(student.id, hw.id, me, true)),
            child: const Text('Yapıldı say'),
          ),
        ],
      );
    }

    final doneText =
        'Yapıldı • ${fmtDateTime(hw.doneAt)}${hw.doneBy.isNotEmpty ? ' (${hw.doneBy})' : ''}';

    // Yapıldı ve kontrol edildi
    if (hw.checked) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(child: Text('$doneText\nKontrol eden: ${hw.checkedBy}')),
            if (me.role.isAdult)
              TextButton(
                onPressed: () => runSafe(context,
                    () => Db.setHomeworkChecked(student.id, hw.id, me, false)),
                child: const Text('Geri al'),
              ),
          ],
        ),
      );
    }

    // Yapıldı, kontrol bekliyor
    return Row(
      children: [
        const Icon(Icons.check_circle_outline, color: Colors.green),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              _isStudent ? '$doneText\nKontrol bekleniyor' : doneText),
        ),
        if (_isStudent)
          TextButton(
            onPressed: () => runSafe(
                context, () => Db.setHomeworkDone(student.id, hw.id, me, false)),
            child: const Text('Geri al'),
          )
        else
          FilledButton.tonalIcon(
            onPressed: () => runSafe(
              context,
              () => Db.setHomeworkChecked(student.id, hw.id, me, true),
              success: 'Ödev kontrol edildi.',
            ),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Kontrol Et'),
          ),
      ],
    );
  }
}

class AddHomeworkSheet extends StatefulWidget {
  const AddHomeworkSheet({super.key, required this.student, required this.me});

  final Student student;
  final AppUser me;

  @override
  State<AddHomeworkSheet> createState() => _AddHomeworkSheetState();
}

class _AddHomeworkSheetState extends State<AddHomeworkSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _sayfa = TextEditingController();
  String? _subject;
  DateTime? _due = today().add(const Duration(days: 1));
  bool _busy = false;
  bool _tumKitaplar = false;
  final _secili = <String, OdevKitabi>{}; // anahtar: tur:id
  late final LiveValue<List<TestBook>> _testKitaplari =
      LiveValue(Db.testBooks(widget.student.id));
  late final LiveValue<List<Book>> _okumaKitaplari =
      LiveValue(Db.books(widget.student.id));

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _sayfa.dispose();
    _testKitaplari.dispose();
    _okumaKitaplari.dispose();
    super.dispose();
  }

  static String _katla(String s) => s
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'i')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ş', 's')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');

  /// Dersle eşleşen kitap mı? (Ders alanı yoksa adına bakılır.)
  bool _derseUygun(String kitapDersi, String ad) {
    final d = _subject;
    if (d == null || d.isEmpty) return true;
    if (kitapDersi.isNotEmpty) {
      if (kitapDersi == d) return true;
      if (kitapDersi == 'Genel / Karma') return true;
      return false;
    }
    final k = _katla(ad), dk = _katla(d).split(' ').first;
    return k.contains(dk);
  }

  void _kitapSec(OdevKitabi k, bool secili) {
    setState(() {
      final anahtar = '${k.tur}:${k.id}';
      if (secili) {
        _secili[anahtar] = k;
        if (_title.text.trim().isEmpty) _title.text = k.ad;
      } else {
        _secili.remove(anahtar);
      }
    });
  }

  Widget _kitaplarBolumu() {
    return ListenableBuilder(
      listenable: Listenable.merge([_testKitaplari, _okumaKitaplari]),
      builder: (context, _) {
        final testler = (_testKitaplari.value ?? const <TestBook>[])
            .where((b) => b.durumu != 'istek')
            .toList();
        final okumalar = (_okumaKitaplari.value ?? const <Book>[])
            .where((b) => b.durumu != 'istek')
            .toList();
        final adaylar = <(OdevKitabi, String, bool)>[
          for (final b in testler)
            (
              OdevKitabi(id: b.id, tur: 'test', ad: b.title),
              [b.publisher, if (b.subject.isNotEmpty) b.subject].where((x) => x.isNotEmpty).join(' • '),
              _derseUygun(b.subject, b.title),
            ),
          for (final b in okumalar)
            (
              OdevKitabi(id: b.id, tur: 'okuma', ad: b.title),
              [if (b.author.isNotEmpty) b.author, 'Okuma kitabı'].join(' • '),
              _derseUygun('', b.title) ||
                  _subject == 'Türkçe' ||
                  _subject == 'Edebiyat',
            ),
        ];
        final uygun = adaylar.where((a) => a.$3).toList();
        final gosterilen = _tumKitaplar ? adaylar : uygun;
        final yukleniyor = _testKitaplari.loading || _okumaKitaplari.loading;
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.library_books_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _subject == null ? 'Kitaplar' : 'Kitaplar • $_subject',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (adaylar.length != uygun.length)
                      TextButton(
                        onPressed: () => setState(() => _tumKitaplar = !_tumKitaplar),
                        child: Text(_tumKitaplar ? 'Bu ders' : 'Tümü (${adaylar.length})'),
                      ),
                  ],
                ),
                if (yukleniyor)
                  const LinearProgressIndicator()
                else if (gosterilen.isEmpty)
                  Text(
                    adaylar.isEmpty
                        ? 'Henüz kayıtlı kitap yok. Kitaplar / Test Kitapları sekmesinden ekleyebilirsiniz.'
                        : 'Bu derse kayıtlı kitap yok.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  for (final a in gosterilen)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _secili.containsKey('${a.$1.tur}:${a.$1.id}'),
                      onChanged: (v) => _kitapSec(a.$1, v ?? false),
                      title: Text(a.$1.ad),
                      subtitle: a.$2.isEmpty ? null : Text(a.$2),
                      secondary: Icon(a.$1.tur == 'okuma'
                          ? Icons.menu_book_outlined
                          : Icons.library_books_outlined),
                    ),
                if (_secili.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  TextField(
                    controller: _sayfa,
                    decoration: const InputDecoration(
                      labelText: 'Sayfa / test',
                      hintText: 'Ör. 45-47 ya da Test 3-5',
                      prefixIcon: Icon(Icons.bookmark_outline),
                      isDense: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _due ?? today(),
      firstDate: today().subtract(const Duration(days: 30)),
      lastDate: today().add(const Duration(days: 365)),
      helpText: 'Teslim tarihi',
    );
    if (d != null) setState(() => _due = d);
  }

  Future<void> _save() async {
    var title = _title.text.trim();
    final sayfa = _sayfa.text.trim();
    if (title.isEmpty && _secili.isNotEmpty) {
      title = _secili.values.map((k) => k.ad).join(', ');
    }
    if (title.isEmpty) {
      showInfo(context, 'Ödev başlığını yazın ya da kitap seçin.');
      return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final ok = await runSafe(
      context,
      () => Db.addHomework(
        widget.student.id,
        widget.me,
        title: title,
        subject: _subject ?? '',
        description: _desc.text.trim(),
        dueDate: _due,
        kitaplar: _secili.values.toList(),
        sayfa: _secili.isEmpty ? '' : sayfa,
      ),
      success: 'Ödev eklendi.',
    );
    if (ok) {
      nav.pop();
    } else if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: '${widget.student.name} için ödev',
      children: [
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              labelText: 'Ödev', hintText: 'Ör. Matematik sayfa 45-47'),
        ),
        const SizedBox(height: 12),
        SubjectDropdown(
            value: _subject,
            onChanged: (v) => setState(() {
                  _subject = v;
                  _tumKitaplar = false;
                })),
        const SizedBox(height: 12),
        _kitaplarBolumu(),
        const SizedBox(height: 12),
        TextField(
          controller: _desc,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Açıklama (isteğe bağlı)'),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text(_due == null ? 'Teslim tarihi yok' : 'Teslim: ${fmtDate(_due)}'),
          trailing: Wrap(
            children: [
              if (_due != null)
                IconButton(
                    tooltip: 'Tarihi kaldır',
                    onPressed: () => setState(() => _due = null),
                    icon: const Icon(Icons.clear)),
              IconButton(
                  tooltip: 'Tarih seç',
                  onPressed: _pickDate,
                  icon: const Icon(Icons.edit_calendar)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _busy ? null : _save,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
