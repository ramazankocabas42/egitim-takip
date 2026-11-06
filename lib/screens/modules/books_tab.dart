import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/db.dart';
import '../../services/kitap_katalog.dart';
import '../../widgets/common.dart';
import '../../widgets/kitap_bulucu.dart';

/// KİTAP OKUMA MODÜLÜ
/// Kitap eklenir; öğrenci her gün "Okudum" deyip kaç sayfa okuduğunu yazar.
class BooksTab extends StatefulWidget {
  const BooksTab({super.key, required this.student, required this.me});

  final Student student;
  final AppUser me;

  @override
  State<BooksTab> createState() => _BooksTabState();
}

class _BooksTabState extends State<BooksTab> {
  late final LiveValue<List<Book>> _books =
      LiveValue(Db.books(widget.student.id));
  late final LiveValue<List<ReadingLog>> _logs =
      LiveValue(Db.readingLogs(widget.student.id));

  @override
  void dispose() {
    _books.dispose();
    _logs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([_books, _logs]),
        builder: (context, _) {
          if (_books.error != null) {
            return EmptyState(
                icon: Icons.error_outline, text: errorText(_books.error!));
          }
          if (_books.loading) return const Loading();
          final books = _books.value!;
          final logs = _logs.value ?? const <ReadingLog>[];
          final reading = books.where((b) => !b.finished).toList();
          final finished = books.where((b) => b.finished).toList();

          final start = today().subtract(const Duration(days: 6));
          final week = logs.where((l) => l.date != null && !l.date!.isBefore(start));
          final weekPages = week.fold<int>(0, (a, l) => a + l.pages);
          final weekMinutes = week.fold<int>(0, (a, l) => a + l.minutes);

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              SizedBox(
                height: 100,
                child: Row(
                  children: [
                    Expanded(
                        child: StatCard(
                            icon: Icons.auto_stories,
                            label: 'Son 7 gün',
                            value: '$weekPages sayfa')),
                    const SizedBox(width: 8),
                    Expanded(
                        child: StatCard(
                            icon: Icons.timer_outlined,
                            label: 'Okuma süresi',
                            value: '$weekMinutes dk',
                            color: Colors.orange)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: StatCard(
                            icon: Icons.emoji_events_outlined,
                            label: 'Biten kitap',
                            value: '${finished.length}',
                            color: Colors.green)),
                  ],
                ),
              ),
              const SectionTitle('Okunan kitaplar'),
              if (reading.isEmpty)
                const EmptyState(
                    icon: Icons.menu_book_outlined,
                    text: 'Şu an okunan kitap yok.\n"Kitap Ekle" ile yeni kitap ekleyin.')
              else
                ...reading.map((b) => _BookCard(
                    student: widget.student, me: widget.me, book: b)),
              if (finished.isNotEmpty) ...[
                const SectionTitle('Bitirilen kitaplar'),
                ...finished.map((b) => _BookCard(
                    student: widget.student, me: widget.me, book: b)),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_books',
        onPressed: () => openSheet<void>(
            context, _AddBookSheet(student: widget.student, me: widget.me)),
        icon: const Icon(Icons.add),
        label: const Text('Kitap Ekle'),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.student, required this.me, required this.book});

  final Student student;
  final AppUser me;
  final Book book;

  @override
  Widget build(BuildContext context) {
    final canDelete = me.role.isAdult || book.createdBy == me.uid;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openSheet<void>(
            context, _BookLogsSheet(student: student, me: me, book: book)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(book.finished ? Icons.emoji_events : Icons.menu_book,
                      color: book.finished ? Colors.amber.shade700 : null),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(book.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        if (book.author.isNotEmpty)
                          Text(book.author,
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'finish') {
                        await runSafe(context,
                            () => Db.setBookFinished(student.id, book, !book.finished));
                      } else if (v == 'delete') {
                        final ok = await confirm(context,
                            title: 'Kitap silinsin mi?',
                            message: book.title,
                            ok: 'Sil',
                            destructive: true);
                        if (!ok || !context.mounted) return;
                        await runSafe(context,
                            () => Db.deleteDoc(student.id, 'books', book.id));
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'finish',
                          child: Text(book.finished
                              ? 'Okunuyor olarak işaretle'
                              : 'Bitti olarak işaretle')),
                      if (canDelete)
                        const PopupMenuItem(value: 'delete', child: Text('Sil')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      value: book.progress,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 6),
                    Text(book.totalPages > 0
                        ? 'Sayfa ${book.currentPage} / ${book.totalPages}  (%${(book.progress * 100).round()})'
                        : 'Okunan: ${book.currentPage} sayfa'),
                    if (!book.finished) ...[
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(46)),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => _ReadDialog(
                              student: student, me: me, book: book),
                        ),
                        icon: const Icon(Icons.check),
                        label: const Text('Bugün Okudum'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadDialog extends StatefulWidget {
  const _ReadDialog({required this.student, required this.me, required this.book});

  final Student student;
  final AppUser me;
  final Book book;

  @override
  State<_ReadDialog> createState() => _ReadDialogState();
}

class _ReadDialogState extends State<_ReadDialog> {
  final _pages = TextEditingController();
  final _minutes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _pages.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pages = parseInt(_pages.text) ?? 0;
    if (pages <= 0) {
      showInfo(context, 'Kaç sayfa okuduğunu yaz.');
      return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final b = widget.book;
    final willFinish = b.totalPages > 0 && b.currentPage + pages >= b.totalPages;
    final ok = await runSafe(
      context,
      () => Db.addReading(widget.student.id, widget.me, b,
          pages: pages, minutes: parseInt(_minutes.text) ?? 0),
      success: willFinish
          ? 'Tebrikler! "${b.title}" kitabını bitirdin 🏆'
          : 'Harika! $pages sayfa kaydedildi 📚',
    );
    if (ok) {
      nav.pop();
    } else if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.book;
    return AlertDialog(
      title: Text(b.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Şu an ${b.currentPage}. sayfadasın'
              '${b.totalPages > 0 ? ' (toplam ${b.totalPages})' : ''}.'),
          const SizedBox(height: 12),
          TextField(
            controller: _pages,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Bugün kaç sayfa okudun?'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _minutes,
            keyboardType: TextInputType.number,
            decoration:
                const InputDecoration(labelText: 'Kaç dakika okudun? (isteğe bağlı)'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Vazgeç')),
        FilledButton(
            onPressed: _busy ? null : _save, child: const Text('Kaydet')),
      ],
    );
  }
}

class _BookLogsSheet extends StatefulWidget {
  const _BookLogsSheet({required this.student, required this.me, required this.book});

  final Student student;
  final AppUser me;
  final Book book;

  @override
  State<_BookLogsSheet> createState() => _BookLogsSheetState();
}

class _BookLogsSheetState extends State<_BookLogsSheet> {
  late final Stream<List<ReadingLog>> _stream =
      Db.readingLogsOfBook(widget.student.id, widget.book.id);

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: widget.book.title,
      children: [
        const Text('Okuma geçmişi'),
        const SizedBox(height: 8),
        StreamBuilder<List<ReadingLog>>(
          stream: _stream,
          builder: (context, snap) {
            if (!snap.hasData) return const Loading();
            final logs = snap.data!;
            if (logs.isEmpty) {
              return const EmptyState(
                  icon: Icons.history, text: 'Henüz okuma kaydı yok.');
            }
            return Column(
              children: logs
                  .map((l) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(child: Text('${l.pages}')),
                        title: Text('${l.pages} sayfa  (s. ${l.fromPage + 1}–${l.toPage})'),
                        subtitle: Text('${fmtDateTime(l.date)}'
                            '${l.minutes > 0 ? ' • ${l.minutes} dk' : ''}'
                            '${l.createdByName.isNotEmpty ? ' • ${l.createdByName}' : ''}'),
                        trailing: widget.me.role.isAdult
                            ? IconButton(
                                tooltip: 'Kaydı sil',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => runSafe(
                                    context,
                                    () => Db.deleteDoc(widget.student.id,
                                        'readingLogs', l.id)),
                              )
                            : null,
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _AddBookSheet extends StatefulWidget {
  const _AddBookSheet({required this.student, required this.me});

  final Student student;
  final AppUser me;

  @override
  State<_AddBookSheet> createState() => _AddBookSheetState();
}

class _AddBookSheetState extends State<_AddBookSheet> {
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _pages = TextEditingController();
  bool _busy = false;
  String _isbn = '';
  String _publisher = '';

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _pages.dispose();
    super.dispose();
  }

  /// Barkoddan / aramadan gelen kitap: formu doldurur, bilgiler tamsa kaydeder.
  void _kitapSecildi(KatalogKitap k) {
    setState(() {
      _isbn = k.isbn;
      _publisher = k.publisher;
      if (k.title.isNotEmpty) _title.text = k.title;
      if (k.author.isNotEmpty) _author.text = k.author;
      if (k.totalPages > 0) _pages.text = '${k.totalPages}';
    });
    if (k.title.isNotEmpty && k.totalPages > 0) {
      _save();
    } else if (k.title.isEmpty) {
      kayitsizKitapUyarisi(context, k.isbn, testKitabi: false);
    } else {
      showInfo(context, 'Sayfa sayısı bulunamadı. Sayfa sayısını yazıp kaydedin.');
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      showInfo(context, 'Kitabın adını yazın.');
      return;
    }
    final author = _author.text.trim();
    final pages = parseInt(_pages.text) ?? 0;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final ok = await runSafe(
      context,
      () => Db.addBook(widget.student.id, widget.me,
          title: title, author: author, totalPages: pages, isbn: _isbn),
      success: 'Kitap eklendi: $title',
    );
    if (ok) {
      KitapKatalog.kaydet(KatalogKitap(
          isbn: _isbn,
          title: title,
          author: author,
          publisher: _publisher,
          totalPages: pages));
      nav.pop();
    } else if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: 'Yeni kitap',
      children: [
        KitapBulucu(onSecildi: _kitapSecildi),
        const SizedBox(height: 16),
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Kitabın adı'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _author,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Yazarı (isteğe bağlı)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pages,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Toplam sayfa sayısı'),
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
