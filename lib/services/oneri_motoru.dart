import 'package:flutter/material.dart';

import '../lgs.dart';
import '../models.dart';
import '../osym.dart';
import 'okul_db.dart';
import 'osym_db.dart';
import 'plan_motoru.dart';
import 'program_db.dart';
import 'takip_db.dart';

/// İyi / Orta / Kötü
enum Seviye { iyi, orta, kotu, yok }

Seviye seviyeOf(double? skor) {
  if (skor == null) return Seviye.yok;
  if (skor >= 75) return Seviye.iyi;
  if (skor >= 55) return Seviye.orta;
  return Seviye.kotu;
}

extension SeviyeX on Seviye {
  String get ad => switch (this) {
        Seviye.iyi => 'İyi',
        Seviye.orta => 'Orta',
        Seviye.kotu => 'Kötü',
        Seviye.yok => 'Veri yok',
      };
  Color get renk => switch (this) {
        Seviye.iyi => const Color(0xFF2E7D32),
        Seviye.orta => const Color(0xFFF9A825),
        Seviye.kotu => const Color(0xFFC62828),
        Seviye.yok => Colors.grey,
      };
  IconData get ikon => switch (this) {
        Seviye.iyi => Icons.sentiment_very_satisfied,
        Seviye.orta => Icons.sentiment_neutral,
        Seviye.kotu => Icons.sentiment_dissatisfied,
        Seviye.yok => Icons.help_outline,
      };
}

/// Değerlendirilen bir alan (soru çözümü, denemeler, okul ...).
class Alan {
  Alan(this.ad, this.ikon, this.skor, this.deger, this.aciklama, this.agirlik);
  final String ad;
  final IconData ikon;
  final double? skor; // 0-100
  final String deger;
  final String aciklama;
  final double agirlik;
  Seviye get seviye => seviyeOf(skor);
}

class DersOnerisi {
  DersOnerisi({
    required this.ders,
    required this.basari,
    required this.ortNet,
    required this.kazanc,
    required this.haftalikBlok,
    required this.neden,
    required this.konular,
  });
  final LgsDers ders;
  final double? basari; // 0-1
  final double? ortNet; // son denemeler
  final double kazanc; // eksik net x katsayı
  final int haftalikBlok;
  final String neden;
  final List<String> konular; // öncelikli konular
  Seviye get seviye => seviyeOf(basari == null ? null : basari! * 100);
}

class EksikKonu {
  EksikKonu(this.ders, this.konu, this.basari, this.soru, {this.hata = 0});
  final String ders;
  final String konu;
  final double? basari; // null: hiç çalışılmamış (hata > 0 ise ÖSYM sonucu)
  final int soru;

  /// ÖSYM sınav / deneme sonuçlarında bu konudaki yanlış + boş sayısı.
  final int hata;
  bool get zayif => basari != null || hata > 0;
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ş', 's')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c')
    .replaceAll('â', 'a')
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// ÖSYM testindeki bir konunun öğrencinin hangi dersine ait olduğunu bulur.
/// "Fizik: Optik" -> Fizik; önek yoksa testin adına bakılır.
String? osymKonuDersi(OsymTest t, String konu, List<String> dersler) {
  final i = konu.indexOf(': ');
  if (i > 0) {
    final d = _onekDersi(konu.substring(0, i), dersler);
    if (d != null) return d;
  }
  return osymTestDersi(t, dersler);
}

String? _onekDersi(String onek, List<String> dersler) {
  final o = _norm(onek);
  final adaylar = <String>[
    o,
    if (o == 'din') 'din kulturu',
    if (o == 'mantik' || o == 'psikoloji' || o == 'sosyoloji') 'felsefe',
    if (o == 'cografya') 'turkiye cografyasi',
    if (o == 'turkce') 'sozel yetenek',
    if (o == 'matematik' || o == 'geometri') 'sayisal yetenek',
    if (o == 'geometri') 'matematik',
  ];
  for (final a in adaylar) {
    for (final d in dersler) {
      final n = _norm(d);
      if (n == a || n.startsWith('$a ') || (a.length > 3 && n.contains(a))) return d;
    }
  }
  return null;
}

String? osymTestDersi(OsymTest t, List<String> dersler) {
  final adlar = [t.ad, ...t.takmaAdlar];
  for (final a in adlar) {
    final na = _norm(a);
    for (final d in dersler) {
      if (_norm(d) == na) return d;
    }
  }
  for (final a in adlar) {
    final na = _norm(a);
    for (final d in dersler) {
      final nd = _norm(d);
      if (nd.length > 3 && (na.contains(nd) || nd.contains(na))) return d;
    }
  }
  return null;
}

