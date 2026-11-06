import 'package:cloud_firestore/cloud_firestore.dart';

import '../lgs.dart';
import '../models.dart';

DateTime? _ts(dynamic v) => v is Timestamp ? v.toDate() : null;
String _str(dynamic v) => v == null ? '' : v.toString();
int _int(dynamic v) => v is num ? v.toInt() : 0;

// ---------------------------------------------------------------------------
// Günlük soru girişi
// ---------------------------------------------------------------------------
class SoruGirisi {
  SoruGirisi({
    required this.id,
    required this.tur,
    required this.tarih,
    required this.dersler,
    required this.ders,
    required this.konu,
    required this.sonuc,
    required this.sure,
    required this.not,
    required this.createdBy,
    required this.createdByName,
  });

  final String id;

  /// 'karma' (ders ders toplu giriş) ya da 'konu' (tek konu)
  final String tur;
  final DateTime tarih;
  final Map<String, Dyb> dersler;
  final String ders;
  final String konu;
  final Dyb sonuc;
  final int sure; // dakika
  final String not;
  final String createdBy;
  final String createdByName;

  bool get karma => tur != 'konu';

  /// Ders adı -> sonuç (konu girişinde tek ders).
  Map<String, Dyb> get dersBazli =>
      karma ? dersler : {if (ders.isNotEmpty) ders: sonuc};

  Dyb get toplam =>
      dersBazli.values.fold<Dyb>(Dyb.bos, (a, b) => a + b);

  factory SoruGirisi.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return SoruGirisi(
      id: d.id,
      tur: _str(m['tur']).isEmpty ? 'karma' : _str(m['tur']),
      tarih: _ts(m['tarih']) ?? _ts(m['createdAt']) ?? DateTime.now(),
      dersler: dersHaritasi(m['dersler']),
      ders: _str(m['ders']),
      konu: _str(m['konu']),
      sonuc: Dyb.fromMap(m['sonuc']),
      sure: _int(m['sure']),
      not: _str(m['not']),
      createdBy: _str(m['createdBy']),
      createdByName: _str(m['createdByName']),
    );
  }
}

// ---------------------------------------------------------------------------
// LGS denemesi
// ---------------------------------------------------------------------------
class LgsDeneme {
  LgsDeneme({
    required this.id,
    required this.ad,
    required this.yayin,
    required this.tarih,
    required this.puan,
    required this.dersler,
    required this.createdBy,
    this.smsAnahtar = '',
  });

  final String id;
  final String smsAnahtar;
  final String ad;
  final String yayin;
  final DateTime tarih;

  /// Deneme sonuç belgesindeki puan (girilmediyse null).
  final double? puan;
  final Map<String, Dyb> dersler;
  final String createdBy;

  double get tahminiPuan => lgsTahminiPuan(dersler);
  double get gosterilenPuan => puan ?? tahminiPuan;
  Dyb get toplam => dersler.values.fold<Dyb>(Dyb.bos, (a, b) => a + b);
  double get toplamNet =>
      dersler.values.fold<double>(0, (a, b) => a + (b.net < 0 ? 0 : b.net));

  factory LgsDeneme.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return LgsDeneme(
      id: d.id,
      ad: _str(m['ad']),
      yayin: _str(m['yayin']),
      tarih: _ts(m['tarih']) ?? DateTime.now(),
      puan: m['puan'] is num ? (m['puan'] as num).toDouble() : null,
      dersler: dersHaritasi(m['dersler']),
      createdBy: _str(m['createdBy']),
      smsAnahtar: _str(m['smsAnahtar']),
    );
  }
}

class LgsHedef {
  const LgsHedef({this.puan, this.okul = ''});

  final double? puan;
  final String okul;
}

// ---------------------------------------------------------------------------
// Haftalık plan
// ---------------------------------------------------------------------------
class PlanBlok {
  const PlanBlok({
    required this.ders,
    this.konu = '',
    required this.dakika,
    this.tamam = false,
  });

  final String ders;
  final String konu;
  final int dakika;
  final bool tamam;

  PlanBlok kopya({bool? tamam, String? ders, String? konu, int? dakika}) =>
      PlanBlok(
        ders: ders ?? this.ders,
        konu: konu ?? this.konu,
        dakika: dakika ?? this.dakika,
        tamam: tamam ?? this.tamam,
      );

