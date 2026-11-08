import '../osym.dart';
import 'kitap_katalog.dart';
import 'osym_db.dart';

/// Sayfadan okunan, henüz kaydedilmemiş sınav sonucu.
class OsymTaslak {
  OsymTaslak(this.tur, {this.yil});
  final String tur;
  int? yil;
  final testler = <String, TestSonucu>{};
  final puanlar = <String, double>{};

  OsymSinavTuru get tanim => osymTuru(tur)!;
  String get ad => '${yil ?? ''} ${tanim.ad}'.trim();
  bool get bos => testler.isEmpty && puanlar.isEmpty;
  String get anahtar => '$tur|$yil';
}

/// ÖSYM AİS / sonuç sayfası metninden sınav sonuçlarını çıkarır.
/// Satırlar: tablo satırıysa hücreler, değilse tek elemanlı liste.
class OsymAyristirici {
  OsymAyristirici._();

  static String _k(String s) => KitapKatalog.kelimelereAyir(s).join(' ');

  static int? _sayi(String c) {
    final t = c.trim();
    if (!RegExp(r'^\d{1,3}$').hasMatch(t)) return null;
    return int.parse(t);
  }

  static double? _ondalik(String c) {
    final m = RegExp(r'^(\d{1,3})[.,](\d{1,6})$').firstMatch(c.trim());
    if (m == null) return null;
    return double.tryParse('${m.group(1)}.${m.group(2)}');
  }

  /// Satırın hangi sınav bölümünü başlattığını bulur.
  static String? _bolum(String k) {
    if (RegExp(r'\b(ayt|alan yeterlilik)\b').hasMatch(k)) return 'AYT';
    if (RegExp(r'\b(tyt|temel yeterlilik)\b').hasMatch(k)) return 'TYT';
    if (RegExp(r'\b(ydt|yabanci dil testi)\b').hasMatch(k)) return 'YDT';
    if (RegExp(r'\b(oabt|ogretmenlik alan bilgisi)\b').hasMatch(k)) return 'OABT';
    if (RegExp(r'\b(ags|akademi giris)\b').hasMatch(k)) return 'AGS';
    if (RegExp(r'\bkpss\b|genel yetenek genel kultur').hasMatch(k)) return 'KPSS';
    return null;
  }

  /// Test adından (sınav türü, test) eşleşmesi. Önce bağlamdaki sınav denenir.
  static (String, OsymTest)? _test(String hucre, String? baglam) {
    final k = _k(hucre);
    if (k.isEmpty || k.length > 70) return null;
    (String, OsymTest)? bul(OsymSinavTuru s) {
      // En uzun eşleşen ad (ör. "temel matematik" > "matematik")
      (String, OsymTest)? en;
      var uz = 0;
      for (final t in s.testler) {
        for (final ad in [t.ad, ...t.takmaAdlar]) {
          final a = _k(ad);
          if (a.isNotEmpty && (k == a || k.startsWith('$a ') || k.endsWith(' $a') || k.contains(a))) {
            if (a.length > uz) {
              uz = a.length;
              en = (s.id, t);
            }
          }
        }
      }
      return en;
    }

    if (baglam != null) {
      final r = bul(osymTuru(baglam)!);
      if (r != null) return r;
    }
    for (final s in osymSinavlari) {
      final r = bul(s);
      if (r != null) return r;
    }
    return null;
  }

  static const _puanAdlari = {
    'tyt': 'TYT', 'say': 'SAY', 'sayisal': 'SAY', 'ea': 'EA', 'esit agirlik': 'EA',
    'soz': 'SÖZ', 'sozel': 'SÖZ', 'dil': 'DİL', 'kpssp3': 'KPSSP3', 'kpssp93': 'KPSSP93',
    'kpssp94': 'KPSSP94', 'ags': 'AGS', 'oabt': 'ÖABT',
  };