/// Bir ÖSYM testinin kapsadığı dersler (konu önekleri + test adı).
Set<String> osymTestDersleri(OsymTest t, List<String> dersler) {
  final s = <String>{};
  for (final k in t.konular) {
    final d = osymKonuDersi(t, k, dersler);
    if (d != null) s.add(d);
  }
  final d = osymTestDersi(t, dersler);
  if (d != null) s.add(d);
  return s;
}

const _palet = [
  Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFF8E24AA),
  Color(0xFFF9A825), Color(0xFF6D4C41), Color(0xFF00897B), Color(0xFF3949AB),
  Color(0xFFD81B60), Color(0xFF546E7A),
];

enum Onem { kritik, onemli, bilgi, iyi }

class Oneri {
  Oneri(this.onem, this.ikon, this.metin);
  final Onem onem;
  final IconData ikon;
  final String metin;
}

class OneriRaporu {
  OneriRaporu({
    required this.alanlar,
    required this.dersler,
    required this.eksikKonular,
    required this.okulZayif,
    required this.oneriler,
  });

  final List<Alan> alanlar;
  final List<DersOnerisi> dersler; // öncelik sırasıyla
  final List<EksikKonu> eksikKonular;
  final List<(String, double)> okulZayif; // ders, ortalama
  final List<Oneri> oneriler;

  double? get genelSkor {
    final v = alanlar.where((a) => a.skor != null).toList();
    if (v.isEmpty) return null;
    final w = v.fold<double>(0, (s, a) => s + a.agirlik);
    return v.fold<double>(0, (s, a) => s + a.skor! * a.agirlik) / w;
  }

  Seviye get genel => seviyeOf(genelSkor);
}

/// Tüm modüllerin verisinden öğrencinin genel durumunu ve önerileri çıkarır.
class OneriMotoru {
  OneriMotoru({
    required this.sorular,
    required this.denemeler,
    required this.hedef,
    required this.okulNotlari,
    required this.odevler,
    required this.plan,
    required this.programHaftasi,
    this.duzen,
    this.profil = 'LGS',
    this.dersAdlari = const [],
    this.osym = const [],
    this.okulVar = true,
    DateTime? simdi,
  }) : simdi = simdi ?? DateTime.now();

  /// Öğrencinin hedefi: LGS | YKS | KPSS | AGS | okul
  final String profil;

  /// Öğrencinin profilindeki dersler (LGS dışında öneriler bunlara göre).
  final List<String> dersAdlari;

  /// ÖSYM sınav ve deneme sonuçları (yeniden eskiye).
  final List<OsymSonuc> osym;

  /// Öğrenci okula devam ediyor mu (okul notları değerlendirilsin mi)?
  final bool okulVar;

  bool get _lgs => profil == 'LGS';
  bool get _osymMi => const ['YKS', 'KPSS', 'AGS'].contains(profil);

  int get gunlukSoruHedefi => switch (profil) {
        'LGS' => 60,
        'YKS' => 120,
        'KPSS' || 'AGS' => 100,
        _ => 30,
      };

  /// Haftalık önerilen çalışma (saat): alt-üst.
  (int, int) get haftalikSaat => switch (profil) {
        'LGS' => (10, 15),
        'YKS' => (25, 35),
        'KPSS' || 'AGS' => (20, 30),
        _ => (6, 10),
      };

  String get _sinavAdi => switch (profil) {
        'AGS' => 'AGS / ÖABT',
        'okul' => 'okul',
        _ => profil,
      };

  /// İlgili ÖSYM sonuçları (hedef sınav grubunda).
  List<OsymSonuc> get _osymSonuclari =>
      osym.where((x) => osymTuru(x.tur)?.grup == profil).toList();

  final List<SoruGirisi> sorular;
  final List<LgsDeneme> denemeler; // yeniden eskiye
  final LgsHedef? hedef;
  final List<OkulSinav> okulNotlari;
  final List<Homework> odevler;
  final HaftalikPlan? plan; // bu hafta
  final List<GunAnalizi>? programHaftasi; // etkinlik girilmediyse null
  final GunDuzeni? duzen;
  final DateTime simdi;

