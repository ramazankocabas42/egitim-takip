import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'kitap_katalog.dart';

/// e-Okul VBS ekran görüntüsünden okunan bilgiler.
class EkranSonucu {
  final sinavlar = <OkunanSinav>[];
  final yilSonlari = <OkunanYilSonu>[];
  final notlar = <OkunanNot>[];

  bool get bos => sinavlar.isEmpty && yilSonlari.isEmpty && notlar.isEmpty;
  int get adet => sinavlar.length + yilSonlari.length + notlar.length;

  /// Başka bir sonucu tekrarsız ekler (aynı not için yenisi geçerli olur).
  void ekle(EkranSonucu d) {
    for (final x in d.sinavlar) {
      if (!sinavlar.any((y) => y.ders == x.ders && y.tarih == x.tarih)) sinavlar.add(x);
    }
    for (final x in d.yilSonlari) {
      yilSonlari.removeWhere((y) => y.yil == x.yil);
      yilSonlari.add(x);
    }
    yilSonlari.sort((a, b) => a.yil.compareTo(b.yil));
    for (final x in d.notlar) {
      notlar.removeWhere((y) => y.ayni(x));
      notlar.add(x);
    }
  }
}

class OkunanSinav {
  OkunanSinav(this.ders, this.tarih);
  final String ders;
  final DateTime tarih;
}

class OkunanYilSonu {
  OkunanYilSonu(this.yil, this.sinif, this.not);
  final String yil;
  final String sinif;
  final double not;
}

class OkunanNot {
  OkunanNot(this.ders, this.tur, this.sira, this.not, [this.donem]);
  final String ders;
  final String tur; // yazili | performans | proje
  final int sira;
  final double not;
  final int? donem; // sayfada belirtilmişse

  bool ayni(OkunanNot o) =>
      o.ders == ders && o.tur == tur && o.sira == sira && o.donem == donem;
}

class _Satir {
  _Satir(this.metin, this.kutu);
  final String metin;
  final Rect kutu;
  double get y => kutu.center.dy;
}

const _aylar = {
  'ocak': 1,
  'subat': 2,
  'mart': 3,
  'nisan': 4,
  'mayis': 5,
  'haziran': 6,
  'temmuz': 7,
  'agustos': 8,
  'eylul': 9,
  'ekim': 10,
  'kasim': 11,
  'aralik': 12,
};

/// OCR'dan gelen ders adını uygulamadaki ders adına çevirir; ders değilse null.
String? dersAdiBul(String metin) {
  final k = KitapKatalog.kelimelereAyir(metin).join(' ');
  if (k.isEmpty) return null;
  if (k.contains('inkilap') || k.contains('ataturkculuk')) return 'T.C. İnkılap Tarihi';
  if (k.contains('din kulturu') || k.startsWith('din ')) return 'Din Kültürü';
  if (k.contains('turkce')) return 'Türkçe';
  if (k.contains('matematik')) return 'Matematik';
  if (k.contains('fen bilimleri')) return 'Fen Bilimleri';
  if (k.contains('ingilizce') || k.contains('yabanci dil')) return 'İngilizce';
  if (k.contains('beden egitimi')) return 'Beden Eğitimi ve Spor';
  if (k.contains('teknoloji ve tasarim') && k.contains('muzik')) {
    return 'Müzik / Teknoloji ve Tasarım';
  }
  if (k.contains('teknoloji ve tasarim')) return 'Teknoloji ve Tasarım';
  if (k.contains('muzik')) return 'Müzik';
  if (k.contains('gorsel sanatlar')) return 'Görsel Sanatlar';
  if (k.contains('bilisim')) return 'Bilişim Teknolojileri';
  if (k.contains('rehberlik')) return 'Rehberlik';
  if (k.contains('sosyal bilgiler')) return 'Sosyal Bilgiler';
  if (k.contains('peygamberimizin') || k.contains('kuran')) return 'Seçmeli Din';
  if (k.contains('matematik uygulamalari')) return 'Matematik Uygulamaları';
  return null;
}

/// Ekran görüntülerindeki yazıları okur ve ayrıştırır (cihaz üzerinde çalışır).
class EkranOkuyucu {
  EkranOkuyucu._();

