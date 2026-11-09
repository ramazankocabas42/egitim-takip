import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// AGS + PDR ÖABT hazırlık içeriği: uygulamaya gömülü özgün konu özetleri ve
/// soru bankası (assets/ags_icerik.json) ile depodan her gün yayımlanan yeni
/// denemeler (icerik/ags/...). Sorular özgündür; ÖSYM sorusu kopyalanmaz.
class AgsKonu {
  const AgsKonu(this.ad, this.ozet);
  final String ad;
  final String ozet;
}

class AgsDers {
  const AgsDers({
    required this.id,
    required this.test,
    required this.sinav,
    required this.ad,
    required this.konular,
  });
  final String id; // sozel, sayisal, tarih, cografya, egitim, mevzuat, pdr
  final String test; // ÖSYM test kimliği (osym.dart)
  final String sinav; // AGS | OABT
  final String ad;
  final List<AgsKonu> konular;
}

class AgsSoru {
  const AgsSoru({
    required this.id,
    required this.ders,
    required this.konu,
    required this.soru,
    required this.secenekler,
    required this.cevap,
    required this.aciklama,
  });
  final String id;
  final String ders;
  final String konu;
  final String soru;
  final List<String> secenekler;
  final int cevap;
  final String aciklama;

  static AgsSoru? oku(dynamic m) {
    if (m is! Map) return null;
    final s = m['secenekler'];
    final c = m['cevap'];
    if (s is! List || s.length < 2 || c is! num) return null;
    final secenekler = s.map((e) => e.toString()).toList();
    if (c < 0 || c >= secenekler.length) return null;
    return AgsSoru(
      id: '${m['id'] ?? ''}',
      ders: '${m['ders'] ?? ''}',
      konu: '${m['konu'] ?? ''}',
      soru: '${m['soru'] ?? ''}',
      secenekler: secenekler,
      cevap: c.toInt(),
      aciklama: '${m['aciklama'] ?? ''}',
    );
  }
}

class AgsDeneme {
  const AgsDeneme({required this.tarih, required this.ad, required this.sorular, this.cevrimdisi = false});
  final String tarih; // YYYY-MM-DD
  final String ad;
  final List<AgsSoru> sorular;
  final bool cevrimdisi;

  /// Sonuç kaydında kullanılan ad; çözülüp çözülmediği buna göre anlaşılır.
  String get kayitAdi => 'Günlük deneme $tarih';
}

class AgsDenemeBilgi {
  const AgsDenemeBilgi(this.tarih, this.dosya, this.soru);
  final String tarih;
  final String dosya;
  final int soru;
}

class AgsIcerik {
  AgsIcerik._(this.dersler, this.sorular);

  final List<AgsDers> dersler;
  final List<AgsSoru> sorular;

  static const _kok = 'https://raw.githubusercontent.com/ramazankocabas42/egitim-takip/main/icerik/ags/';
  static AgsIcerik? _onbellek;
  static List<AgsDenemeBilgi>? _liste;
  static final _denemeler = <String, AgsDeneme>{};

  AgsDers? ders(String id) {
    for (final d in dersler) {
      if (d.id == id) return d;
    }
    return null;
  }

  List<AgsSoru> dersSorulari(String id) => sorular.where((s) => s.ders == id).toList();

  static Future<AgsIcerik> yukle() async {
    final o = _onbellek;
    if (o != null) return o;
    final m = jsonDecode(await rootBundle.loadString('assets/ags_icerik.json')) as Map;
    final dersler = <AgsDers>[
      for (final d in (m['dersler'] as List))
        AgsDers(
          id: '${d['id']}',
          test: '${d['test']}',
          sinav: '${d['sinav']}',
          ad: '${d['ad']}',
          konular: [for (final k in (d['konular'] as List)) AgsKonu('${k['ad']}', '${k['ozet']}')],
        ),
    ];
    final sorular = [for (final s in (m['sorular'] as List)) AgsSoru.oku(s)].whereType<AgsSoru>().toList();
    return _onbellek = AgsIcerik._(dersler, sorular);
  }

  static Future<dynamic> _getir(String yol) async {
    // Önbelleği atlamak için gün damgası eklenir.
    final g = DateTime.now();
    final r = await http
        .get(Uri.parse('$_kok$yol?g=${g.year}${g.month}${g.day}${g.hour}'))
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw Exception('İçerik alınamadı (${r.statusCode})');
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  /// Yayımlanmış günlük denemeler (yeniden eskiye).
  static Future<List<AgsDenemeBilgi>> denemeListesi({bool yenile = false}) async {
    if (_liste != null && !yenile) return _liste!;
    final m = await _getir('index.json');
    final l = <AgsDenemeBilgi>[
      for (final d in ((m is Map ? m['denemeler'] : null) as List? ?? const []))
        if (d is Map && d['tarih'] != null && d['dosya'] != null)
          AgsDenemeBilgi('${d['tarih']}', '${d['dosya']}', (d['soru'] as num?)?.toInt() ?? 0),
    ]..sort((a, b) => b.tarih.compareTo(a.tarih));
    return _liste = l;
  }

  static Future<AgsDeneme> deneme(AgsDenemeBilgi b) async {
    final o = _denemeler[b.dosya];
    if (o != null) return o;
    final m = await _getir(b.dosya) as Map;
    final d = AgsDeneme(
      tarih: '${m['tarih'] ?? b.tarih}',
      ad: '${m['ad'] ?? 'Günlük deneme'}',
      sorular: [for (final s in (m['sorular'] as List? ?? const [])) AgsSoru.oku(s)].whereType<AgsSoru>().toList(),
    );
    return _denemeler[b.dosya] = d;
  }

  static String bugun() {
    final g = DateTime.now();
    return '${g.year}-${g.month.toString().padLeft(2, '0')}-${g.day.toString().padLeft(2, '0')}';
  }

  /// İnternet yoksa soru bankasından güne göre sabit 20 soruluk deneme.
  AgsDeneme cevrimdisiDeneme(String tarih) {
    final r = Random(tarih.hashCode);
    const dagilim = {'sozel': 3, 'sayisal': 3, 'tarih': 2, 'cografya': 2, 'egitim': 5, 'mevzuat': 2, 'pdr': 3};
    final secilen = <AgsSoru>[];
    for (final e in dagilim.entries) {
      final l = dersSorulari(e.key)..shuffle(r);
      secilen.addAll(l.take(e.value));
    }
    return AgsDeneme(tarih: tarih, ad: 'Soru bankasından deneme', sorular: secilen, cevrimdisi: true);
  }
}