  static List<OsymTaslak> oku(List<List<String>> satirlar) {
    final taslaklar = <String, OsymTaslak>{};
    final yilRe = RegExp(r'\b(20[1-3]\d)\b');
    int? yil;
    String? baglam;
    // Sütun başlıkları: soru / doğru / yanlış / boş / net
    Map<String, int>? sutun;

    OsymTaslak taslak(String tur) =>
        taslaklar.putIfAbsent('$tur|$yil', () => OsymTaslak(tur, yil: yil));

    for (final ham in satirlar) {
      final r = [for (final c in ham) c.trim()];
      if (r.every((c) => c.isEmpty)) continue;
      final metin = r.join(' ');
      final k = _k(metin);

      final ym = yilRe.firstMatch(metin);
      if (ym != null && r.length <= 3 && metin.length < 90) yil = int.parse(ym.group(1)!);
      final b = _bolum(k);
      if (b != null && metin.length < 90) baglam = b;

      // Başlık satırı mı?
      if (r.length >= 3) {
        final m = <String, int>{};
        for (var i = 0; i < r.length; i++) {
          final h = _k(r[i]);
          if (h.contains('dogru')) m['d'] = i;
          if (h.contains('yanlis')) m['y'] = i;
          if (h.contains('bos')) m['b'] = i;
          if (h == 'net' || h.startsWith('net ') || h.endsWith(' net')) m['net'] = i;
          if (h.contains('soru')) m['s'] = i;
        }
        if (m.containsKey('d') && m.containsKey('y')) {
          sutun = m;
          continue;
        }
      }

      // Puan satırı: "TYT puanı | 412,34567" ya da "SAY | 380,123"
      for (var i = 0; i < r.length; i++) {
        final hk = _k(r[i]).replaceAll(' puani', '').replaceAll(' puan', '').trim();
        final ad = _puanAdlari[hk];
        if (ad == null) continue;
        for (var j = i + 1; j < r.length && j <= i + 3; j++) {
          final v = _ondalik(r[j]);
          if (v != null && v > 0 && v <= 600) {
            final tur = switch (ad) {
              'TYT' => 'TYT',
              'SAY' || 'EA' || 'SÖZ' => 'AYT',
              'DİL' => 'YDT',
              'AGS' => 'AGS',
              'ÖABT' => 'OABT',
              _ => 'KPSS',
            };
            taslak(tur).puanlar[ad] = v;
            break;
          }
        }
      }

      // Test satırı
      final ilk = r.indexWhere((c) => _test(c, baglam) != null);
      if (ilk < 0) continue;
      final eslesme = _test(r[ilk], baglam)!;
      final sayilar = <(int, int)>[]; // (sütun, değer)
      for (var i = ilk + 1; i < r.length; i++) {
        final v = _sayi(r[i]);
        if (v != null) sayilar.add((i, v));
      }
      if (r.length == 1) {
        // "Türkçe 40 32 6 30,5" gibi tek hücre
        final parca = r.first.split(RegExp(r'\s+'));
        for (var i = 0; i < parca.length; i++) {
          final v = _sayi(parca[i]);
          if (v != null) sayilar.add((i, v));
        }
      }
      if (sayilar.isEmpty) continue;

      var tur = eslesme.$1;
      var test = eslesme.$2;
      int? d, y, s;
      final st = sutun;
      if (st != null) {
        int? al(String a) {
          final i = st[a];
          if (i == null) return null;
          for (final x in sayilar) {
            if (x.$1 == i) return x.$2;
          }
          return null;
        }

        d = al('d');
        y = al('y');
        s = al('s');
        final bo = al('b');
        if (s == null && d != null && y != null && bo != null) s = d + y + bo;
      }
      if (d == null || y == null) {
        final v = sayilar.map((e) => e.$2).toList();
        final varsayilan = test.soru;
        if (v.length >= 3 && v[0] >= v[1] + v[2] && v[0] <= 200) {
          // soru, doğru, yanlış (, boş/net)
          s = v[0];
          d = v[1];
          y = v[2];
        } else if (v.length >= 2) {
          d = v[0];
          y = v[1];
          if (v.length >= 3 && d + y + v[2] <= 200) s = d + y + v[2];
        } else {
          continue;
        }
        s ??= varsayilan;
      }
      s ??= test.soru;
      if (d + y > s) s = d + y;

      // TYT/AYT "Fen Bilimleri" ayrımı: soru sayısına göre
      if (test.id == 'fen' && baglam == null) {
        tur = s > 20 || d + y > 20 ? 'AYT' : 'TYT';
        test = osymTuru(tur)!.test('fen')!;
      }
      taslak(tur).testler[test.id] = TestSonucu(soru: s, d: d, y: y);
    }

    final l = taslaklar.values.where((t) => !t.bos).toList();
    for (final t in l) {
      t.yil ??= DateTime.now().year;
    }
    return l;
  }
}