  OneriRaporu rapor() {
    final bugun = DateTime(simdi.year, simdi.month, simdi.day);
    final oneriler = <Oneri>[];
    final alanlar = <Alan>[];

    // ---- 1) Soru çözümü (son 14 gün) ----
    final s14 = sorular.where((e) => e.tarih.isAfter(bugun.subtract(const Duration(days: 14))));
    final top14 = s14.fold<Dyb>(Dyb.bos, (a, e) => a + e.toplam);
    final gunluk = top14.toplam / 14;
    final s7gun = sorular
        .where((e) => e.tarih.isAfter(bugun.subtract(const Duration(days: 7))))
        .map((e) => DateTime(e.tarih.year, e.tarih.month, e.tarih.day))
        .toSet()
        .length;
    double? soruSkor;
    if (sorular.isNotEmpty) {
      final hacim = (gunluk / gunlukSoruHedefi).clamp(0, 1).toDouble();
      soruSkor = top14.toplam == 0 ? 0 : top14.basari * 100 * 0.65 + hacim * 100 * 0.35;
    }
    alanlar.add(Alan(
      'Soru çözümü',
      Icons.edit_note,
      soruSkor,
      top14.toplam == 0 ? '—' : '%${(top14.basari * 100).round()} doğru',
      sorular.isEmpty
          ? 'Henüz soru girişi yok.'
          : 'Son 14 günde ${top14.toplam} soru (günde ~${gunluk.round()}), '
              'son 7 günün $s7gun gününde çalışılmış.',
      0.25,
    ));

    // ---- 2) Denemeler ----
    final lgsDeneme = _lgs || (profil == 'okul' && denemeler.isNotEmpty);
    final son3 = lgsDeneme ? denemeler.take(3).toList() : <LgsDeneme>[];
    double? denemeSkor;
    double? ortPuan, ortNet;
    final osymSon = _osymSonuclari;
    final osym3 = osymSon.take(3).toList();
    double? osymOran;
    if (_osymMi) {
      if (osym3.isNotEmpty) {
        osymOran = osym3.fold<double>(
                0.0,
                (s, x) => s +
                    (x.toplamSoru == 0 ? 0.0 : x.toplamNet.clamp(0.0, 999.0).toDouble() / x.toplamSoru)) /
            osym3.length;
        denemeSkor = (osymOran * 100).clamp(0, 100).toDouble();
      }
      final resmi = osymSon.where((x) => x.resmi).length;
      alanlar.add(Alan(
        '$_sinavAdi sınav ve denemeleri',
        Icons.workspace_premium_outlined,
        denemeSkor,
        osymOran == null ? '—' : '%${(osymOran * 100).round()} net',
        osym3.isEmpty
            ? 'Henüz $_sinavAdi sonucu yok. ÖSYM Sınavları sekmesinden sonuç aktarın'
                '${profil == 'AGS' ? ' ya da AGS Hazırlık\'ta günlük deneme çözün' : ''}.'
            : 'Son ${osym3.length} sonucun net oranı ortalaması '
                '(${osym3.map((x) => '${x.tur} ${x.toplamNet.toStringAsFixed(1)}/${x.toplamSoru}').join(', ')}). '
                'Toplam ${osymSon.length} kayıt, $resmi tanesi ÖSYM sınavı.',
        0.30,
      ));
    }
    if (son3.isNotEmpty) {
      ortNet = son3.fold<double>(0, (s, d) => s + d.toplamNet) / son3.length;
      ortPuan = son3.fold<double>(0, (s, d) => s + d.gosterilenPuan) / son3.length;
      final netSkor = (ortNet / 90 * 100).clamp(0, 100).toDouble();
      final h = hedef?.puan;
      denemeSkor = h != null && h > 0
          ? (netSkor + (ortPuan / h * 100).clamp(0, 100)) / 2
          : netSkor;
    }
    if (lgsDeneme) alanlar.add(Alan(
      'LGS denemeleri',
      Icons.flag_outlined,
      denemeSkor,
      ortNet == null ? '—' : '${ortNet.toStringAsFixed(1)} net',
      son3.isEmpty
          ? 'Henüz deneme girilmemiş.'
          : 'Son ${son3.length} deneme ortalaması ${ortPuan!.toStringAsFixed(1)} puan'
              '${hedef?.puan != null ? ' (hedef ${hedef!.puan!.round()})' : ''}.',
      0.30,
    ));

    // ---- 3) Okul notları (bu dönem) ----
    final donem = donemOf(simdi);
    final notlar = okulNotlari.where((n) => n.donem == donem && n.not != null);
    final dersNot = <String, List<double>>{};
    for (final n in notlar) {
      dersNot.putIfAbsent(n.ders, () => []).add(n.not!);
    }
    double? okulOrt;
    final okulZayif = <(String, double)>[];
    if (dersNot.isNotEmpty) {
      var w = 0.0, t = 0.0;
      dersNot.forEach((d, l) {
        final o = l.reduce((a, b) => a + b) / l.length;
        w += dersAgirligi(d);
        t += o * dersAgirligi(d);
        if (o < 70) okulZayif.add((d, o));
      });
      okulOrt = t / w;
      okulZayif.sort((a, b) => a.$2.compareTo(b.$2));
    }
    if (okulVar) alanlar.add(Alan(
      'Okul notları',
      Icons.school_outlined,
      okulOrt,
      okulOrt == null ? '—' : okulOrt.toStringAsFixed(1),
      okulOrt == null
          ? 'Bu dönem okul notu girilmemiş.'
          : '$donem. dönem tahmini ortalama, ${dersNot.length} ders.',
      0.15,
    ));

