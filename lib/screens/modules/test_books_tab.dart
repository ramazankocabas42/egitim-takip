import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/db.dart';
import '../../services/kitap_katalog.dart';
import '../../widgets/common.dart';
import '../../widgets/kitap_bulucu.dart';
import '../../widgets/kitaplik.dart';

/// TEST KİTABI MODÜLÜ
/// - "Test Kitabı Ekle" ile alınan kitap; konuları ve sayfa aralıklarıyla eklenir.
/// - Öğrenci kitabın içinden çözdüğü sayfaları ve bitirdiği konuları işaretler.
class TestBooksTab extends StatefulWidget {
  const TestBooksTab({super.key, required this.student, required this.me});

  final Student student;
  final AppUser me;

  @override
  State<TestBooksTab> createState() => _TestBooksTabState();
}

class _TestBooksTabState extends State<TestBooksTab> {
  late final LiveValue<List<TestBook>> _books =
      LiveValue(Db.testBooks(widget.student.id));
  String _durum = 'devam';

  @override
  void dispose() {
    _books.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _books,
        builder: (context, _) {
          if (_books.error != null) {
            return EmptyState(
                icon: Icons.error_outline, text: errorText(_books.error!));
          }
          if (_books.loading) return const Loading();
          final books = _books.value!;
          final sayilar = <String, int>{};
          for (final b in books) {
            sayilar[b.durumu] = (sayilar[b.durumu] ?? 0) + 1;
          }
          final secili = books.where((b) => b.durumu == _durum).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              DurumSecici(
                secili: _durum,
                sayilar: sayilar,
                degisti: (d) => setState(() => _durum = d),
              ),
              const SizedBox(height: 8),
              if (secili.isEmpty)
                EmptyState(
                  icon: Icons.library_books_outlined,
                  text: switch (_durum) {
                    'istek' => 'Almayı düşündüğün test kitaplarını buraya ekle.\n'
                        '"Test Kitabı Ekle"de "Henüz almadım"ı seç.',
                    'bitti' => 'Henüz tamamlanan test kitabı yok.',
                    _ => 'Henüz test kitabı yok.\n"Test Kitabı Ekle" butonuyla aldığınız '
                        'kitabı konularıyla birlikte ekleyin.',
                  },
                )
              else
                ...secili.map((b) => _TestBookCard(
                      book: b,
                      onDurum: (d) => runSafe(
                          context,
                          () => Db.setDurum(
                              widget.student.id, 'testBooks', b.id, d)),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => TestBookDetailScreen(
                            student: widget.student,
                            me: widget.me,
                            bookId: b.id),
                      )),
                    )),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_testbooks',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              AddTestBookScreen(student: widget.student, me: widget.me),
        )),
        icon: const Icon(Icons.add),
        label: const Text('Test Kitabı Ekle'),
      ),
    );
  }
}

class _TestBookCard extends StatelessWidget {
  const _TestBookCard(
      {required this.book, required this.onTap, required this.onDurum});

  final TestBook book;
  final VoidCallback onTap;
  final ValueChanged<String> onDurum;