  static Future<EkranSonucu> oku(List<String> dosyalar) async {
    final tanima = TextRecognizer(script: TextRecognitionScript.latin);
    final sonuc = EkranSonucu();
    try {
      for (final yol in dosyalar) {
        final metin = await tanima.processImage(InputImage.fromFilePath(yol));
        final satirlar = <_Satir>[
          for (final b in metin.blocks)
            for (final l in b.lines)
              if (l.text.trim().isNotEmpty) _Satir(l.text.trim(), l.boundingBox),
        ]..sort((a, b) => a.y.compareTo(b.y));
        _sinavTarihleri(satirlar, sonuc);
        _yilSonlari(satirlar, sonuc);
        _notlar(satirlar, sonuc);
      }
    } finally {
      await tanima.close();
    }
    return sonuc;
  }

  static final _tarihRe = RegExp(r'(\d{1,2})\s*([A-Za-zÇĞİÖŞÜçğıöşü]+)\s*(20\d\d)');
  static final _sayiTarihRe = RegExp(r'(?<!\d)(\d{1,2})[./](\d{1,2})[./](20\d\d)(?!\d)');

  static DateTime? _tarih(String s) {
    final n = _sayiTarihRe.firstMatch(s);
    if (n != null) {
      final g = int.parse(n.group(1)!), a = int.parse(n.group(2)!);
      if (g >= 1 && g <= 31 && a >= 1 && a <= 12) {
        return DateTime(int.parse(n.group(3)!), a, g);
      }
    }
    final m = _tarihRe.firstMatch(s);
    if (m == null) return null;
    final ay = _aylar[KitapKatalog.kelimelereAyir(m.group(2)!).join()];
    if (ay == null) return null;
    final g = int.parse(m.group(1)!);
    if (g < 1 || g > 31) return null;
    return DateTime(int.parse(m.group(3)!), ay, g);
  }

  /// "DİN KÜLTÜRÜ VE AHLAK BİLGİSİ" satırının hemen altındaki
  /// "13 Kasım 2026 Cuma" satırı -> sınav.
  static void _sinavTarihleri(List<_Satir> s, EkranSonucu out) {
    for (var i = 0; i < s.length; i++) {
      final t = _tarih(s[i].metin);
      if (t == null) continue;
      // Üstteki en yakın ders adı satırı
      for (var j = i - 1; j >= 0 && j >= i - 3; j--) {
        if (_tarih(s[j].metin) != null) break;
        final ders = dersAdiBul(s[j].metin);
        if (ders != null) {
          if (!out.sinavlar.any((x) => x.ders == ders && x.tarih == t)) {
            out.sinavlar.add(OkunanSinav(ders, t));
          }
          break;
        }
      }
    }
  }

  /// "2022-2023   4. Sınıf   Yıl Sonu Notu 96,4445" satırları.
  static void _yilSonlari(List<_Satir> s, EkranSonucu out) {
    final yilRe = RegExp(r'(20\d\d)\s*[-–]\s*(20\d\d)');
    final sinifRe = RegExp(r'(\d{1,2})\s*\.\s*S[ıiIİ1l]n[ıiIİ1l]f', caseSensitive: false);
    final notRe = RegExp(r'^(\d{2,3})[,.](\d{1,4})$');
    final yillar = s.where((x) => yilRe.hasMatch(x.metin)).toList();
    if (yillar.isEmpty) return;
    final siniflar = s.where((x) => sinifRe.hasMatch(x.metin)).toList();
    final notlar = s.where((x) => notRe.hasMatch(x.metin.replaceAll(' ', ''))).toList();
    for (final y in yillar) {
      final ym = yilRe.firstMatch(y.metin)!;
      final yil = '${ym.group(1)}-${ym.group(2)}';
      // Aynı satırda (dikeyde en yakın) sınıf ve not
      _Satir? enYakin(List<_Satir> l) {
        _Satir? b;
        for (final x in l) {
          final fark = (x.y - y.y).abs();
          if (fark > y.kutu.height * 3) continue;
          if (b == null || fark < (b.y - y.y).abs()) b = x;
        }
        return b;
      }

      final sn = enYakin(siniflar);
      final nt = enYakin(notlar);
      if (nt == null) continue;
      final notM = notRe.firstMatch(nt.metin.replaceAll(' ', ''))!;
      final deger = double.tryParse('${notM.group(1)}.${notM.group(2)}');
      if (deger == null || deger > 100) continue;
      final sinif = sn == null ? '' : '${sinifRe.firstMatch(sn.metin)!.group(1)}. Sınıf';
      if (!out.yilSonlari.any((x) => x.yil == yil)) {
        out.yilSonlari.add(OkunanYilSonu(yil, sinif, deger));
      }
    }
  }

