import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

/// TEST / DENEME SONUÇLARI MODÜLÜ
/// Çözülen test ya da denemenin doğru-yanlış-boş sayıları girilir, net hesaplanır.
class TestsTab extends StatefulWidget {
  const TestsTab({super.key, required this.student, required this.me});

  final Student student;
  final AppUser me;

  @override
  State<TestsTab> createState() => _TestsTabState();
}

class _TestsTabState extends State<TestsTab> {
  late final LiveValue<List<TestResult>> _results =
      LiveValue(Db.testResults(widget.student.id));
  String? _subjectFilter;

  @override
  void dispose() {
    _results.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _results,
        builder: (context, _) {
          if (_results.error != null) {
            return EmptyState(
                icon: Icons.error_outline, text: errorText(_results.error!));
          }
          if (_results.loading) return const Loading();
          final all = _results.value!;
          if (all.isEmpty) {
            return const EmptyState(
              icon: Icons.quiz_outlined,
              text: 'Henüz test ya da deneme sonucu yok.\n'
                  '"Sonuç Ekle" ile doğru, yanlış ve boş sayılarını girin.',
            );
          }
          final usedSubjects = all
              .map((r) => r.subject)
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
          final list = _subjectFilter == null
              ? all
              : all.where((r) => r.subject == _subjectFilter).toList();
          final last = list.take(10).toList().reversed.toList();
          final last5 = list.take(5).toList();
          final avg = last5.isEmpty
              ? 0.0
              : last5.map((r) => r.net).reduce((a, b) => a + b) / last5.length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              if (usedSubjects.length > 1)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: const Text('Tümü'),
                          selected: _subjectFilter == null,
                          onSelected: (_) =>
                              setState(() => _subjectFilter = null),
                        ),
                      ),
                      ...usedSubjects.map((s) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(s),
                              selected: _subjectFilter == s,
                              onSelected: (_) =>
                                  setState(() => _subjectFilter = s),
                            ),
                          )),
                    ],
                  ),
                ),
              SizedBox(
                height: 100,
                child: Row(
                  children: [
                    Expanded(
                        child: StatCard(
                            icon: Icons.trending_up,
                            label: 'Son 5 ortalama net',
                            value: avg.toStringAsFixed(2))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: StatCard(
                            icon: Icons.format_list_numbered,
                            label: 'Toplam kayıt',
                            value: '${list.length}',
                            color: Colors.orange)),
                  ],
                ),
              ),
              if (last.length > 1) ...[
                const SectionTitle('Son sonuçlar (net)'),
                MiniBars(
                  values: last.map((r) => r.net < 0 ? 0.0 : r.net).toList(),
                  labels: last.map((r) => fmtShort(r.date)).toList(),
                  decimals: 1,
                ),
              ],
              const SectionTitle('Tüm sonuçlar'),
              ...list.map((r) => _ResultCard(
                  student: widget.student, me: widget.me, result: r)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_tests',
        onPressed: () => openSheet<void>(
            context, _AddResultSheet(student: widget.student, me: widget.me)),
        icon: const Icon(Icons.add),
        label: const Text('Sonuç Ekle'),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.student, required this.me, required this.result});

  final Student student;
  final AppUser me;
  final TestResult result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final canDelete = me.role.isAdult || r.createdBy == me.uid;
    Widget pill(String label, int n, Color c) => Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('$label $n',
              style: TextStyle(color: c, fontWeight: FontWeight.w600)),
        );
    return Card(
      child: ListTile(
        title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text([
                if (r.subject.isNotEmpty) r.subject,
                fmtDate(r.date),
              ].join(' • ')),
              const SizedBox(height: 6),
              Row(children: [
                pill('D', r.correct, Colors.green),
                pill('Y', r.wrong, Colors.red),
                pill('B', r.blank, Colors.grey),
              ]),
            ],
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(r.net.toStringAsFixed(2),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Text('net'),
          ],
        ),
        onLongPress: canDelete
            ? () async {
                final ok = await confirm(context,
                    title: 'Sonuç silinsin mi?',
                    message: r.name,
                    ok: 'Sil',
                    destructive: true);
                if (!ok || !context.mounted) return;
                await runSafe(
                    context, () => Db.deleteDoc(student.id, 'testResults', r.id));
              }
            : null,
      ),
    );
  }
}