    // ---- 4) Ödevler (son 30 gün) ----
    final gecmis = odevler.where((h) =>
        h.dueDate != null &&
        h.dueDate!.isBefore(bugun) &&
        h.dueDate!.isAfter(bugun.subtract(const Duration(days: 30))));
    final geciken = odevler
        .where((h) => !h.done && h.dueDate != null && h.dueDate!.isBefore(bugun))
        .toList();
    double? odevSkor;
    if (gecmis.isNotEmpty) {
      final oran = gecmis.where((h) => h.done).length / gecmis.length;
      odevSkor = (oran * 100 - geciken.length * 5).clamp(0, 100).toDouble();
    }
    alanlar.add(Alan(
      'Ödevler',
      Icons.assignment_outlined,
      odevSkor,
      gecmis.isEmpty ? '—' : '%${(gecmis.where((h) => h.done).length / gecmis.length * 100).round()}',
      gecmis.isEmpty
          ? 'Son 30 günde teslim tarihi geçen ödev yok.'
          : '${gecmis.length} ödevin ${gecmis.where((h) => h.done).length} tanesi yapıldı'
              '${geciken.isNotEmpty ? ', ${geciken.length} ödev gecikmiş' : ''}.',
      0.15,
    ));

    // ---- 5) Plan uyumu (bu hafta, dünkü güne kadar) ----
    final gunNo = simdi.weekday - 1;
    double? planSkor;
    var planDk = 0, tamamDk = 0;
    if (plan != null) {
      for (var g = 0; g < gunNo; g++) {
        for (final b in plan!.gunler[g]) {
          planDk += b.dakika;
          if (b.tamam) tamamDk += b.dakika;
        }
      }
      if (planDk > 0) planSkor = tamamDk / planDk * 100;
    }
    alanlar.add(Alan(
      'Plana uyum',
      Icons.calendar_month_outlined,
      planSkor,
      planSkor == null ? '—' : '%${planSkor.round()}',
      planSkor == null
          ? 'Bu hafta için değerlendirilecek plan yok.'
          : 'Bu hafta ${sureYaz(planDk)} planlanan çalışmanın ${sureYaz(tamamDk)} kadarı yapıldı.',
      0.10,
    ));

    // ---- 6) Zaman (program) ----
    final ph = programHaftasi;
    final haftalikCalisma = ph?.fold<int>(0, (s, g) => s + g.calismaDk);
    alanlar.add(Alan(
      'Çalışma zamanı',
      Icons.schedule,
      haftalikCalisma == null ? null : (haftalikCalisma / (haftalikSaat.$1 * 60) * 100).clamp(0, 100).toDouble(),
      haftalikCalisma == null ? '—' : sureYaz(haftalikCalisma),
      haftalikCalisma == null
          ? 'Program sekmesine okul/dershane saatleri girilmemiş.'
          : 'Haftalık programda ders çalışmaya ayrılabilecek süre.',
      0.05,
    ));

    // ---- Ders öncelikleri ----
    final durum = (_lgs
        ? PlanMotoru(sorular: sorular, denemeler: denemeler, simdi: simdi).dersDurumlari()
        : _genelDersDurumlari(bugun, dersNot, osym3))
      ..sort((a, b) => b.ihtiyac.compareTo(a.ihtiyac));
    final toplamIhtiyac = durum.fold<double>(0, (s, d) => s + d.ihtiyac);
    final haftalikBlok = haftalikCalisma == null
        ? 14
        : (haftalikCalisma / PlanMotoru.blokDakika).floor();
    final eksikKonular = _eksikKonular(bugun);
    final dersler = <DersOnerisi>[];
    for (final d in durum) {
      final netler = son3.map((x) => x.dersler[d.ders.ad]?.net ?? 0).toList();
      final on = netler.isEmpty ? null : netler.reduce((a, b) => a + b) / netler.length;
      final kazanc = on == null ? 0.0 : (d.ders.soru - on.clamp(0, d.ders.soru)) * d.ders.katsayi;
      final neden = <String>[];
      if (on != null) neden.add('deneme ort. ${on.toStringAsFixed(1)}/${d.ders.soru} net');
      if (d.basari != null) neden.add('başarı %${(d.basari! * 100).round()}');
      if (!_lgs) neden.addAll(_genelNeden[d.ders.ad] ?? const []);
      neden.add(d.soru == 0 ? '14 günde soru yok' : '14 günde ${d.soru} soru');
      if (_lgs && d.ders.katsayi == 4) neden.add('katsayı 4');
      if (_osymMi && d.ders.soru > 0) neden.add('sınavda ~${d.ders.soru} soru');
      dersler.add(DersOnerisi(
        ders: d.ders,
        basari: d.basari,
        ortNet: on,
        kazanc: kazanc.toDouble(),
        haftalikBlok: toplamIhtiyac == 0
            ? 0
            : (haftalikBlok * d.ihtiyac / toplamIhtiyac).round().clamp(1, 99),
        neden: neden.join(' • '),
        konular: eksikKonular
            .where((k) => k.ders == d.ders.ad)
            .take(3)
            .map((k) => k.konu)
            .toList(),
      ));
    }