  /// Not Bilgileri ekranı: ders başlığı ve altındaki "1. Sınav 85",
  /// "Performans 1  90" gibi satırlar ya da ders adıyla aynı satırdaki notlar.
  static void _notlar(List<_Satir> s, EkranSonucu out) {
    // Yakın yükseklikteki satırları tek satır yap (soldan sağa).
    final satirlar = <List<_Satir>>[];
    for (final x in s) {
      if (satirlar.isNotEmpty) {
        final son = satirlar.last;
        final ort = son.map((e) => e.y).reduce((a, b) => a + b) / son.length;
        if ((x.y - ort).abs() < x.kutu.height * 0.6) {
          son.add(x);
          continue;
        }
      }
      satirlar.add([x]);
    }
    final metinler = satirlar
        .map((r) => (List.of(r)..sort((a, b) => a.kutu.left.compareTo(b.kutu.left)))
            .map((e) => e.metin)
            .join(' '))
        .toList();

    final sayiRe = RegExp(r'(?<![\d.,])(\d{1,3})(?:[.,](\d{1,2}))?(?![\d.,])');
    String? ders;
    final sayac = <String, int>{};
    for (final m in metinler) {
      if (_tarih(m) != null) continue;
      if (RegExp(r'20\d\d\s*[-–]\s*20\d\d').hasMatch(m)) continue;
      final d = dersAdiBul(m);
      final kucuk = KitapKatalog.kelimelereAyir(m).join(' ');
      final tur = kucuk.contains('performans')
          ? 'performans'
          : (kucuk.contains('proje') ? 'proje' : 'yazili');

      // Satırdaki 0-100 arası sayılar (sıra numaraları "1." hariç)
      final temiz = m.replaceAll(RegExp(r'\b\d\s*\.\s*(?=[A-Za-zÇĞİÖŞÜçğıöşü])'), '');
      final sayilar = <double>[];
      for (final x in sayiRe.allMatches(temiz)) {
        final v = double.tryParse('${x.group(1)}.${x.group(2) ?? '0'}');
        if (v != null && v >= 0 && v <= 100) sayilar.add(v);
      }

      if (d != null) {
        ders = d;
        // Ders adıyla aynı satırda notlar: hepsi sırayla yazılı sayılır.
        for (final v in sayilar) {
          final k = '$d|yazili';
          sayac[k] = (sayac[k] ?? 0) + 1;
          out.notlar.add(OkunanNot(d, 'yazili', sayac[k]!, v));
        }
        continue;
      }
      if (ders == null || sayilar.isEmpty) continue;
      final siraM = RegExp(r'(\d)\s*\.').firstMatch(m);
      final k = '$ders|$tur';
      final sira = siraM != null ? int.parse(siraM.group(1)!) : (sayac[k] ?? 0) + 1;
      sayac[k] = sira;
      out.notlar.add(OkunanNot(ders, tur, sira, sayilar.last));
    }
  }

  // -------------------------------------------------------------------------
  // e-Okul web sayfası (uygulama içi tarayıcı) metninden ayrıştırma.
  // Her satır, tablo satırıysa hücreleri; değilse tek elemanlı listedir.
  // -------------------------------------------------------------------------
  static EkranSonucu metinOku(List<List<String>> satirlar) {
    final out = EkranSonucu();
    final rows = <List<String>>[
      for (final r in satirlar)
        if (r.any((c) => c.trim().isNotEmpty)) [for (final c in r) c.trim()],
    ];
    _metinSinavlar(rows, out);
    _metinYilSonlari(rows, out);
    _metinNotTablosu(rows, out);
    if (out.notlar.isEmpty) _metinNotSatirlari(rows, out);
    return out;
  }

  static String _katla(String s) => KitapKatalog.kelimelereAyir(s).join(' ');

