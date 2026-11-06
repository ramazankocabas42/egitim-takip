import '../lgs.dart';
import 'takip_db.dart';

/// Bir dersin son verilere göre durumu.
class DersDurumu {
  DersDurumu(this.ders, this.basari, this.soru, this.ihtiyac);

  final LgsDers ders;
  final double? basari; // 0-1, veri yoksa null
  final int soru; // son 14 günde çözülen
  final double ihtiyac; // planda alacağı pay
}

/// Öğrencinin verilerinden haftalık çalışma planı üretir.
///
/// - Her günün müsait süresi 40 dakikalık bloklara bölünür.
/// - Bloklar derslere "ihtiyaç" oranında dağıtılır: LGS katsayısı yüksek,
///   başarısı düşük ve az çalışılan dersler daha çok blok alır.
/// - Her bloğa, konu bazlı girişlerde başarısı en düşük konular ve sonra
///   müfredat sırasındaki konular atanır.
class PlanMotoru {
  PlanMotoru({
    required this.sorular,
    required this.denemeler,
    DateTime? simdi,
  }) : simdi = simdi ?? DateTime.now();

  final List<SoruGirisi> sorular;
  final List<LgsDeneme> denemeler;
  final DateTime simdi;

  static const blokDakika = 40;

  List<DersDurumu> dersDurumlari() {
    final sinir = simdi.subtract(const Duration(days: 14));
    final son = sorular.where((e) => e.tarih.isAfter(sinir));
    final top = <String, Dyb>{};
    for (final e in son) {
      e.dersBazli.forEach((k, v) => top[k] = (top[k] ?? Dyb.bos) + v);
    }
    final son3 = denemeler.take(3).toList();

    return lgsDersler.map((d) {
      final oranlar = <double>[];
      final s = top[d.ad];
      if (s != null && s.toplam >= 5) oranlar.add(s.basari);
      if (son3.isNotEmpty) {
        final n = son3.fold<double>(0, (a, x) {
              final v = x.dersler[d.ad]?.net ?? 0;
              return a + (v < 0 ? 0 : v);
            }) /
            son3.length;
        oranlar.add(n / d.soru);
      }
      final basari =
          oranlar.isEmpty ? null : oranlar.reduce((a, b) => a + b) / oranlar.length;
      final agirlik = d.katsayi == 4 ? 1.0 : 0.35;
      var ihtiyac = agirlik * (1.15 - (basari ?? 0.55));
      if ((s?.toplam ?? 0) < 20) ihtiyac += 0.12 * agirlik; // az çalışılmış
      return DersDurumu(d, basari, s?.toplam ?? 0, ihtiyac);
    }).toList();
  }

  /// Ders -> sıralı konu listesi (önce zayıf konular, sonra müfredat sırası).
  Map<String, List<String>> _konuSirasi() {
    final sinir = simdi.subtract(const Duration(days: 30));
    final konu = <String, Map<String, Dyb>>{};
    final sonCalisma = <String, DateTime>{};
    for (final e in sorular.where((e) => !e.karma)) {
      final k = '${e.ders}|${e.konu}';
      final onceki = sonCalisma[k];
      if (onceki == null || e.tarih.isAfter(onceki)) sonCalisma[k] = e.tarih;
      if (e.tarih.isBefore(sinir)) continue;
      konu.putIfAbsent(e.ders, () => {});
      konu[e.ders]![e.konu] = (konu[e.ders]![e.konu] ?? Dyb.bos) + e.sonuc;
    }
    final out = <String, List<String>>{};
    for (final d in lgsDersler) {
      final zayif = (konu[d.ad] ?? const <String, Dyb>{})
          .entries
          .where((e) => e.value.toplam >= 3 && e.value.basari < 0.75)
          .toList()
        ..sort((a, b) => a.value.basari.compareTo(b.value.basari));
      final mufredat = List.of(lgsKonular[d.ad] ?? const <String>[])
        // Uzun süredir (ya da hiç) çalışılmayan konular öne
        ..sort((a, b) {
          final ta = sonCalisma['${d.ad}|$a'];
          final tb = sonCalisma['${d.ad}|$b'];
          if (ta == null && tb == null) return 0;
          if (ta == null) return -1;
          if (tb == null) return 1;
          return ta.compareTo(tb);
        });
      out[d.ad] = [
        ...zayif.map((e) => e.key),
        ...mufredat.where((k) => !zayif.any((z) => z.key == k)),
      ];
    }
    return out;
  }

