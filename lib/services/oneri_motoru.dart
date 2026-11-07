import 'package:flutter/material.dart';

import '../lgs.dart';
import '../models.dart';
import 'okul_db.dart';
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
  EksikKonu(this.ders, this.konu, this.basari, this.soru);
  final String ders;
  final String konu;
  final double? basari; // null: hiç çalışılmamış
  final int soru;
}

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
    DateTime? simdi,
  }) : simdi = simdi ?? DateTime.now();

  final List<SoruGirisi> sorular;
  final List<LgsDeneme> denemeler; // yeniden eskiye
  final LgsHedef? hedef;
  final List<OkulSinav> okulNotlari;
  final List<Homework> odevler;
  final HaftalikPlan? plan; // bu hafta
  final List<GunAnalizi>? programHaftasi; // etkinlik girilmediyse null
  final DateTime simdi;

  static const gunlukSoruHedefi = 60;

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
    final son3 = denemeler.take(3).toList();
    double? denemeSkor;
    double? ortPuan, ortNet;
    if (son3.isNotEmpty) {
      ortNet = son3.fold<double>(0, (s, d) => s + d.toplamNet) / son3.length;
      ortPuan = son3.fold<double>(0, (s, d) => s + d.gosterilenPuan) / son3.length;
      final netSkor = (ortNet / 90 * 100).clamp(0, 100).toDouble();
      final h = hedef?.puan;
      denemeSkor = h != null && h > 0
          ? (netSkor + (ortPuan / h * 100).clamp(0, 100)) / 2
          : netSkor;
    }
    alanlar.add(Alan(
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
    alanlar.add(Alan(
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
      haftalikCalisma == null ? null : (haftalikCalisma / 600 * 100).clamp(0, 100).toDouble(),
      haftalikCalisma == null ? '—' : sureYaz(haftalikCalisma),
      haftalikCalisma == null
          ? 'Program sekmesine okul/dershane saatleri girilmemiş.'
          : 'Haftalık programda ders çalışmaya ayrılabilecek süre.',
      0.05,
    ));

    // ---- Ders öncelikleri ----
    final motor = PlanMotoru(sorular: sorular, denemeler: denemeler, simdi: simdi);
    final durum = motor.dersDurumlari()..sort((a, b) => b.ihtiyac.compareTo(a.ihtiyac));
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
      neden.add(d.soru == 0 ? '14 günde soru yok' : '14 günde ${d.soru} soru');
      if (d.ders.katsayi == 4) neden.add('katsayı 4');
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
    final h = hedef?.puan;
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
    } else if (h == null && son3.isNotEmpty) {
      oneriler.add(Oneri(Onem.bilgi, Icons.flag_outlined,
          'LGS Deneme sekmesinden hedef puan girerseniz hedefe olan mesafe de hesaplanır.'));
    }

    if (denemeler.length >= 4) {
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
    for (final d in lgsDersler) {
      final t = son3.fold<Dyb>(Dyb.bos, (a, x) => a + (x.dersler[d.ad] ?? Dyb.bos));
      if (t.d + t.y < 6) continue;
      final yOran = t.y / (t.d + t.y);
      if (yOran >= 0.3) {
        oneriler.add(Oneri(Onem.onemli, Icons.close,
            '${d.ad} denemelerinde yanlış oranı yüksek (%${(yOran * 100).round()}). '
            '3 yanlış 1 doğruyu götürür: emin olmadığın soruyu boş bırak, yanlışları deftere yaz.'));
      }
    }

    final zayifKonu = eksikKonular.where((k) => k.basari != null).take(4).toList();
    if (zayifKonu.isNotEmpty) {
      oneriler.add(Oneri(
          Onem.onemli,
          Icons.replay,
          'Tekrar edilmesi gereken konular: '
          '${zayifKonu.map((k) => '${k.konu} (%${(k.basari! * 100).round()})').join(', ')}.'));
    }

    if (sorular.isNotEmpty && gunluk < 40) {
      oneriler.add(Oneri(gunluk < 20 ? Onem.kritik : Onem.onemli, Icons.speed,
          'Son 14 günde günde ortalama ${gunluk.round()} soru çözülmüş. LGS için günde '
          '$gunlukSoruHedefi-80 soru hedeflenmeli.'));
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
          'Okulda ${z.$1} ortalaması ${z.$2.toStringAsFixed(1)}. Takdir/teşekkür için bu derse destek gerekli.'));
    }

    if (ph != null) {
      final sifir = ph.where((g) => g.calismaDk == 0).map((g) => gunUzun[g.gun]).toList();
      if (sifir.isNotEmpty && sifir.length < 7) {
        oneriler.add(Oneri(Onem.bilgi, Icons.schedule,
            '${sifir.join(', ')} programda ders çalışmaya zaman kalmıyor; o günler dinlenme günü sayılabilir ya da kısa tekrar yapılabilir.'));
      }
      final hc = haftalikCalisma ?? 0;
      if (hc < 8 * 60) {
        oneriler.add(Oneri(Onem.onemli, Icons.hourglass_bottom,
            'Haftalık çalışmaya ayrılabilen süre ${sureYaz(hc)}. LGS dönemi için '
            'haftada 10-15 saat önerilir; hafta sonu saatlerini gözden geçirin.'));
      }
    } else {
      oneriler.add(Oneri(Onem.bilgi, Icons.schedule,
          'Program sekmesine okul ve dershane saatlerini girerseniz boş zamanlar ve çalışma saatleri hesaplanır.'));
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
    final calisilmamis = <EksikKonu>[
      for (final d in lgsDersler)
        for (final k in (lgsKonular[d.ad] ?? const <String>[]))
          if (!hic.contains('${d.ad}|$k')) EksikKonu(d.ad, k, null, 0),
    ];
    return [...zayif, ...calisilmamis];
  }
}