  static double? _notDegeri(String c) {
    final m = RegExp(r'^(\d{1,3})(?:[.,](\d{1,4}))?$').firstMatch(c.trim());
    if (m == null) return null;
    final v = double.tryParse('${m.group(1)}.${m.group(2) ?? '0'}');
    return (v != null && v >= 0 && v <= 100) ? v : null;
  }

  /// Ders adı ile tarih aynı satırda ya da ders adı bir üst satırda.
  static void _metinSinavlar(List<List<String>> rows, EkranSonucu out) {
    void ekle(String ders, DateTime t) {
      if (!out.sinavlar.any((x) => x.ders == ders && x.tarih == t)) {
        out.sinavlar.add(OkunanSinav(ders, t));
      }
    }

    for (var i = 0; i < rows.length; i++) {
      final metin = rows[i].join(' ');
      final t = _tarih(metin);
      if (t == null) continue;
      String? ders;
      for (final c in rows[i]) {
        if (_tarih(c) != null && c.length < 30) continue;
        ders = dersAdiBul(c);
        if (ders != null) break;
      }
      if (ders == null) {
        for (var j = i - 1; j >= 0 && j >= i - 3; j--) {
          final ust = rows[j].join(' ');
          if (_tarih(ust) != null) break;
          ders = dersAdiBul(ust);
          if (ders != null) break;
        }
      }
      if (ders != null) ekle(ders, t);
    }
  }

  /// "2022-2023 | 4. Sınıf | 96,4445" (aynı satırda ya da alt alta).
  static void _metinYilSonlari(List<List<String>> rows, EkranSonucu out) {
    final yilRe = RegExp(r'(20\d\d)\s*[-–/]\s*(20\d\d)');
    final sinifRe = RegExp(r'(\d{1,2})\s*\.?\s*S[ıiIİ]n[ıiIİ]f', caseSensitive: false);
    final ondalikRe = RegExp(r'(?<![\d.,])(\d{2,3})[,.](\d{2,4})(?![\d.,])');
    for (var i = 0; i < rows.length; i++) {
      final metin = rows[i].join(' ');
      final ym = yilRe.firstMatch(metin);
      if (ym == null) continue;
      // Yıl satırı + en fazla 3 alt satır (yeni bir yıl gelene kadar)
      final parca = StringBuffer(metin.replaceFirst(ym.group(0)!, ' '));
      for (var j = i + 1; j < rows.length && j <= i + 3; j++) {
        final alt = rows[j].join(' ');
        if (yilRe.hasMatch(alt)) break;
        parca.write(' $alt');
      }
      final p = parca.toString();
      double? not;
      for (final m in ondalikRe.allMatches(p)) {
        final v = double.tryParse('${m.group(1)}.${m.group(2)}');
        if (v != null && v <= 100) {
          not = v;
          break;
        }
      }
      if (not == null) continue;
      final sm = sinifRe.firstMatch(p);
      final yil = '${ym.group(1)}-${ym.group(2)}';
      out.yilSonlari.removeWhere((x) => x.yil == yil);
      out.yilSonlari.add(OkunanYilSonu(yil, sm == null ? '' : '${sm.group(1)}. Sınıf', not));
    }
    out.yilSonlari.sort((a, b) => a.yil.compareTo(b.yil));
  }

  static final _donemRe = RegExp(r'(?:^|\s)([12])\s+donem');