  HaftalikPlan uret(String hafta, List<int> musaitlik) {
    // 1) Günleri bloklara böl
    final gunBloklari = List.generate(7, (g) {
      final dk = musaitlik[g];
      final out = <int>[];
      if (dk >= 20) {
        final tam = dk ~/ blokDakika;
        final kalan = dk % blokDakika;
        for (var i = 0; i < tam; i++) {
          out.add(blokDakika);
        }
        if (kalan >= 20) {
          out.add(kalan);
        } else if (kalan > 0 && out.isNotEmpty) {
          out[out.length - 1] += kalan;
        }
      }
      return out;
    });
    final toplamBlok = gunBloklari.fold<int>(0, (a, b) => a + b.length);
    if (toplamBlok == 0) return HaftalikPlan.bos(hafta);

    // 2) Blokları derslere dağıt (en büyük kalan yöntemi)
    final durum = dersDurumlari();
    final toplamIhtiyac = durum.fold<double>(0, (a, b) => a + b.ihtiyac);
    final kota = <String, int>{};
    final kesir = <String, double>{};
    var dagitilan = 0;
    for (final d in durum) {
      final pay = toplamBlok * d.ihtiyac / toplamIhtiyac;
      kota[d.ders.ad] = pay.floor();
      kesir[d.ders.ad] = pay - pay.floor();
      dagitilan += pay.floor();
    }
    final sirali = kesir.keys.toList()
      ..sort((a, b) => kesir[b]!.compareTo(kesir[a]!));
    for (var i = 0; dagitilan < toplamBlok; i++) {
      kota[sirali[i % sirali.length]] = kota[sirali[i % sirali.length]]! + 1;
      dagitilan++;
    }
    // Yeterli blok varsa her ders haftada en az bir kez çalışılsın.
    if (toplamBlok >= lgsDersler.length) {
      for (final d in lgsDersler) {
        if (kota[d.ad] == 0) {
          final enCok =
              kota.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
          kota[enCok] = kota[enCok]! - 1;
          kota[d.ad] = 1;
        }
      }
    }

    // 3) Günlere yerleştir: aynı gün aynı ders tekrar etmesin (mümkünse)
    final konuSirasi = _konuSirasi();
    final konuIndeks = <String, int>{};
    final gunler = List.generate(7, (_) => <PlanBlok>[]);
    for (var g = 0; g < 7; g++) {
      final bugun = <String>{};
      for (final dk in gunBloklari[g]) {
        final adaylar = kota.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) {
            final ta = bugun.contains(a.key) ? 1 : 0;
            final tb = bugun.contains(b.key) ? 1 : 0;
            if (ta != tb) return ta.compareTo(tb);
            return b.value.compareTo(a.value);
          });
        if (adaylar.isEmpty) break;
        final ders = adaylar.first.key;
        kota[ders] = kota[ders]! - 1;
        bugun.add(ders);
        final liste = konuSirasi[ders] ?? const <String>[];
        final i = konuIndeks[ders] ?? 0;
        konuIndeks[ders] = i + 1;
        gunler[g].add(PlanBlok(
          ders: ders,
          konu: liste.isEmpty ? '' : liste[i % liste.length],
          dakika: dk,
        ));
      }
    }
    return HaftalikPlan(hafta: hafta, gunler: gunler, adaptif: true);
  }
}

