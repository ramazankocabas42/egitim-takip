import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import 'takip_db.dart';

int _int(dynamic v, [int vars = 0]) => v is num ? v.toInt() : vars;
String _str(dynamic v) => v == null ? '' : v.toString();

/// Etkinlik türleri: kimlik, ad, ikon, renk.
class EtkinlikTuru {
  const EtkinlikTuru(this.id, this.ad, this.ikon, this.renk);
  final String id;
  final String ad;
  final IconData ikon;
  final Color renk;
}

const etkinlikTurleri = <EtkinlikTuru>[
  EtkinlikTuru('okul', 'Okul', Icons.school, Color(0xFF283593)),
  EtkinlikTuru('dershane', 'Dershane / Kurs', Icons.apartment, Color(0xFF00897B)),
  EtkinlikTuru('etut', 'Etüt / Özel ders', Icons.co_present_outlined, Color(0xFF6D4C41)),
  EtkinlikTuru('spor', 'Spor / Sanat', Icons.sports_soccer, Color(0xFFEF6C00)),
  EtkinlikTuru('dini', 'Kuran kursu / Dini', Icons.mosque_outlined, Color(0xFF558B2F)),
  EtkinlikTuru('aile', 'Aile / Ziyaret', Icons.family_restroom, Color(0xFFAD1457)),
  EtkinlikTuru('diger', 'Diğer', Icons.event_note, Color(0xFF546E7A)),
];

EtkinlikTuru etkinlikTuru(String id) =>
    etkinlikTurleri.firstWhere((t) => t.id == id, orElse: () => etkinlikTurleri.last);

String saatYaz(int dk) {
  final d = ((dk % 1440) + 1440) % 1440;
  return '${(d ~/ 60).toString().padLeft(2, '0')}:${(d % 60).toString().padLeft(2, '0')}';
}

/// Haftalık tekrarlanan bir meşguliyet (okul, dershane, kurs ...).
class ProgramEtkinligi {
  ProgramEtkinligi({
    required this.id,
    required this.ad,
    required this.tur,
    required this.gunler,
    required this.bas,
    required this.bit,
    required this.createdBy,
  });

  final String id;
  final String ad;
  final String tur;
  final List<int> gunler; // 0 = Pazartesi
  final int bas; // gün içindeki dakika
  final int bit;
  final String createdBy;

  int get sure => bit - bas;

  factory ProgramEtkinligi.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    final g = m['gunler'];
    return ProgramEtkinligi(
      id: d.id,
      ad: _str(m['ad']),
      tur: _str(m['tur']).isEmpty ? 'diger' : _str(m['tur']),
      gunler: g is List ? (g.map((e) => _int(e)).where((e) => e >= 0 && e < 7).toList()..sort()) : [],
      bas: _int(m['bas']),
      bit: _int(m['bit']),
      createdBy: _str(m['createdBy']),
    );
  }
}

/// Uyku, yemek ve günlük çalışma hedefi gibi kişisel ayarlar.
class GunDuzeni {
  const GunDuzeni({
    this.haftaIciKalkis = 7 * 60,
    this.haftaIciYatma = 22 * 60 + 30,
    this.haftaSonuKalkis = 9 * 60,
    this.haftaSonuYatma = 23 * 60,
    this.yemekBas = 19 * 60,
    this.yemekDk = 45,
    this.yolDk = 20,
    this.dinlenmeDk = 30,
    this.hedefHaftaIci = 180,
    this.hedefHaftaSonu = 300,
  });

  final int haftaIciKalkis, haftaIciYatma, haftaSonuKalkis, haftaSonuYatma;
  final int yemekBas, yemekDk;
  final int yolDk; // etkinlik öncesi/sonrası yol, hazırlık
  final int dinlenmeDk; // etkinlik dönüşü mola
  final int hedefHaftaIci, hedefHaftaSonu; // günlük çalışma hedefi (dk)

  bool haftaSonu(int g) => g >= 5;
  int kalkis(int g) => haftaSonu(g) ? haftaSonuKalkis : haftaIciKalkis;
  int yatma(int g) => haftaSonu(g) ? haftaSonuYatma : haftaIciYatma;
  int hedef(int g) => haftaSonu(g) ? hedefHaftaSonu : hedefHaftaIci;

  Map<String, dynamic> toMap() => {
        'haftaIciKalkis': haftaIciKalkis,
        'haftaIciYatma': haftaIciYatma,
        'haftaSonuKalkis': haftaSonuKalkis,
        'haftaSonuYatma': haftaSonuYatma,
        'yemekBas': yemekBas,
        'yemekDk': yemekDk,
        'yolDk': yolDk,
        'dinlenmeDk': dinlenmeDk,
        'hedefHaftaIci': hedefHaftaIci,
        'hedefHaftaSonu': hedefHaftaSonu,
      };