  /// Tek başına "1. Dönem" / "2. DÖNEM NOTLARI" gibi bir başlık satırı mı?
  static int? _donemBasligi(List<String> r) {
    if (r.length > 2) return null;
    final k = _katla(r.join(' '));
    if (k.length > 40) return null;
    final m = _donemRe.firstMatch(k);
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// Başlık hücresinden (tür, sıra, dönem); not sütunu değilse null.
  static (String, int?, int?)? _sutunTuru(String baslik) {
    var k = _katla(baslik);
    if (k.isEmpty) return null;
    if (k.contains('ortalama') || k.contains('puan') || k.contains('toplam')) return null;
    int? donem;
    final dm = _donemRe.firstMatch(k);
    if (dm != null) {
      donem = int.parse(dm.group(1)!);
      k = k.replaceFirst(_donemRe, ' ');
    }
    final sira = int.tryParse(RegExp(r'(\d)').firstMatch(k)?.group(1) ?? '');
    if (k.contains('performans')) return ('performans', sira, donem);
    if (k.contains('proje')) return ('proje', sira, donem);
    if (k.contains('sinav') || k.contains('yazili')) return ('yazili', sira, donem);
    return null;
  }

  /// Ders | 1. Sınav | 2. Sınav | 1. Performans | ... başlıklı tablo.
  static void _metinNotTablosu(List<List<String>> rows, EkranSonucu out) {
    Map<int, (String, int, int?)>? sutunlar;
    int? donem;
    for (final r in rows) {
      final db = _donemBasligi(r);
      if (db != null) {
        donem = db;
        continue;
      }
      if (r.length >= 2) {
        final eslesen = <int, (String, int?, int?)>{};
        for (var i = 0; i < r.length; i++) {
          final t = _sutunTuru(r[i]);
          if (t != null) eslesen[i] = t;
        }
        final dersVar = r.any((c) => dersAdiBul(c) != null);
        if (eslesen.length >= 2 && !dersVar) {
          // Sırası yazmayan sütunlara türü içinde sırayla numara ver
          final sayac = <String, int>{};
          sutunlar = {};
          for (final e in eslesen.entries) {
            final (tur, sira, sd) = e.value;
            final k = '$tur|$sd';
            final s = sira ?? (sayac[k] ?? 0) + 1;
            sayac[k] = s;
            sutunlar[e.key] = (tur, s, sd);
          }
          continue;
        }
      }
      if (sutunlar == null || r.length < 2) continue;
      if (_tarih(r.join(' ')) != null) continue;
      final ders = dersAdiBul(r.first) ?? (r.length > 1 ? dersAdiBul(r[1]) : null);
      if (ders == null) continue;
      for (final e in sutunlar.entries) {
        if (e.key >= r.length) continue;
        final v = _notDegeri(r[e.key]);
        if (v == null) continue;
        final (tur, sira, sd) = e.value;
        final n = OkunanNot(ders, tur, sira, v, sd ?? donem);
        out.notlar.removeWhere((x) => x.ayni(n));
        out.notlar.add(n);
      }
    }
  }

  /// Başlıksız düzen: ders adı satırı, altında "1. Sınav 85" gibi satırlar
  /// ya da ders adıyla aynı satırda sıralı notlar.
  static void _metinNotSatirlari(List<List<String>> rows, EkranSonucu out) {
    final yilRe = RegExp(r'20\d\d\s*[-–/]\s*20\d\d');
    String? ders;
    int? donem;
    final sayac = <String, int>{};
    for (final r in rows) {
      final m = r.join(' ');
      if (_tarih(m) != null || yilRe.hasMatch(m)) continue;
      final db = _donemBasligi(r);
      if (db != null) {
        donem = db;
        sayac.clear();
        continue;
      }
      final d = dersAdiBul(r.first.isNotEmpty ? r.first : m);
      final kucuk = _katla(m);
      final tur = kucuk.contains('performans')
          ? 'performans'
          : (kucuk.contains('proje') ? 'proje' : 'yazili');
      final hucreler = r.length > 1 ? r : m.split(RegExp(r'\s+'));
      final sayilar = <double>[];
      for (final c in hucreler) {
        final v = _notDegeri(c);
        if (v != null) sayilar.add(v);
      }
      if (d != null) {
        ders = d;
        for (final v in sayilar) {
          final k = '$d|yazili';
          sayac[k] = (sayac[k] ?? 0) + 1;
          out.notlar.add(OkunanNot(d, 'yazili', sayac[k]!, v, donem));
        }
        continue;
      }
      if (ders == null || sayilar.isEmpty) continue;
      if (!(kucuk.contains('sinav') ||
          kucuk.contains('yazili') ||
          kucuk.contains('performans') ||
          kucuk.contains('proje'))) {
        continue;
      }
      final siraM = RegExp(r'(\d)\s*\.').firstMatch(m);
      final dr = ders;
      final k = '$dr|$tur';
      final sira = siraM != null ? int.parse(siraM.group(1)!) : (sayac[k] ?? 0) + 1;
      sayac[k] = sira;
      // "1. Sınav 85" -> son sayı nottur
      final n = OkunanNot(dr, tur, sira, sayilar.last, donem);
      out.notlar.removeWhere((x) => x.ayni(n));
      out.notlar.add(n);
    }
  }
}
