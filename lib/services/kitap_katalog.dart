import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models.dart';

/// Barkoddan ya da addan bulunan kitap bilgisi.
class KatalogKitap {
  KatalogKitap({
    this.isbn = '',
    required this.title,
    this.author = '',
    this.publisher = '',
    this.subject = '',
    this.totalPages = 0,
    this.topics = const [],
    this.kaynak = 'katalog',
  });

  final String isbn;
  final String title;
  final String author;
  final String publisher;
  final String subject;
  final int totalPages;
  final List<Topic> topics;

  /// 'katalog' (uygulamanın ortak kataloğu), 'google' ya da 'openlibrary'
  final String kaynak;

  String get altBaslik => [
        if (publisher.isNotEmpty) publisher,
        if (author.isNotEmpty) author,
        if (totalPages > 0) '$totalPages sayfa',
        if (topics.isNotEmpty) '${topics.length} konu',
      ].join(' • ');

  factory KatalogKitap.fromMap(Map<String, dynamic> m) => KatalogKitap(
        isbn: (m['isbn'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        author: (m['author'] ?? '').toString(),
        publisher: (m['publisher'] ?? '').toString(),
        subject: (m['subject'] ?? '').toString(),
        totalPages: m['totalPages'] is num ? (m['totalPages'] as num).toInt() : 0,
        topics: m['topics'] is List
            ? (m['topics'] as List)
                .whereType<Map>()
                .map(Topic.fromMap)
                .toList()
            : const [],
      );
}

/// Kitap kataloğu: barkod (ISBN) ya da ad/yayınevi ile kitap bulur.
///
/// Sırasıyla bakılan yerler:
/// 1. Uygulamanın ortak kataloğu (Firestore `kitapKatalog`): Bir kullanıcının
///    kaydettiği kitap (sayfa sayısı, test kitabı konuları dahil) sonraki
///    herkese hazır gelir.
/// 2. Google Books
/// 3. Open Library
class KitapKatalog {
  KitapKatalog._();

  static final CollectionReference<Map<String, dynamic>> _koleksiyon =
      FirebaseFirestore.instance.collection('kitapKatalog');

  static const _zamanAsimi = Duration(seconds: 8);

  // -------------------------------------------------------------------------
  // ISBN
  // -------------------------------------------------------------------------

  /// Barkoddan okunan değeri 13 haneli ISBN'e çevirir; ISBN değilse null.
  static String? isbnTemizle(String ham) {
    final s = ham.toUpperCase().replaceAll(RegExp(r'[^0-9X]'), '');
    if (s.length == 13 &&
        (s.startsWith('978') || s.startsWith('979')) &&
        _isbn13Gecerli(s)) {
      return s;
    }
    if (s.length == 10 && _isbn10Gecerli(s)) {
      final govde = '978${s.substring(0, 9)}';
      return govde + _isbn13Kontrol(govde).toString();
    }
    return null;
  }

  static int _isbn13Kontrol(String ilk12) {
    var t = 0;
    for (var i = 0; i < 12; i++) {
      t += int.parse(ilk12[i]) * (i.isEven ? 1 : 3);
    }
    return (10 - t % 10) % 10;
  }

  static bool _isbn13Gecerli(String s) =>
      RegExp(r'^\d{13}$').hasMatch(s) &&
      _isbn13Kontrol(s.substring(0, 12)) == int.parse(s[12]);

  static bool _isbn10Gecerli(String s) {
    if (!RegExp(r'^\d{9}[\dX]$').hasMatch(s)) return false;
    var t = 0;
    for (var i = 0; i < 10; i++) {
      final d = s[i] == 'X' ? 10 : int.parse(s[i]);
      t += d * (10 - i);
    }
    return t % 11 == 0;
  }

  // -------------------------------------------------------------------------
  // Arama
  // -------------------------------------------------------------------------

  /// Barkodla kitap bulur. Hiçbir yerde yoksa null döner.
  static Future<KatalogKitap?> isbnIleBul(String isbn) async {
    KatalogKitap? katalog;
    try {
      final d = await _koleksiyon.doc(isbn).get().timeout(_zamanAsimi);
      if (d.exists) katalog = KatalogKitap.fromMap(d.data()!);
    } catch (e) {
      debugPrint('Katalog okunamadı: $e');
    }
    // Katalogdaki kayıt eksiksizse dışarıya hiç sorma.
    if (katalog != null && katalog.title.isNotEmpty && katalog.totalPages > 0) {
      return katalog;
    }

    final google = await _googleIsbn(isbn);
    final ol = (google == null || google.totalPages == 0 || google.publisher.isEmpty)
        ? await _openLibraryIsbn(isbn)
        : null;

    final adaylar = [katalog, google, ol].whereType<KatalogKitap>().toList();
    if (adaylar.isEmpty) return null;
    String ilk(String Function(KatalogKitap) f) =>
        adaylar.map(f).firstWhere((v) => v.isNotEmpty, orElse: () => '');
    return KatalogKitap(
      isbn: isbn,
      title: ilk((k) => k.title),
      author: ilk((k) => k.author),
      publisher: ilk((k) => k.publisher),
      subject: katalog?.subject ?? '',
      totalPages: adaylar
          .map((k) => k.totalPages)
          .firstWhere((p) => p > 0, orElse: () => 0),
      topics: katalog?.topics ?? const [],
      kaynak: katalog != null ? 'katalog' : (google != null ? 'google' : 'openlibrary'),
    );
  }

  /// Ad, yayınevi, yazar ya da ISBN ile arar.
  static Future<List<KatalogKitap>> ara(String sorgu) async {
    final q = sorgu.trim();
    final isbn = isbnTemizle(q);
    if (isbn != null) {
      final k = await isbnIleBul(isbn);
      return k == null ? const [] : [k];
    }
    final kelimeler = kelimelereAyir(q);
    if (!kelimeler.any((w) => w.length >= 2)) return const [];

    final sonuc = await Future.wait([
      _katalogAra(kelimeler),
      _googleAra(q),
    ]);
    final katalog = sonuc[0];
    final gorulen = katalog.map((k) => k.isbn).where((i) => i.isNotEmpty).toSet();
    return [
      ...katalog,
      ...sonuc[1].where((k) => k.isbn.isEmpty || !gorulen.contains(k.isbn)),
    ];
  }

  static Future<List<KatalogKitap>> _katalogAra(List<String> kelimeler) async {
    try {
      final s = await _koleksiyon
          .where('anahtarlar',
              arrayContains: _kisalt(kelimeler
                  .reduce((a, b) => b.length > a.length ? b : a)))
          .limit(30)
          .get()
          .timeout(_zamanAsimi);
      final liste = <KatalogKitap>[];
      for (final d in s.docs) {
        final k = KatalogKitap.fromMap(d.data());
        final metin =
            kelimelereAyir('${k.title} ${k.publisher} ${k.author}');
        final hepsi = kelimeler
            .every((w) => metin.any((m) => m.startsWith(w)));
        if (hepsi) liste.add(k);
      }
      return liste;
    } catch (e) {
      debugPrint('Katalog araması yapılamadı: $e');
      return const [];
    }
  }

  // -------------------------------------------------------------------------
  // Kaydetme
  // -------------------------------------------------------------------------

  /// Kaydedilen kitabı ortak kataloğa ekler/günceller. Boş alanlar mevcut
  /// bilgiyi silmez. Hata olursa sessizce geçer (kitap kaydı yine yapılmıştır).
  static Future<void> kaydet(KatalogKitap k) async {
    if (k.title.trim().isEmpty) return;
    try {
      final id = k.isbn.isNotEmpty
          ? k.isbn
          : 'ad_${_ozet(kelimelereAyir('${k.title} ${k.publisher}').join(' '))}';
      final veri = <String, dynamic>{
        'title': k.title.trim(),
        'anahtarlar': _anahtarlar('${k.title} ${k.publisher} ${k.author}'),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
        'updatedAt': FieldValue.serverTimestamp(),
        if (k.isbn.isNotEmpty) 'isbn': k.isbn,
        if (k.author.trim().isNotEmpty) 'author': k.author.trim(),
        if (k.publisher.trim().isNotEmpty) 'publisher': k.publisher.trim(),
        if (k.subject.isNotEmpty) 'subject': k.subject,
        if (k.totalPages > 0) 'totalPages': k.totalPages,
        if (k.topics.isNotEmpty) 'topics': k.topics.map((t) => t.toMap()).toList(),
      };
      await _koleksiyon.doc(id).set(veri, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Kataloğa yazılamadı: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Dış kaynaklar
  // -------------------------------------------------------------------------

  static Future<Map<String, dynamic>?> _json(Uri uri) async {
    try {
      final r = await http.get(uri).timeout(_zamanAsimi);
      if (r.statusCode != 200) return null;
      final v = jsonDecode(utf8.decode(r.bodyBytes));
      return v is Map<String, dynamic> ? v : null;
    } catch (e) {
      debugPrint('İstek başarısız ($uri): $e');
      return null;
    }
  }

  static KatalogKitap? _googleKitap(dynamic item, {String isbn = ''}) {
    if (item is! Map) return null;
    final v = item['volumeInfo'];
    if (v is! Map) return null;
    var baslik = (v['title'] ?? '').toString();
    final alt = (v['subtitle'] ?? '').toString();
    if (alt.isNotEmpty) baslik = '$baslik - $alt';
    if (baslik.isEmpty) return null;
    var bulunanIsbn = isbn;
    if (bulunanIsbn.isEmpty && v['industryIdentifiers'] is List) {
      for (final i in v['industryIdentifiers'] as List) {
        if (i is Map && i['type'] == 'ISBN_13') {
          bulunanIsbn = isbnTemizle(i['identifier'].toString()) ?? '';
        }
      }
    }
    return KatalogKitap(
      isbn: bulunanIsbn,
      title: baslik,
      author: v['authors'] is List ? (v['authors'] as List).join(', ') : '',
      publisher: (v['publisher'] ?? '').toString(),
      totalPages: v['pageCount'] is num ? (v['pageCount'] as num).toInt() : 0,
      kaynak: 'google',
    );
  }

  static Future<KatalogKitap?> _googleIsbn(String isbn) async {
    final j = await _json(Uri.https(
        'www.googleapis.com', '/books/v1/volumes', {'q': 'isbn:$isbn'}));
    final items = j?['items'];
    if (items is! List || items.isEmpty) return null;
    return _googleKitap(items.first, isbn: isbn);
  }

  static Future<List<KatalogKitap>> _googleAra(String q) async {
    final j = await _json(Uri.https('www.googleapis.com', '/books/v1/volumes',
        {'q': q, 'maxResults': '10', 'printType': 'books'}));
    final items = j?['items'];
    if (items is! List) return const [];
    return items.map((i) => _googleKitap(i)).whereType<KatalogKitap>().toList();
  }

  static Future<KatalogKitap?> _openLibraryIsbn(String isbn) async {
    final j = await _json(Uri.https('openlibrary.org', '/api/books', {
      'bibkeys': 'ISBN:$isbn',
      'format': 'json',
      'jscmd': 'data',
    }));
    final v = j?['ISBN:$isbn'];
    if (v is! Map) return null;
    String adlar(dynamic l) => l is List
        ? l.whereType<Map>().map((m) => (m['name'] ?? '').toString()).join(', ')
        : '';
    final baslik = (v['title'] ?? '').toString();
    if (baslik.isEmpty) return null;
    return KatalogKitap(
      isbn: isbn,
      title: baslik,
      author: adlar(v['authors']),
      publisher: adlar(v['publishers']),
      totalPages: v['number_of_pages'] is num
          ? (v['number_of_pages'] as num).toInt()
          : 0,
      kaynak: 'openlibrary',
    );
  }

  // -------------------------------------------------------------------------
  // Metin yardımcıları
  // -------------------------------------------------------------------------

  /// Türkçe karakterleri sadeleştirip küçük harfli kelimelere ayırır.
  /// ("Fen Bilimleri" ve "fen bilimleri", "Işık" ve "isik" aynı sayılır.)
  static List<String> kelimelereAyir(String s) {
    const harita = {
      'I': 'ı', 'İ': 'i', 'ç': 'c', 'Ç': 'c', 'ğ': 'g', 'Ğ': 'g',
      'ı': 'i', 'ö': 'o', 'Ö': 'o', 'ş': 's', 'Ş': 's', 'ü': 'u', 'Ü': 'u',
      'â': 'a', 'î': 'i', 'û': 'u',
    };
    final b = StringBuffer();
    for (final c in s.split('')) {
      var h = harita[c] ?? c;
      h = harita[h] ?? h; // 'I' -> 'ı' -> 'i'
      b.write(h.toLowerCase());
    }
    return b
        .toString()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  static const _enUzunAnahtar = 15;

  static String _kisalt(String w) =>
      w.length > _enUzunAnahtar ? w.substring(0, _enUzunAnahtar) : w;

  static List<String> _anahtarlar(String metin) {
    final set = <String>{};
    for (final w in kelimelereAyir(metin)) {
      for (var n = 2; n <= w.length && n <= _enUzunAnahtar; n++) {
        set.add(w.substring(0, n));
      }
      if (w.length == 1) set.add(w);
      if (set.length >= 190) break;
    }
    return set.take(190).toList();
  }

  static String _ozet(String s) {
    var h = 0x811c9dc5;
    for (final c in utf8.encode(s)) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }
}