  factory GunDuzeni.fromMap(Map<String, dynamic>? m) {
    const v = GunDuzeni();
    if (m == null) return v;
    return GunDuzeni(
      haftaIciKalkis: _int(m['haftaIciKalkis'], v.haftaIciKalkis),
      haftaIciYatma: _int(m['haftaIciYatma'], v.haftaIciYatma),
      haftaSonuKalkis: _int(m['haftaSonuKalkis'], v.haftaSonuKalkis),
      haftaSonuYatma: _int(m['haftaSonuYatma'], v.haftaSonuYatma),
      yemekBas: _int(m['yemekBas'], v.yemekBas),
      yemekDk: _int(m['yemekDk'], v.yemekDk),
      yolDk: _int(m['yolDk'], v.yolDk),
      dinlenmeDk: _int(m['dinlenmeDk'], v.dinlenmeDk),
      hedefHaftaIci: _int(m['hedefHaftaIci'], v.hedefHaftaIci),
      hedefHaftaSonu: _int(m['hedefHaftaSonu'], v.hedefHaftaSonu),
    );
  }

  GunDuzeni kopya(Map<String, int> d) => GunDuzeni.fromMap({...toMap(), ...d});
}

// ---------------------------------------------------------------------------
// Zaman analizi
// ---------------------------------------------------------------------------
/// Gün içindeki bir zaman dilimi.
class Aralik {
  const Aralik(this.bas, this.bit, {this.ad = '', this.tur = ''});
  final int bas, bit;
  final String ad;

  /// Etkinlik türü; 'bos', 'calisma', 'yemek', 'hazirlik', 'yol'
  final String tur;
  int get sure => bit - bas;
}

class GunAnalizi {
  GunAnalizi({
    required this.gun,
    required this.kalkis,
    required this.yatma,
    required this.dolu,
    required this.bos,
    required this.calisma,
  });

  final int gun;
  final int kalkis, yatma;
  final List<Aralik> dolu; // etkinlikler (+ yemek)
  final List<Aralik> bos; // yol/dinlenme payları düşülmüş boş zaman
  final List<Aralik> calisma; // önerilen çalışma blokları

  int sureOf(String tur) =>
      dolu.where((a) => a.tur == tur).fold(0, (s, a) => s + a.sure);
  int get bosDk => bos.fold(0, (s, a) => s + a.sure);
  int get calismaDk => calisma.fold(0, (s, a) => s + a.sure);
  int get etkinlikDk =>
      dolu.where((a) => a.tur != 'yemek').fold(0, (s, a) => s + a.sure);

  /// Zaman çizelgesi için hepsi sıralı (boşlar çalışma dışı kalan kısım).
  List<Aralik> get akis {
    final l = <Aralik>[...dolu, ...calisma];
    // Boş zamanın çalışma dışında kalan kısımları
    for (final b in bos) {
      var t = b.bas;
      for (final c in calisma.where((c) => c.bas >= b.bas && c.bit <= b.bit)) {
        if (c.bas > t) l.add(Aralik(t, c.bas, tur: 'bos'));
        t = c.bit;
      }
      if (b.bit > t) l.add(Aralik(t, b.bit, tur: 'bos'));
    }
    l.sort((a, b) => a.bas.compareTo(b.bas));
    return l;
  }
}

class ZamanMotoru {
  ZamanMotoru(this.etkinlikler, this.duzen);

  final List<ProgramEtkinligi> etkinlikler;
  final GunDuzeni duzen;

  static const blok = 40, mola = 10, sabahHazirlik = 45, enAzPencere = 30;