/// Geçen haftanın değerlendirmesi.
class KocDegerlendirmesi {
  KocDegerlendirmesi({
    required this.oncekiPlan,
    required this.sorular,
    required this.buHafta,
  });

  final HaftalikPlan? oncekiPlan;
  final List<SoruGirisi> sorular;
  final DateTime buHafta; // bu haftanın Pazartesi'si

  List<String> mesajlar() {
    final out = <String>[];
    final gecenBasi = buHafta.subtract(const Duration(days: 7));
    final ikiOnce = buHafta.subtract(const Duration(days: 14));

    Dyb aralik(DateTime a, DateTime b) => sorular
        .where((e) => !e.tarih.isBefore(a) && e.tarih.isBefore(b))
        .fold(Dyb.bos, (x, e) => x + e.toplam);

    final gecen = aralik(gecenBasi, buHafta);
    final once = aralik(ikiOnce, gecenBasi);

    final p = oncekiPlan;
    if (p != null && p.toplamDakika > 0) {
      final oran = (p.tamamOrani * 100).round();
      out.add(
          'Geçen hafta planın %$oran\'ini tamamladın (${sureYaz(p.tamamDakika)} / ${sureYaz(p.toplamDakika)}).');
      if (oran >= 85) {
        out.add('Harika bir disiplin! Bu hafta biraz daha zorlayıcı konulara yer açtık.');
      } else if (oran >= 50) {
        out.add('Fena değil. Yarım kalan blokları bu haftanın ilk günlerine kaydırmayı dene.');
      } else {
        out.add('Plan biraz yoğun gelmiş olabilir. Müsaitlik sürelerini gerçekçi '
            'güncelleyip planı yeniden hazırlamayı dene.');
      }
    }

    if (gecen.toplam > 0) {
      out.add('Geçen hafta ${gecen.toplam} soru çözdün, başarı '
          '%${(gecen.basari * 100).round()}.');
      if (once.toplam > 0) {
        final fark = gecen.toplam - once.toplam;
        if (fark > 0) {
          out.add('Bir önceki haftaya göre $fark soru daha fazla. Yükseliş sürüyor 📈');
        } else if (fark < 0) {
          out.add('Bir önceki haftaya göre ${-fark} soru daha az. Bu hafta telafi edelim.');
        }
        final bf = ((gecen.basari - once.basari) * 100).round();
        if (bf.abs() >= 3) {
          out.add(bf > 0
              ? 'Doğru oranın %$bf arttı 👏'
              : 'Doğru oranın %${-bf} düştü; yanlışlarını tekrar etmeyi unutma.');
        }
      }

      // Ders bazında en iyi / en zayıf
      final ders = <String, Dyb>{};
      for (final e in sorular.where(
          (e) => !e.tarih.isBefore(gecenBasi) && e.tarih.isBefore(buHafta))) {
        e.dersBazli.forEach((k, v) => ders[k] = (ders[k] ?? Dyb.bos) + v);
      }
      final yeterli = ders.entries.where((e) => e.value.toplam >= 10).toList()
        ..sort((a, b) => a.value.basari.compareTo(b.value.basari));
      if (yeterli.length >= 2) {
        out.add('En güçlü dersin: ${yeterli.last.key} '
            '(%${(yeterli.last.value.basari * 100).round()}). '
            'En çok destek gereken: ${yeterli.first.key} '
            '(%${(yeterli.first.value.basari * 100).round()}).');
      }
      final calisilmayan = lgsDersler
          .where((d) => (ders[d.ad]?.toplam ?? 0) == 0)
          .map((d) => d.ad)
          .toList();
      if (calisilmayan.isNotEmpty && calisilmayan.length < lgsDersler.length) {
        out.add('Geçen hafta hiç soru girilmeyen dersler: ${calisilmayan.join(', ')}.');
      }
    }
    return out;
  }
}