class _AddResultSheet extends StatefulWidget {
  const _AddResultSheet({required this.student, required this.me});

  final Student student;
  final AppUser me;

  @override
  State<_AddResultSheet> createState() => _AddResultSheetState();
}

class _AddResultSheetState extends State<_AddResultSheet> {
  final _name = TextEditingController();
  final _correct = TextEditingController();
  final _wrong = TextEditingController();
  final _blank = TextEditingController();
  String? _subject;
  int _penalty = 0;
  DateTime _date = today();
  bool _busy = false;
  TestBook? _kitap;
  String? _konu;
  int? _testNo;

  /// Kitap / konu / test seçilince adı otomatik oluşturur.
  void _adiOlustur() {
    final parcalar = <String>[
      if (_kitap != null) _kitap!.title,
      if (_konu != null && _konu!.isNotEmpty) _konu!,
      if (_testNo != null) 'Test $_testNo',
    ];
    _name.text = parcalar.join(' – ');
  }

  Future<void> _kitapSec() async {
    final kitap = await showModalBottomSheet<TestBook>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _KitapSecici(studentId: widget.student.id),
    );
    if (kitap == null) return;
    setState(() {
      _kitap = kitap;
      _konu = null;
      _testNo = null;
      if (subjects.contains(kitap.subject)) _subject = kitap.subject;
      _adiOlustur();
    });
    if (kitap.topics.isNotEmpty && mounted) await _testSec();
  }

  Future<void> _testSec() async {
    final k = _kitap;
    if (k == null) return;
    final sonuc = await showModalBottomSheet<(String?, int?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TestSecici(kitap: k, konu: _konu, testNo: _testNo),
    );
    if (sonuc == null) return;
    setState(() {
      _konu = sonuc.$1;
      _testNo = sonuc.$2;
      _adiOlustur();
    });
  }

  @override
  void initState() {
    super.initState();
    for (final c in [_correct, _wrong, _blank]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _correct.dispose();
    _wrong.dispose();
    _blank.dispose();
    super.dispose();
  }

  int get _c => parseInt(_correct.text) ?? 0;
  int get _w => parseInt(_wrong.text) ?? 0;
  double get _net => _penalty > 0 ? _c - _w / _penalty : _c.toDouble();

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showInfo(context, 'Testin ya da denemenin adını yazın.');
      return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final ok = await runSafe(
      context,
      () => Db.addTestResult(widget.student.id, widget.me,
          name: name,
          subject: _subject ?? '',
          correct: _c,
          wrong: _w,
          blank: parseInt(_blank.text) ?? 0,
          penalty: _penalty,
          date: _date),
      success: 'Sonuç kaydedildi.',
    );
    if (ok) {
      nav.pop();
    } else if (mounted) {
      setState(() => _busy = false);
    }
  }

  Widget _num(TextEditingController c, String label, Color color) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: color),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: 'Test / Deneme Sonucu',
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _kitapSec,
                icon: const Icon(Icons.library_books_outlined),
                label: Text(_kitap?.title ?? 'Kitap seç',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _kitap == null ? null : _testSec,
                icon: const Icon(Icons.checklist),
                label: Text(
                    _konu != null || _testNo != null
                        ? [
                            if (_konu != null) _konu!,
                            if (_testNo != null) 'Test $_testNo'
                          ].join(' • ')
                        : 'Test seç',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              labelText: 'Adı', hintText: 'Ör. Kesirler Test 3, LGS Deneme 2'),
        ),
        const SizedBox(height: 12),
        SubjectDropdown(
            value: _subject, onChanged: (v) => setState(() => _subject = v)),
        const SizedBox(height: 12),
        Row(children: [
          _num(_correct, 'Doğru', Colors.green),
          const SizedBox(width: 8),
          _num(_wrong, 'Yanlış', Colors.red),
          const SizedBox(width: 8),
          _num(_blank, 'Boş', Colors.grey),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: _penalty,
          decoration: const InputDecoration(labelText: 'Net hesabı'),
          items: const [
            DropdownMenuItem(value: 0, child: Text('Yanlış doğruyu götürmez')),
            DropdownMenuItem(value: 3, child: Text('3 yanlış 1 doğruyu götürür (LGS)')),
            DropdownMenuItem(value: 4, child: Text('4 yanlış 1 doğruyu götürür (YKS)')),
          ],
          onChanged: (v) => setState(() => _penalty = v ?? 0),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text('Tarih: ${fmtDate(_date)}'),
          trailing: const Icon(Icons.edit_calendar),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: today().subtract(const Duration(days: 365)),
              lastDate: today(),
            );
            if (d != null) setState(() => _date = d);
          },
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Net: ${_net.toStringAsFixed(2)}',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _busy ? null : _save,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