  /// [gunPlani]: o günün çalışma planı blokları (varsa ders adları yazılır).
  GunAnalizi analiz(int g, {List<PlanBlok> gunPlani = const []}) {
    final kalkis = duzen.kalkis(g), yatma = duzen.yatma(g);
    final dolu = <Aralik>[
      for (final e in etkinlikler.where((e) => e.gunler.contains(g) && e.bit > e.bas))
        Aralik(e.bas, e.bit, ad: e.ad, tur: e.tur),
    ];
    if (duzen.yemekDk > 0) {
      dolu.add(Aralik(duzen.yemekBas, duzen.yemekBas + duzen.yemekDk,
          ad: 'Akşam yemeği', tur: 'yemek'));
    }
    dolu.sort((a, b) => a.bas.compareTo(b.bas));

    // Meşgul aralıklar: etkinlik ± yol, dönüşte dinlenme; sabah hazırlığı.
    final mesgul = <List<int>>[
      [kalkis, kalkis + sabahHazirlik],
      for (final a in dolu)
        a.tur == 'yemek'
            ? [a.bas, a.bit]
            : [a.bas - duzen.yolDk, a.bit + duzen.yolDk + duzen.dinlenmeDk],
    ]..sort((a, b) => a[0].compareTo(b[0]));
    final bos = <Aralik>[];
    var t = kalkis;
    for (final m in mesgul) {
      final bas = m[0] < kalkis ? kalkis : m[0];
      if (bas - t >= enAzPencere) bos.add(Aralik(t, bas > yatma ? yatma : bas, tur: 'bos'));
      if (m[1] > t) t = m[1];
      if (t >= yatma) break;
    }
    if (yatma - t >= enAzPencere) bos.add(Aralik(t, yatma, tur: 'bos'));

    // Çalışma blokları: hedef süreye kadar, en az 1 saat serbest zaman kalsın.
    final toplamBos = bos.fold(0, (s, a) => s + a.sure);
    var kalan = duzen.hedef(g);
    if (toplamBos - kalan < 60) kalan = toplamBos - 60;
    final calisma = <Aralik>[];
    var p = 0;
    // Akşamüstü/akşam pencereleri önce (okul öncesi sabah en sona).
    final sirali = List.of(bos)
      ..sort((a, b) {
        final sa = a.bas < 10 * 60 ? 1 : 0, sb = b.bas < 10 * 60 ? 1 : 0;
        if (sa != sb) return sa.compareTo(sb);
        return a.bas.compareTo(b.bas);
      });
    for (final b in sirali) {
      var s = b.bas;
      while (kalan >= 25 && b.bit - s >= 25) {
        final dk = [blok, kalan, b.bit - s].reduce((x, y) => x < y ? x : y);
        if (dk < 25) break;
        final pb = p < gunPlani.length ? gunPlani[p] : null;
        p++;
        calisma.add(Aralik(s, s + dk,
            ad: pb == null ? 'Ders çalışma' : pb.ders,
            tur: 'calisma'));
        kalan -= dk;
        s += dk + mola;
      }
    }
    calisma.sort((a, b) => a.bas.compareTo(b.bas));
    return GunAnalizi(
        gun: g, kalkis: kalkis, yatma: yatma, dolu: dolu, bos: bos, calisma: calisma);
  }

  List<GunAnalizi> hafta({HaftalikPlan? plan}) => [
        for (var g = 0; g < 7; g++) analiz(g, gunPlani: plan?.gunler[g] ?? const []),
      ];
}

// ---------------------------------------------------------------------------
// Firestore
// ---------------------------------------------------------------------------
class ProgramDb {
  ProgramDb._();

  static CollectionReference<Map<String, dynamic>> _sub(String sid, String ad) =>
      FirebaseFirestore.instance.collection('students').doc(sid).collection(ad);

  static Stream<List<ProgramEtkinligi>> etkinlikler(String sid) =>
      _sub(sid, 'programEtkinlikleri').snapshots().map((s) {
        final l = s.docs.map(ProgramEtkinligi.fromDoc).toList()
          ..sort((a, b) {
            final c = etkinlikTurleri
                .indexWhere((t) => t.id == a.tur)
                .compareTo(etkinlikTurleri.indexWhere((t) => t.id == b.tur));
            return c != 0 ? c : a.bas.compareTo(b.bas);
          });
        return l;
      });

  static Future<void> etkinlikKaydet(
    String sid,
    AppUser me, {
    String? id,
    required String ad,
    required String tur,
    required List<int> gunler,
    required int bas,
    required int bit,
  }) {
    final veri = {'ad': ad, 'tur': tur, 'gunler': gunler, 'bas': bas, 'bit': bit};
    if (id == null) {
      return _sub(sid, 'programEtkinlikleri').add({
        ...veri,
        'createdBy': me.uid,
        'createdAt': Timestamp.now(),
      });
    }
    return _sub(sid, 'programEtkinlikleri')
        .doc(id)
        .update({...veri, 'updatedAt': Timestamp.now()});
  }

  static Future<void> etkinlikSil(String sid, String id) =>
      _sub(sid, 'programEtkinlikleri').doc(id).delete();

  static DocumentReference<Map<String, dynamic>> _duzenRef(String sid) =>
      _sub(sid, 'ayarlar').doc('gunDuzeni');

  static Stream<GunDuzeni> duzen(String sid) =>
      _duzenRef(sid).snapshots().map((d) => GunDuzeni.fromMap(d.data()));

  static Future<void> duzenKaydet(String sid, AppUser me, GunDuzeni d) async {
    final ref = _duzenRef(sid);
    final mevcut = await ref.get();
    if (mevcut.exists) {
      await ref.update({...d.toMap(), 'updatedAt': Timestamp.now()});
    } else {
      await ref.set({...d.toMap(), 'createdBy': me.uid, 'createdAt': Timestamp.now()});
    }
  }
}
