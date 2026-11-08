import 'package:cloud_firestore/cloud_firestore.dart';

import '../models.dart';
import '../osym.dart';

int _int(dynamic v) => v is num ? v.toInt() : 0;
double? _dbl(dynamic v) => v is num ? v.toDouble() : null;
String _str(dynamic v) => v == null ? '' : v.toString();

/// Bir testin sonucu.
class TestSonucu {
  const TestSonucu({required this.soru, required this.d, required this.y});
  final int soru;
  final int d;
  final int y;
  int get b => (soru - d - y).clamp(0, 999);
  double net(int bolen) => d - y / bolen;
  double get basari => soru == 0 ? 0 : d / soru;

  Map<String, dynamic> toMap() => {'s': soru, 'd': d, 'y': y};
  factory TestSonucu.fromMap(Map m) =>
      TestSonucu(soru: _int(m['s']), d: _int(m['d']), y: _int(m['y']));
}

/// ÖSYM sınavı ya da deneme sonucu.
class OsymSonuc {
  OsymSonuc({
    required this.id,
    required this.tur,
    required this.ad,
    required this.tarih,
    required this.resmi,
    required this.kaynak,
    required this.testler,
    required this.puanlar,
    required this.konuHata,
    required this.createdBy,
  });

  final String id;
  final String tur; // TYT, AYT, YDT, KPSS, AGS, OABT
  final String ad;
  final DateTime tarih;
  final bool resmi; // ÖSYM sınavı mı (değilse deneme)
  final String kaynak; // elle | osym
  final Map<String, TestSonucu> testler;
  final Map<String, double> puanlar;

  /// "testId|konu" -> yanlış + boş sayısı
  final Map<String, int> konuHata;
  final String createdBy;

  OsymSinavTuru? get tanim => osymTuru(tur);
  int get bolen => tanim?.yanlisBolen ?? 4;

  double get toplamNet => testler.values.fold(0.0, (s, t) => s + t.net(bolen));
  int get toplamD => testler.values.fold(0, (s, t) => s + t.d);
  int get toplamY => testler.values.fold(0, (s, t) => s + t.y);
  int get toplamB => testler.values.fold(0, (s, t) => s + t.b);
  int get toplamSoru => testler.values.fold(0, (s, t) => s + t.soru);

  factory OsymSonuc.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    final t = m['testler'];
    final p = m['puanlar'];
    final k = m['konuHata'];
    final ts = m['tarih'];
    return OsymSonuc(
      id: d.id,
      tur: _str(m['tur']),
      ad: _str(m['ad']),
      tarih: ts is Timestamp ? ts.toDate() : DateTime(2000),
      resmi: m['resmi'] != false,
      kaynak: _str(m['kaynak']),
      testler: t is Map
          ? {for (final e in t.entries) e.key.toString(): TestSonucu.fromMap(e.value as Map)}
          : {},
      puanlar: p is Map
          ? {
              for (final e in p.entries)
                if (_dbl(e.value) != null) e.key.toString(): _dbl(e.value)!,
            }
          : {},
      konuHata: k is Map
          ? {for (final e in k.entries) e.key.toString(): _int(e.value)}
          : {},
      createdBy: _str(m['createdBy']),
    );
  }
}

class OsymDb {
  OsymDb._();

  static CollectionReference<Map<String, dynamic>> _col(String sid) =>
      FirebaseFirestore.instance.collection('students').doc(sid).collection('osymSinavlari');

  static Stream<List<OsymSonuc>> sonuclar(String sid) => _col(sid).snapshots().map(
      (s) => s.docs.map(OsymSonuc.fromDoc).toList()..sort((a, b) => b.tarih.compareTo(a.tarih)));

  static Future<void> kaydet(
    String sid,
    AppUser me, {
    String? id,
    required String tur,
    required String ad,
    required DateTime tarih,
    required bool resmi,
    required String kaynak,
    required Map<String, TestSonucu> testler,
    required Map<String, double> puanlar,
    Map<String, int>? konuHata,
  }) {
    final veri = <String, dynamic>{
      'tur': tur,
      'ad': ad,
      'tarih': Timestamp.fromDate(tarih),
      'resmi': resmi,
      'kaynak': kaynak,
      'testler': {for (final e in testler.entries) e.key: e.value.toMap()},
      'puanlar': puanlar,
      if (konuHata != null) 'konuHata': konuHata,
    };
    if (id == null) {
      return _col(sid).add({...veri, 'createdBy': me.uid, 'createdAt': Timestamp.now()});
    }
    return _col(sid).doc(id).update({...veri, 'updatedAt': Timestamp.now()});
  }

  static Future<void> konuHataKaydet(String sid, String id, Map<String, int> konuHata) =>
      _col(sid).doc(id).update({'konuHata': konuHata, 'updatedAt': Timestamp.now()});

  static Future<void> sil(String sid, String id) => _col(sid).doc(id).delete();
}