    // ---- Öneriler ----
    final h = _lgs ? hedef?.puan : null;
    if (h != null && ortPuan != null) {
      final fark = h - ortPuan;
      final enKazanc = List.of(dersler)..sort((a, b) => b.kazanc.compareTo(a.kazanc));
      if (fark > 0) {
        oneriler.add(Oneri(
            fark > 40 ? Onem.kritik : Onem.onemli,
            Icons.flag,
            'Hedef ${h.round()} puan için son denemelerin ortalamasından '
            '${fark.toStringAsFixed(0)} puan eksik. En çok puan kazandıracak ders: '
            '${enKazanc.first.ders.ad} (ortalama ${enKazanc.first.ortNet?.toStringAsFixed(1) ?? '-'}'
            '/${enKazanc.first.ders.soru} net).'));
      } else {
        oneriler.add(Oneri(Onem.iyi, Icons.emoji_events,
            'Deneme ortalaması hedefin üzerinde (${ortPuan.toStringAsFixed(0)}). Bu seviyeyi korumak için düzenli deneme çözmeye devam.'));
      }
    } else if (_lgs && h == null && son3.isNotEmpty) {
      oneriler.add(Oneri(Onem.bilgi, Icons.flag_outlined,
          'LGS Deneme sekmesinden hedef puan girerseniz hedefe olan mesafe de hesaplanır.'));
    }

    if (_osymMi) _osymOnerileri(oneriler, osymSon, bugun);

    if (lgsDeneme && denemeler.length >= 4) {
      final onceki = denemeler.skip(3).take(3).toList();
      final oOrt = onceki.fold<double>(0, (s, d) => s + d.gosterilenPuan) / onceki.length;
      final fark = (ortPuan ?? 0) - oOrt;
      if (fark <= -10) {
        oneriler.add(Oneri(Onem.kritik, Icons.trending_down,
            'Son 3 denemenin ortalaması öncekilere göre ${(-fark).toStringAsFixed(0)} puan düştü. '
            'Yanlış yapılan soruları ders ders gözden geçirip konu tekrarı yapın.'));
      } else if (fark >= 10) {
        oneriler.add(Oneri(Onem.iyi, Icons.trending_up,
            'Son 3 denemede ${fark.toStringAsFixed(0)} puanlık yükseliş var 👏'));
      }
    }

    for (final d in dersler.take(2)) {
      oneriler.add(Oneri(
          (d.basari ?? 0.5) < 0.55 ? Onem.kritik : Onem.onemli,
          d.ders.ikon,
          '${d.ders.ad} dersine ağırlık ver: haftada en az ${d.haftalikBlok} blok '
          '(${sureYaz(d.haftalikBlok * PlanMotoru.blokDakika)}).'
          '${d.konular.isNotEmpty ? ' Öncelik: ${d.konular.join(', ')}.' : ''}'));
    }

    // Yanlış oranı yüksek dersler
    for (final d in lgsDeneme ? lgsDersler : const <LgsDers>[]) {
      final t = son3.fold<Dyb>(Dyb.bos, (a, x) => a + (x.dersler[d.ad] ?? Dyb.bos));
      if (t.d + t.y < 6) continue;
      final yOran = t.y / (t.d + t.y);
      if (yOran >= 0.3) {
        oneriler.add(Oneri(Onem.onemli, Icons.close,
            '${d.ad} denemelerinde yanlış oranı yüksek (%${(yOran * 100).round()}). '
            '3 yanlış 1 doğruyu götürür: emin olmadığın soruyu boş bırak, yanlışları deftere yaz.'));
      }
    }

    final zayifKonu = eksikKonular.where((k) => k.zayif).take(5).toList();
    if (zayifKonu.isNotEmpty) {
      oneriler.add(Oneri(
          Onem.onemli,
          Icons.replay,
          'Tekrar edilmesi gereken konular: '
          '${zayifKonu.map((k) => k.basari != null ? '${k.konu} (%${(k.basari! * 100).round()})' : '${k.konu} (${k.hata} hata)').join(', ')}.'));
    }

    if (sorular.isNotEmpty && gunluk < gunlukSoruHedefi * 2 / 3) {
      oneriler.add(Oneri(gunluk < gunlukSoruHedefi / 3 ? Onem.kritik : Onem.onemli, Icons.speed,
          'Son 14 günde günde ortalama ${gunluk.round()} soru çözülmüş. $_sinavAdi için günde '
          'en az $gunlukSoruHedefi soru hedeflenmeli.'));
    } else if (sorular.isEmpty) {
      oneriler.add(Oneri(Onem.bilgi, Icons.edit_note,
          'Soru Takibi sekmesine günlük çözülen soruları girerseniz öneriler çok daha isabetli olur.'));
    }
    if (sorular.isNotEmpty && s7gun <= 3) {
      oneriler.add(Oneri(Onem.onemli, Icons.event_busy,
          'Son 7 günün yalnızca $s7gun gününde soru çözülmüş. Her gün az da olsa çalışmak daha etkilidir.'));
    }