  @override
  Widget build(BuildContext context) {
    final pct = (book.progress * 100).round();
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: CircularProgressIndicator(
                        value: book.progress,
                        strokeWidth: 6,
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    Text('%$pct',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(book.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text([
                      if (book.subject.isNotEmpty) book.subject,
                      if (book.publisher.isNotEmpty) book.publisher,
                    ].join(' • ')),
                    const SizedBox(height: 4),
                    Text(
                      '${book.solvedPages.length}'
                      '${book.totalPages > 0 ? '/${book.totalPages}' : ''} sayfa çözüldü'
                      ' • ${book.doneTopicCount}/${book.topics.length} konu',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => onDurum(v.substring(6)),
                itemBuilder: (_) => durumMenuOgeleri(book.durumu),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Test kitabı detay: Konular + Sayfalar
// ---------------------------------------------------------------------------
class TestBookDetailScreen extends StatefulWidget {
  const TestBookDetailScreen({
    super.key,
    required this.student,
    required this.me,
    required this.bookId,
  });

  final Student student;
  final AppUser me;
  final String bookId;

  @override
  State<TestBookDetailScreen> createState() => _TestBookDetailScreenState();
}

class _TestBookDetailScreenState extends State<TestBookDetailScreen> {
  late final LiveValue<TestBook?> _book =
      LiveValue(Db.testBookStream(widget.student.id, widget.bookId));
  bool _loaded = false;

  String get sid => widget.student.id;

  @override
  void initState() {
    super.initState();
    _book.addListener(_onFirst);
  }

  void _onFirst() {
    if (!_loaded) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _book.removeListener(_onFirst);
    _book.dispose();
    super.dispose();
  }

  Future<void> _togglePage(TestBook b, int page) => runSafe(context,
      () => Db.setPagesSolved(sid, b.id, [page], !b.solvedPages.contains(page)));

  Future<void> _toggleTopic(TestBook b, Topic t) async {
    final done = b.isTopicDone(t);
    if (!done) {
      await runSafe(context, () async {
        await Db.setTopicDone(sid, b.id, t.name, true);
        if (t.hasRange) await Db.setPagesSolved(sid, b.id, t.pages, true);
      }, success: '"${t.name}" konusu bitti 👏');
      return;
    }
    // Bitmiş konunun işaretini kaldır
    final allPagesSolved = t.hasRange && b.solvedInTopic(t) == t.pageCount;
    if (allPagesSolved) {
      final ok = await confirm(context,
          title: 'İşareti kaldır',
          message:
              '"${t.name}" konusunun sayfaları (${t.start}–${t.end}) çözülmüş görünüyor. '
              'Bu sayfaların işaretleri de kaldırılsın mı?',
          ok: 'Kaldır');
      if (!ok || !mounted) return;
      await runSafe(context, () async {
        await Db.setTopicDone(sid, b.id, t.name, false);
        await Db.setPagesSolved(sid, b.id, t.pages, false);
      });
    } else {
      await runSafe(context, () => Db.setTopicDone(sid, b.id, t.name, false));
    }
  }

  Future<void> _addTopic(TestBook b) async {
    final t = await showDialog<Topic>(
        context: context, builder: (_) => const _TopicDialog());
    if (t == null || !mounted) return;
    if (b.topics.any((x) => x.name == t.name)) {
      showInfo(context, 'Bu isimde bir konu zaten var.');
      return;
    }
    final yeni = [...b.topics, t];
    final ok =
        await runSafe(context, () => Db.updateTestBookTopics(sid, b.id, yeni));
    if (ok) _katalogaYaz(b, yeni);
  }

  /// Barkodlu kitabın konuları değişince ortak kataloğu da güncelle.
  void _katalogaYaz(TestBook b, List<Topic> konular) {
    if (b.isbn.isEmpty || konular.isEmpty) return;
    KitapKatalog.kaydet(KatalogKitap(
      isbn: b.isbn,
      title: b.title,
      publisher: b.publisher,
      subject: b.subject,
      totalPages: b.totalPages,
      topics: konular,
    ));
  }

  Future<void> _deleteTopic(TestBook b, Topic t) async {
    final ok = await confirm(context,
        title: 'Konu silinsin mi?', message: t.name, ok: 'Sil', destructive: true);
    if (!ok || !mounted) return;
    final yeni = b.topics.where((x) => x.name != t.name).toList();
    final silindi = await runSafe(
        context, () => Db.updateTestBookTopics(sid, b.id, yeni));
    if (silindi) _katalogaYaz(b, yeni);
  }

  Future<void> _deleteBook(TestBook b) async {
    final ok = await confirm(context,
        title: 'Test kitabı silinsin mi?',
        message: '${b.title} ve tüm işaretlemeleri silinecek.',
        ok: 'Sil',
        destructive: true);
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    final done = await runSafe(context, () => Db.deleteDoc(sid, 'testBooks', b.id));
    if (done) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _book,
      builder: (context, _) {
        if (_book.error != null) {
          return Scaffold(
              appBar: AppBar(),
              body: EmptyState(
                  icon: Icons.error_outline, text: errorText(_book.error!)));
        }
        if (!_loaded) return const Scaffold(body: Loading());
        final b = _book.value;
        if (b == null) {
          return Scaffold(
              appBar: AppBar(),
              body: const EmptyState(
                  icon: Icons.search_off, text: 'Test kitabı bulunamadı.'));
        }
        final canDelete = widget.me.role.isAdult || b.createdBy == widget.me.uid;
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(b.title),
              actions: [
                if (canDelete)
                  IconButton(
                    tooltip: 'Kitabı sil',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteBook(b),
                  ),
              ],
              bottom: TabBar(tabs: [
                Tab(text: 'Konular (${b.doneTopicCount}/${b.topics.length})'),
                Tab(
                    text:
                        'Sayfalar (${b.solvedPages.length}${b.totalPages > 0 ? '/${b.totalPages}' : ''})'),
              ]),
            ),
            body: TabBarView(children: [
              _topicsView(b),
              _pagesView(b),
            ]),
          ),
        );
      },
    );
  }

  Widget _topicsView(TestBook b) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Genel ilerleme: %${(b.progress * 100).round()}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: b.progress,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(5),
                ),
                const SizedBox(height: 8),
                const Text(
                    'Konuyu bitirince yanındaki kutuya dokun. Sayfa aralığı girilmişse '
                    'o sayfalar da çözüldü olarak işaretlenir.'),
              ],
            ),
          ),
        ),
        if (b.topics.isEmpty)
          const EmptyState(
              icon: Icons.list_alt, text: 'Bu kitaba henüz konu eklenmedi.'),
        ...b.topics.map((t) {
          final done = b.isTopicDone(t);
          final solved = b.solvedInTopic(t);
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
              leading: Checkbox(
                value: done,
                onChanged: (_) => _toggleTopic(b, t),
              ),
              title: Text(t.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration: done ? TextDecoration.lineThrough : null,
                  )),
              subtitle: t.hasRange
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sayfa ${t.start}–${t.end} • $solved/${t.pageCount} çözüldü'),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: t.pageCount == 0 ? 0 : solved / t.pageCount,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    )
                  : Text(done ? 'Tamamlandı' : 'Sayfa aralığı girilmedi'),
              onTap: () => _toggleTopic(b, t),
              trailing: widget.me.role.isAdult || b.createdBy == widget.me.uid
                  ? IconButton(
                      tooltip: 'Konuyu sil',
                      icon: const Icon(Icons.close),
                      onPressed: () => _deleteTopic(b, t),
                    )
                  : null,
            ),
          );
        }),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _addTopic(b),
          icon: const Icon(Icons.add),
          label: const Text('Konu ekle'),
        ),
      ],
    );
  }

  Widget _pagesView(TestBook b) {
    if (b.totalPages <= 0) {
      return const EmptyState(
          icon: Icons.grid_off,
          text: 'Bu kitap için toplam sayfa sayısı girilmemiş.\n'
              'Konular sekmesinden konuları işaretleyebilirsiniz.');
    }
    final cs = Theme.of(context).colorScheme;
    // Hangi sayfa hangi konuya ait? (uzun basınca gösterilir)
    String? topicOf(int p) {
      for (final t in b.topics) {
        if (t.hasRange && p >= t.start && p <= t.end) return t.name;
      }
      return null;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Çözdüğün sayfaya dokun, yeşil olsun. Yanlışlıkla işaretlediysen tekrar dokun.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 64,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: b.totalPages,
            itemBuilder: (context, i) {
              final page = i + 1;
              final solved = b.solvedPages.contains(page);
              final topic = topicOf(page);
              return Material(
                color: solved ? Colors.green : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _togglePage(b, page),
                  onLongPress: topic == null
                      ? null
                      : () => showInfo(context, 'Sayfa $page: $topic'),
                  child: Center(
                    child: Text(
                      '$page',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: solved ? Colors.white : cs.onSurface,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TopicDialog extends StatefulWidget {
  const _TopicDialog();

  @override
  State<_TopicDialog> createState() => _TopicDialogState();
}

class _TopicDialogState extends State<_TopicDialog> {
  final _name = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Konu ekle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Konu adı'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _start,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'İlk sayfa'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _end,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Son sayfa'),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            final s = parseInt(_start.text) ?? 0;
            final e = parseInt(_end.text) ?? 0;
            Navigator.pop(
                context, Topic(name: name, start: s, end: e < s ? s : e));
          },
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Test kitabı ekleme ekranı
// ---------------------------------------------------------------------------
class AddTestBookScreen extends StatefulWidget {
  const AddTestBookScreen({super.key, required this.student, required this.me});

  final Student student;
  final AppUser me;

  @override
  State<AddTestBookScreen> createState() => _AddTestBookScreenState();
}

class _TopicRow {
  final name = TextEditingController();
  final start = TextEditingController();
  final end = TextEditingController();

  void dispose() {
    name.dispose();
    start.dispose();
    end.dispose();
  }
}

class _AddTestBookScreenState extends State<AddTestBookScreen> {
  final _title = TextEditingController();
  final _publisher = TextEditingController();
  final _pages = TextEditingController();
  String? _subject;
  final List<_TopicRow> _rows = [_TopicRow()];
  bool _busy = false;
  String _isbn = '';
  bool _istek = false;

  /// Barkoddan / aramadan gelen kitap: formu (konular dahil) doldurur,
  /// bilgiler tamsa hemen kaydeder.
  void _kitapSecildi(KatalogKitap k) {
    setState(() {
      _isbn = k.isbn;
      if (k.title.isNotEmpty) _title.text = k.title;
      if (k.publisher.isNotEmpty) _publisher.text = k.publisher;
      if (subjects.contains(k.subject)) _subject = k.subject;
      if (k.totalPages > 0) _pages.text = '${k.totalPages}';
      if (k.topics.isNotEmpty) {
        final eski = List.of(_rows);
        _rows
          ..clear()
          ..addAll(k.topics.map((t) {
            final r = _TopicRow();
            r.name.text = t.name;
            if (t.start > 0) r.start.text = '${t.start}';
            if (t.end > 0) r.end.text = '${t.end}';
            return r;
          }));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final r in eski) {
            r.dispose();
          }
        });
      }
    });
    if (k.title.isNotEmpty && k.totalPages > 0) {
      _save();
    } else if (k.title.isEmpty) {
      kayitsizKitapUyarisi(context, k.isbn, testKitabi: true);
    } else {
      showInfo(context, 'Sayfa sayısı bulunamadı. Sayfa sayısını yazıp kaydedin.');
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _publisher.dispose();
    _pages.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      showInfo(context, 'Kitabın adını yazın.');
      return;
    }
    final topics = <Topic>[];
    final names = <String>{};
    for (final r in _rows) {
      final n = r.name.text.trim();
      if (n.isEmpty || names.contains(n)) continue;
      names.add(n);
      final s = parseInt(r.start.text) ?? 0;
      final e = parseInt(r.end.text) ?? 0;
      topics.add(Topic(name: n, start: s, end: e < s ? s : e));
    }
    var total = parseInt(_pages.text) ?? 0;
    // Toplam sayfa girilmediyse konuların son sayfasından tahmin et.
    if (total == 0 && topics.any((t) => t.hasRange)) {
      total = topics.map((t) => t.end).reduce((a, b) => a > b ? a : b);
    }
    final publisher = _publisher.text.trim();
    final subject = _subject ?? '';
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final ok = await runSafe(
      context,
      () => Db.addTestBook(widget.student.id, widget.me,
          title: title,
          publisher: publisher,
          subject: subject,
          totalPages: total,
          topics: topics,
          isbn: _isbn,
          durum: _istek ? 'istek' : 'devam'),
      success: 'Test kitabı eklendi: $title',
    );
    if (ok) {
      KitapKatalog.kaydet(KatalogKitap(
          isbn: _isbn,
          title: title,
          publisher: publisher,
          subject: subject,
          totalPages: total,
          topics: topics));
      nav.pop();
    } else if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Kitabı Ekle')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          KitapBulucu(onSecildi: _kitapSecildi),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Kitabın adı',
                hintText: 'Ör. 7. Sınıf Matematik Soru Bankası',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _publisher,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Yayınevi (isteğe bağlı)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          SubjectDropdown(
              value: _subject, onChanged: (v) => setState(() => _subject = v)),
          const SizedBox(height: 12),
          TextField(
            controller: _pages,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Toplam sayfa sayısı',
                helperText: 'Sayfa sayfa işaretleme için gereklidir.',
                border: OutlineInputBorder()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _istek,
            onChanged: (v) => setState(() => _istek = v),
            title: const Text('Henüz almadım'),
            subtitle: const Text('"Almayı düşündüklerim" listesine ekle'),
          ),
          const SectionTitle('Konular'),
          const Text(
              'Kitabın içindekiler sayfasındaki konuları ve sayfa aralıklarını yazın. '
              'Sayfa aralığı boş bırakılabilir.'),
          const SizedBox(height: 8),
          ...List.generate(_rows.length, (i) {
            final r = _rows[i];
            return Padding(
              key: ObjectKey(r),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: TextField(
                      controller: r.name,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                          labelText: '${i + 1}. konu', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: r.start,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'İlk s.', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: r.end,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Son s.', isDense: true),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Satırı sil',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _rows.length == 1
                        ? null
                        : () {
                            final removed = _rows[i];
                            setState(() => _rows.removeAt(i));
                            WidgetsBinding.instance.addPostFrameCallback(
                                (_) => removed.dispose());
                          },
                  ),
                ],
              ),
            );
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _rows.add(_TopicRow())),
              icon: const Icon(Icons.add),
              label: const Text('Konu satırı ekle'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _busy ? null : _save,
            child: const Text('Kitabı Kaydet'),
          ),
        ),
      ),
    );
  }
}