  Map<String, dynamic> toMap() =>
      {'ders': ders, 'konu': konu, 'dakika': dakika, 'tamam': tamam};

  factory PlanBlok.fromMap(dynamic m) => m is Map
      ? PlanBlok(
          ders: _str(m['ders']),
          konu: _str(m['konu']),
          dakika: _int(m['dakika']),
          tamam: m['tamam'] == true,
        )
      : const PlanBlok(ders: '', dakika: 0);
}

class HaftalikPlan {
  HaftalikPlan({required this.hafta, required this.gunler, this.adaptif = false});

  final String hafta; // Pazartesi tarihi, yyyy-mm-dd
  final List<List<PlanBlok>> gunler; // 7 gün
  final bool adaptif;

  static HaftalikPlan bos(String hafta) =>
      HaftalikPlan(hafta: hafta, gunler: List.generate(7, (_) => <PlanBlok>[]));

  int gunDakika(int g) => gunler[g].fold(0, (a, b) => a + b.dakika);
  int get toplamDakika => List.generate(7, gunDakika).fold(0, (a, b) => a + b);
  int get tamamDakika => gunler
      .expand((g) => g)
      .where((b) => b.tamam)
      .fold(0, (a, b) => a + b.dakika);
  double get tamamOrani => toplamDakika == 0 ? 0 : tamamDakika / toplamDakika;

  Map<String, dynamic> gunlerMap() => {
        for (var i = 0; i < 7; i++)
          '$i': gunler[i].map((b) => b.toMap()).toList(),
      };