    if (geciken.isNotEmpty) {
      oneriler.add(Oneri(Onem.kritik, Icons.assignment_late,
          '${geciken.length} ödevin teslim tarihi geçmiş: '
          '${geciken.take(3).map((h) => h.title).join(', ')}${geciken.length > 3 ? '...' : ''}.'));
    }

    final yaklasan = okulNotlari
        .where((n) =>
            n.not == null &&
            n.tarih != null &&
            !n.tarih!.isBefore(bugun) &&
            n.tarih!.difference(bugun).inDays <= 10)
        .toList();
    for (final s in yaklasan.take(3)) {
      final g = DateTime(s.tarih!.year, s.tarih!.month, s.tarih!.day).difference(bugun).inDays;
      oneriler.add(Oneri(g <= 3 ? Onem.kritik : Onem.onemli, Icons.event,
          '${s.ders} ${s.baslik.toLowerCase()} sınavı ${g == 0 ? 'bugün' : (g == 1 ? 'yarın' : '$g gün sonra')}. '
          'Önceki günlerde bu derse tekrar bloğu ayır.'));
    }

    for (final z in okulZayif.take(2)) {
      oneriler.add(Oneri(z.$2 < 50 ? Onem.kritik : Onem.onemli, Icons.school,
          'Okulda ${z.$1} ortalaması ${z.$2.toStringAsFixed(1)}. Bu derse destek gerekli.'));
    }

    if (ph != null) {
      final sifir = ph.where((g) => g.calismaDk == 0).map((g) => gunUzun[g.gun]).toList();
      if (sifir.isNotEmpty && sifir.length < 7) {
        oneriler.add(Oneri(Onem.bilgi, Icons.schedule,
            '${sifir.join(', ')} programda ders çalışmaya zaman kalmıyor; o günler dinlenme günü sayılabilir ya da kısa tekrar yapılabilir.'));
      }
      final hc = haftalikCalisma ?? 0;
      final (alt, ust) = haftalikSaat;
      if (hc < alt * 60 * 0.8) {
        oneriler.add(Oneri(Onem.onemli, Icons.hourglass_bottom,
            'Haftalık çalışmaya ayrılabilen süre ${sureYaz(hc)}. '
            '${profil == 'okul' ? 'Okul dersleri' : '$_sinavAdi hazırlığı'} için '
            'haftada $alt-$ust saat önerilir; boş saatleri gözden geçirin.'));
      }
    } else {
      oneriler.add(Oneri(Onem.bilgi, Icons.schedule,
          'Program sekmesine okul ve dershane saatlerini girerseniz boş zamanlar ve çalışma saatleri hesaplanır.'));
    }

    final dz = duzen;
    if (dz != null) {
      final haftalikTel = dz.telefonHaftaIci * 5 + dz.telefonHaftaSonu * 2;
      if (dz.telefonHaftaIci > 120 || dz.telefonHaftaSonu > 180) {
        oneriler.add(Oneri(Onem.onemli, Icons.smartphone,
            'Telefon / ekran süresi haftada ${sureYaz(haftalikTel)}. Bunun bir kısmını çalışmaya '
            'ayırmak haftada ${sureYaz((haftalikTel - 5 * 90 - 2 * 120).clamp(0, 9999))} ek çalışma zamanı kazandırır.'));
      } else if (haftalikCalisma != null &&
          haftalikCalisma < haftalikSaat.$1 * 60 * 0.8 &&
          haftalikTel >= 5 * 60) {
        oneriler.add(Oneri(Onem.bilgi, Icons.smartphone,
            'Çalışma süresi az, telefon süresi haftada ${sureYaz(haftalikTel)}. Günde 30 dk '
            'kısaltmak haftada 3,5 saat çalışma zamanı demek.'));
      }
    }

    if (planSkor != null && planSkor < 50) {
      oneriler.add(Oneri(Onem.onemli, Icons.calendar_month,
          'Bu hafta planın yalnızca %${planSkor.round()}\'i yapıldı. Plan çok yoğunsa günlük hedefi düşürüp sürdürülebilir bir plan yapın.'));
    }

    const sira = {Onem.kritik: 0, Onem.onemli: 1, Onem.bilgi: 2, Onem.iyi: 3};
    final siraliOneri = [
      for (var i = 0; i < oneriler.length; i++) (i, oneriler[i]),
    ]..sort((a, b) {
        final c = sira[a.$2.onem]!.compareTo(sira[b.$2.onem]!);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });

    return OneriRaporu(
      alanlar: alanlar,
      dersler: dersler,
      eksikKonular: eksikKonular,
      okulZayif: okulZayif,
      oneriler: siraliOneri.map((e) => e.$2).toList(),
    );
  }

  /// LGS dışı: dersin hazır olma durumu (soru takibi + ÖSYM sonuçları + okul).
  final _genelNeden = <String, List<String>>{};

  List<String> get _dersListesi {
    if (dersAdlari.isNotEmpty) return dersAdlari;
    final s = <String>{};
    for (final e in sorular) {
      s.addAll(e.dersBazli.keys);
    }
    return s.toList();
  }

  List<DersDurumu> _genelDersDurumlari(
      DateTime bugun, Map<String, List<double>> dersNot, List<OsymSonuc> osym3) {
    final adlar = _dersListesi;
    final sinir = bugun.subtract(const Duration(days: 14));
    final top = <String, Dyb>{};
    for (final e in sorular.where((e) => e.tarih.isAfter(sinir))) {
      e.dersBazli.forEach((k, v) => top[k] = (top[k] ?? Dyb.bos) + v);
    }
    // ÖSYM: ders -> net oranları; ders -> sınavdaki soru sayısı
    final denemeOran = <String, List<double>>{};
    final soruSayisi = <String, double>{};
    final renk = <String, Color>{};
    for (final t in [for (final s in osymSinavlari.where((s) => s.grup == profil)) ...s.testler]) {
      final ds = osymTestDersleri(t, adlar);
      for (final d in ds) {
        soruSayisi[d] = (soruSayisi[d] ?? 0) + t.soru / ds.length;
        renk[d] ??= t.renk;
      }
    }
    for (final x in osym3) {
      final tanim = x.tanim;
      if (tanim == null) continue;
      x.testler.forEach((id, ts) {
        final t = tanim.test(id);
        if (t == null || ts.soru == 0) return;
        final oran = (ts.net(x.bolen) / ts.soru).clamp(0.0, 1.0);
        for (final d in osymTestDersleri(t, adlar)) {
          denemeOran.putIfAbsent(d, () => []).add(oran);
        }
      });
    }
    final enCokSoru = soruSayisi.values.fold<double>(1, (a, b) => b > a ? b : a);
    var i = 0;
    return adlar.map((ad) {
      final neden = <String>[];
      final oranlar = <double>[];
      final s = top[ad];
      if (s != null && s.toplam >= 5) {
        oranlar.add(s.basari);
        neden.add('soru takibi %${(s.basari * 100).round()}');
      }
      final dn = denemeOran[ad];
      if (dn != null && dn.isNotEmpty) {
        final o = dn.reduce((a, b) => a + b) / dn.length;
        oranlar.add(o);
        neden.add('sınav/deneme %${(o * 100).round()} net');
      }
      final notlar = dersNot[ad];
      if (okulVar && notlar != null && notlar.isNotEmpty) {
        final o = notlar.reduce((a, b) => a + b) / notlar.length;
        oranlar.add(o / 100);
        neden.add('okul ${o.toStringAsFixed(0)}');
      }
      _genelNeden[ad] = neden;
      final basari = oranlar.isEmpty ? null : oranlar.reduce((a, b) => a + b) / oranlar.length;
      final soru = (soruSayisi[ad] ?? 0).round();
      final agirlik = _osymMi
          ? (soru == 0 ? 0.3 : 0.3 + 0.7 * soru / enCokSoru)
          : dersAgirligi(ad) / 5;
      var ihtiyac = agirlik * (1.15 - (basari ?? 0.55));
      if ((s?.toplam ?? 0) < 20) ihtiyac += 0.12 * agirlik;
      final ders = LgsDers(
        ad: ad,
        kisa: ad,
        soru: soru,
        katsayi: 1,
        ikon: Icons.menu_book_outlined,
        renk: renk[ad] ?? _palet[i++ % _palet.length],
      );
      return DersDurumu(ders, basari, s?.toplam ?? 0, ihtiyac);
    }).toList();
  }

  /// ÖSYM sonuçlarına dayalı öneriler (YKS / KPSS / AGS).
  void _osymOnerileri(List<Oneri> oneriler, List<OsymSonuc> son, DateTime bugun) {
    if (son.isEmpty) {
      oneriler.add(Oneri(Onem.bilgi, Icons.workspace_premium_outlined,
          profil == 'AGS'
              ? 'AGS Hazırlık sekmesinden her gün yeni denemeyi çözün; sonuçlar buraya yansır ve eksik konular çıkarılır. '
                  'Geçmiş AGS / KPSS sonuçlarınızı ÖSYM Sınavları sekmesinden aktarabilirsiniz.'
              : 'ÖSYM Sınavları sekmesinden girdiğiniz $_sinavAdi sınavlarını ve denemeleri ekleyin; '
                  'net ve konu eksikleri buraya yansır.'));
      return;
    }
    double oran(OsymSonuc x) => x.toplamSoru == 0 ? 0.0 : x.toplamNet / x.toplamSoru;
    if (son.length >= 4) {
      final a = son.take(3).map(oran).reduce((p, q) => p + q) / 3;
      final b = son.skip(3).take(3).map(oran).reduce((p, q) => p + q) /
          son.skip(3).take(3).length;
      final fark = (a - b) * 100;
      if (fark <= -5) {
        oneriler.add(Oneri(Onem.kritik, Icons.trending_down,
            'Son 3 $_sinavAdi sonucunda net oranı öncekilere göre ${(-fark).round()} puan düştü. '
            'Yanlış yapılan konuları tekrar edin.'));
      } else if (fark >= 5) {
        oneriler.add(Oneri(Onem.iyi, Icons.trending_up,
            'Son 3 $_sinavAdi sonucunda net oranı ${fark.round()} puan yükseldi 👏'));
      }
    }
    // Yanlış oranı yüksek testler (son 3)
    final testToplam = <String, (int, int, String)>{};
    for (final x in son.take(3)) {
      final tanim = x.tanim;
      x.testler.forEach((id, t) {
        final ad = tanim?.test(id)?.ad ?? id;
        final o = testToplam[ad] ?? (0, 0, ad);
        testToplam[ad] = (o.$1 + t.d, o.$2 + t.y, ad);
      });
    }
    for (final e in testToplam.values) {
      if (e.$1 + e.$2 < 6) continue;
      final yOran = e.$2 / (e.$1 + e.$2);
      if (yOran >= 0.3) {
        oneriler.add(Oneri(Onem.onemli, Icons.close,
            '${e.$3} testinde yanlış oranı yüksek (%${(yOran * 100).round()}). '
            '4 yanlış 1 doğruyu götürür: emin olmadığın soruyu boş bırak.'));
      }
    }
    final sonTarih = son.first.tarih;
    final gun = bugun.difference(DateTime(sonTarih.year, sonTarih.month, sonTarih.day)).inDays;
    if (gun >= 7) {
      oneriler.add(Oneri(Onem.onemli, Icons.event_repeat,
          'Son $_sinavAdi denemesi $gun gün önce. Haftada en az 2 deneme çözmek sınav temposunu korur'
          '${profil == 'AGS' ? '; AGS Hazırlık\'taki günlük deneme 20 soruluk ve 30 dakikada biter' : ''}.'));
    }
  }

  /// Zayıf konular (son 45 gün, konu girişleri) + hiç çalışılmamış LGS konuları.
  List<EksikKonu> _eksikKonular(DateTime bugun) {
    final sinir = bugun.subtract(const Duration(days: 45));
    final konu = <String, Dyb>{};
    final hic = <String>{};
    for (final e in sorular.where((e) => !e.karma)) {
      final k = '${e.ders}|${e.konu}';
      hic.add(k);
      if (e.tarih.isBefore(sinir)) continue;
      konu[k] = (konu[k] ?? Dyb.bos) + e.sonuc;
    }
    final zayif = <EksikKonu>[
      for (final e in konu.entries)
        if (e.value.toplam >= 3 && e.value.basari < 0.65)
          EksikKonu(e.key.split('|').first, e.key.split('|').last, e.value.basari,
              e.value.toplam),
    ]..sort((a, b) => a.basari!.compareTo(b.basari!));
    // ÖSYM sonuçlarındaki konu eksikleri (son 6 sonuç)
    final osymHata = <String, int>{};
    final osymDers = <String, String>{};
    if (_osymMi) {
      final adlar = _dersListesi;
      for (final x in _osymSonuclari.take(6)) {
        final tanim = x.tanim;
        x.konuHata.forEach((anahtar, n) {
          final i = anahtar.indexOf('|');
          if (i < 0 || n <= 0) return;
          final t = tanim?.test(anahtar.substring(0, i));
          final konu = anahtar.substring(i + 1);
          final ders = (t == null ? null : osymKonuDersi(t, konu, adlar)) ?? t?.ad ?? '';
          final k = '$ders|$konu';
          osymHata[k] = (osymHata[k] ?? 0) + n;
          osymDers[k] = ders;
        });
      }
    }
    final osymZayif = <EksikKonu>[
      for (final e in osymHata.entries)
        EksikKonu(osymDers[e.key]!, e.key.split('|').last.replaceFirst(RegExp(r'^[^:]+: '), ''),
            null, 0, hata: e.value),
    ]..sort((a, b) => b.hata.compareTo(a.hata));
    if (!_lgs) return [...zayif, ...osymZayif];
    final calisilmamis = <EksikKonu>[
      for (final d in lgsDersler)
        for (final k in (lgsKonular[d.ad] ?? const <String>[]))
          if (!hic.contains('${d.ad}|$k')) EksikKonu(d.ad, k, null, 0),
    ];
    return [...zayif, ...calisilmamis];
  }
}