/// Öğrencinin test kitaplarından seçim (devam edenler önce).
class _KitapSecici extends StatelessWidget {
  const _KitapSecici({required this.studentId});

  final String studentId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: StreamBuilder<List<TestBook>>(
          stream: Db.testBooks(studentId),
          builder: (context, snap) {
            if (snap.hasError) {
              return EmptyState(
                  icon: Icons.error_outline, text: errorText(snap.error!));
            }
            if (!snap.hasData) return const Loading();
            const sira = {'devam': 0, 'istek': 1, 'bitti': 2};
            final liste = List.of(snap.data!)
              ..sort((a, b) => sira[a.durumu]!.compareTo(sira[b.durumu]!));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Kitap seç',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: liste.isEmpty
                      ? const EmptyState(
                          icon: Icons.library_books_outlined,
                          text: 'Henüz test kitabı eklenmemiş.\n'
                              '"Test Kitapları" sekmesinden kitap ekleyin.')
                      : ListView.builder(
                          itemCount: liste.length,
                          itemBuilder: (context, i) {
                            final k = liste[i];
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text('%${(k.progress * 100).round()}',
                                    style: const TextStyle(fontSize: 11)),
                              ),
                              title: Text(k.title),
                              subtitle: Text([
                                if (k.subject.isNotEmpty) k.subject,
                                if (k.publisher.isNotEmpty) k.publisher,
                                kitapDurumlari[k.durumu] ?? '',
                              ].join(' • ')),
                              onTap: () => Navigator.pop(context, k),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Seçilen kitabın konularından ve test numarasından seçim.
class _TestSecici extends StatefulWidget {
  const _TestSecici({required this.kitap, this.konu, this.testNo});

  final TestBook kitap;
  final String? konu;
  final int? testNo;

  @override
  State<_TestSecici> createState() => _TestSeciciState();
}

class _TestSeciciState extends State<_TestSecici> {
  late String? _konu = widget.konu;
  late final _no =
      TextEditingController(text: widget.testNo == null ? '' : '${widget.testNo}');

  @override
  void dispose() {
    _no.dispose();
    super.dispose();
  }

  void _tamam() => Navigator.pop(
      context, (_konu, int.tryParse(_no.text.trim())));

  @override
  Widget build(BuildContext context) {
    final k = widget.kitap;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(k.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: TextField(
                  controller: _no,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Test numarası (isteğe bağlı)',
                    prefixIcon: Icon(Icons.tag),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: k.topics.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                            'Bu kitaba konu eklenmemiş. Test numarasını yazıp Tamam\'a basın.'),
                      )
                    : ListView(
                        children: [
                          RadioListTile<String?>(
                            value: null,
                            groupValue: _konu,
                            onChanged: (v) => setState(() => _konu = v),
                            title: const Text('Konu seçmeden devam et'),
                          ),
                          for (final t in k.topics)
                            RadioListTile<String?>(
                              value: t.name,
                              groupValue: _konu,
                              onChanged: (v) => setState(() => _konu = v),
                              title: Text(t.name),
                              subtitle: t.hasRange
                                  ? Text('Sayfa ${t.start}–${t.end}'
                                      '${k.isTopicDone(t) ? '  •  tamamlandı' : ''}')
                                  : null,
                              secondary: k.isTopicDone(t)
                                  ? const Icon(Icons.check_circle,
                                      color: Colors.green)
                                  : null,
                            ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  onPressed: _tamam,
                  child: const Text('Tamam'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