  factory HaftalikPlan.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    final g = m['gunler'];
    return HaftalikPlan(
      hafta: d.id,
      adaptif: m['adaptif'] == true,
      gunler: List.generate(7, (i) {
        final l = g is Map ? g['$i'] : null;
        return l is List ? l.map(PlanBlok.fromMap).toList() : <PlanBlok>[];
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Firestore işlemleri
// ---------------------------------------------------------------------------
class TakipDb {
  TakipDb._();

  static CollectionReference<Map<String, dynamic>> _sub(String sid, String ad) =>
      FirebaseFirestore.instance.collection('students').doc(sid).collection(ad);

  static DocumentReference<Map<String, dynamic>> _ayar(String sid, String id) =>
      _sub(sid, 'ayarlar').doc(id);

  /// Ayar belgesini yazar: yoksa oluşturur (createdBy ile), varsa günceller.
  static Future<void> _ayarYaz(DocumentReference<Map<String, dynamic>> ref,
      AppUser me, Map<String, dynamic> veri) async {
    final mevcut = await ref.get();
    if (mevcut.exists) {
      await ref.update({...veri, 'updatedAt': Timestamp.now()});
    } else {
      await ref.set({
        ...veri,
        'createdBy': me.uid,
        'createdAt': Timestamp.now(),
      });
    }
  }

  static Future<void> sil(String sid, String koleksiyon, String id) =>
      _sub(sid, koleksiyon).doc(id).delete();

  // ---- Soru girişleri ----
  static Stream<List<SoruGirisi>> sorular(String sid) => _sub(sid, 'soruGirisleri')
      .orderBy('tarih', descending: true)
      .limit(400)
      .snapshots()
      .map((s) => s.docs.map(SoruGirisi.fromDoc).toList());

  static Future<void> soruKaydet(
    String sid,
    AppUser me, {
    String? id,
    required String tur,
    required DateTime tarih,
    Map<String, Dyb> dersler = const {},
    String ders = '',
    String konu = '',
    Dyb sonuc = Dyb.bos,
    int sure = 0,
    String not = '',
  }) {
    final veri = <String, dynamic>{
      'tur': tur,
      'tarih': Timestamp.fromDate(DateTime(tarih.year, tarih.month, tarih.day, 12)),
      'dersler': dersHaritasiYaz(dersler),
      'ders': ders,
      'konu': konu,
      'sonuc': sonuc.toMap(),
      'sure': sure,
      'not': not,
    };
    if (id == null) {
      return _sub(sid, 'soruGirisleri').add({
        ...veri,
        'createdBy': me.uid,
        'createdByName': me.name,
        'createdAt': Timestamp.now(),
      });
    }
    return _sub(sid, 'soruGirisleri')
        .doc(id)
        .update({...veri, 'updatedAt': Timestamp.now()});
  }

  // ---- LGS denemeleri ----
  static Stream<List<LgsDeneme>> denemeler(String sid) => _sub(sid, 'lgsDenemeleri')
      .orderBy('tarih', descending: true)
      .snapshots()
      .map((s) => s.docs.map(LgsDeneme.fromDoc).toList());

  static Future<void> denemeKaydet(
    String sid,
    AppUser me, {
    String? id,
    required String ad,
    required String yayin,
    required DateTime tarih,
    required double? puan,
    required Map<String, Dyb> dersler,
    String kaynak = 'elle',
    String smsAnahtar = '',
  }) {
    final veri = <String, dynamic>{
      'ad': ad,
      'yayin': yayin,
      'tarih': Timestamp.fromDate(DateTime(tarih.year, tarih.month, tarih.day, 12)),
      'puan': puan,
      'dersler': dersHaritasiYaz(dersler),
    };
    if (id == null) {
      return _sub(sid, 'lgsDenemeleri').add({
        ...veri,
        'kaynak': kaynak,
        if (smsAnahtar.isNotEmpty) 'smsAnahtar': smsAnahtar,
        'createdBy': me.uid,
        'createdAt': Timestamp.now(),
      });
    }
    return _sub(sid, 'lgsDenemeleri')
        .doc(id)
        .update({...veri, 'updatedAt': Timestamp.now()});
  }

  static Stream<LgsHedef> hedef(String sid) =>
      _ayar(sid, 'lgsHedef').snapshots().map((d) {
        final m = d.data() ?? const <String, dynamic>{};
        return LgsHedef(
          puan: m['puan'] is num ? (m['puan'] as num).toDouble() : null,
          okul: _str(m['okul']),
        );
      });

  static Future<void> hedefKaydet(
          String sid, AppUser me, double? puan, String okul) =>
      _ayarYaz(_ayar(sid, 'lgsHedef'), me, {'puan': puan, 'okul': okul});

  // ---- SMS aktarımı: işlenen mesajlar ----
  static Future<Set<String>> smsIslenenler(String sid) async {
    final d = await _ayar(sid, 'smsAktarim').get();
    final l = d.data()?['islenenler'];
    return l is List ? l.map((e) => e.toString()).toSet() : <String>{};
  }

  static Future<void> smsIslendi(String sid, AppUser me, String anahtar) =>
      _ayarYaz(_ayar(sid, 'smsAktarim'), me, {
        'islenenler': FieldValue.arrayUnion([anahtar]),
      });

  // ---- Müsaitlik ----
  static const varsayilanMusaitlik = [90, 90, 90, 90, 60, 180, 120];

  static Stream<List<int>> musaitlik(String sid) =>
      _ayar(sid, 'musaitlik').snapshots().map((d) {
        final l = d.data()?['dakikalar'];
        if (l is List && l.length == 7) return l.map(_int).toList();
        return List.of(varsayilanMusaitlik);
      });

  static Future<void> musaitlikKaydet(String sid, AppUser me, List<int> dk) =>
      _ayarYaz(_ayar(sid, 'musaitlik'), me, {'dakikalar': dk});

  // ---- Haftalık plan ----
  static Stream<HaftalikPlan?> plan(String sid, String hafta) =>
      _sub(sid, 'haftalikPlan').doc(hafta).snapshots().map(
          (d) => d.exists ? HaftalikPlan.fromDoc(d) : null);

  static Future<HaftalikPlan?> planGetir(String sid, String hafta) async {
    try {
      final d = await _sub(sid, 'haftalikPlan').doc(hafta).get();
      return d.exists ? HaftalikPlan.fromDoc(d) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> planKaydet(String sid, AppUser me, HaftalikPlan p) =>
      _ayarYaz(_sub(sid, 'haftalikPlan').doc(p.hafta), me, {
        'hafta': p.hafta,
        'adaptif': p.adaptif,
        'gunler': p.gunlerMap(),
      });
}
