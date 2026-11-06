import 'package:cloud_firestore/cloud_firestore.dart';

import '../models.dart';

String _str(dynamic v) => v == null ? '' : v.toString();
int _int(dynamic v) => v is num ? v.toInt() : 0;
double? _dbl(dynamic v) => v is num ? v.toDouble() : null;

/// Okul sınavı ya da notu (yazılı, performans, proje).
/// Tarihi olup notu olmayan kayıt "yaklaşan sınav"dır; not girilince sonuç olur.
class OkulSinav {
  OkulSinav({
    required this.id,
    required this.ders,
    required this.tur,
    required this.sira,
    required this.donem,
    required this.tarih,
    required this.not,
    required this.createdBy,
  });

  final String id;
  final String ders;
  final String tur; // 'yazili' | 'performans' | 'proje'
  final int sira; // 1. yazılı, 2. yazılı...
  final int donem; // 1 | 2
  final DateTime? tarih;
  final double? not;
  final String createdBy;

  String get turAdi => switch (tur) {
        'performans' => 'Performans',
        'proje' => 'Proje',
        _ => 'Yazılı',
      };

  String get baslik => '${sira > 0 ? '$sira. ' : ''}$turAdi';

  factory OkulSinav.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    final t = m['tarih'];
    return OkulSinav(
      id: d.id,
      ders: _str(m['ders']),
      tur: _str(m['tur']).isEmpty ? 'yazili' : _str(m['tur']),
      sira: _int(m['sira']),
      donem: _int(m['donem']) == 2 ? 2 : 1,
      tarih: t is Timestamp ? t.toDate() : null,
      not: _dbl(m['not']),
      createdBy: _str(m['createdBy']),
    );
  }
}

class YilSonu {
  YilSonu({required this.yil, required this.sinif, required this.not});

  final String yil; // 2022-2023
  final String sinif; // 4. Sınıf
  final double not;

  factory YilSonu.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return YilSonu(
      yil: _str(m['yil']).isEmpty ? d.id : _str(m['yil']),
      sinif: _str(m['sinif']),
      not: _dbl(m['not']) ?? 0,
    );
  }
}

/// Bulunulan eğitim öğretim yılında tarihin dönemi (Eylül–Ocak: 1, Şubat–Ağustos: 2).
int donemOf(DateTime d) => (d.month >= 9 || d.month == 1) ? 1 : 2;

/// Haftalık ders saatine göre yaklaşık ağırlık (8. sınıf).
double dersAgirligi(String ders) {
  final k = ders.toLowerCase();
  if (k.contains('türkçe') || k.contains('matematik')) return 5;
  if (k.contains('fen') || k.contains('ingiliz') || k.contains('yabancı')) return 4;
  if (k.contains('müzik') || k.contains('görsel')) return 1;
  return 2;
}

class OkulDb {
  OkulDb._();

  static CollectionReference<Map<String, dynamic>> _sub(String sid, String ad) =>
      FirebaseFirestore.instance.collection('students').doc(sid).collection(ad);

  static Stream<List<OkulSinav>> sinavlar(String sid) =>
      _sub(sid, 'okulSinavlari').snapshots().map((s) {
        final l = s.docs.map(OkulSinav.fromDoc).toList();
        l.sort((a, b) {
          final ta = a.tarih, tb = b.tarih;
          if (ta == null && tb == null) return a.sira.compareTo(b.sira);
          if (ta == null) return 1;
          if (tb == null) return -1;
          return ta.compareTo(tb);
        });
        return l;
      });

  static Future<void> sinavKaydet(
    String sid,
    AppUser me, {
    String? id,
    required String ders,
    required String tur,
    required int sira,
    required int donem,
    required DateTime? tarih,
    required double? not,
  }) {
    final veri = <String, dynamic>{
      'ders': ders,
      'tur': tur,
      'sira': sira,
      'donem': donem,
      'tarih': tarih == null
          ? null
          : Timestamp.fromDate(DateTime(tarih.year, tarih.month, tarih.day, 9)),
      'not': not,
    };
    if (id == null) {
      return _sub(sid, 'okulSinavlari').add({
        ...veri,
        'createdBy': me.uid,
        'createdAt': Timestamp.now(),
      });
    }
    return _sub(sid, 'okulSinavlari')
        .doc(id)
        .update({...veri, 'updatedAt': Timestamp.now()});
  }

  static Future<void> sil(String sid, String koleksiyon, String id) =>
      _sub(sid, koleksiyon).doc(id).delete();

  static Stream<List<YilSonu>> yilSonlari(String sid) =>
      _sub(sid, 'yilSonuNotlari').snapshots().map((s) {
        final l = s.docs.map(YilSonu.fromDoc).toList()
          ..sort((a, b) => a.yil.compareTo(b.yil));
        return l;
      });

  /// Belge kimliği yıl olduğu için aynı yıl tekrar eklenirse güncellenir.
  static Future<void> yilSonuKaydet(
      String sid, AppUser me, String yil, String sinif, double not) async {
    final ref = _sub(sid, 'yilSonuNotlari').doc(yil.replaceAll('/', '-'));
    final d = await ref.get();
    if (d.exists) {
      await ref.update({'yil': yil, 'sinif': sinif, 'not': not});
    } else {
      await ref.set({
        'yil': yil,
        'sinif': sinif,
        'not': not,
        'createdBy': me.uid,
        'createdAt': Timestamp.now(),
      });
    }
  }
}
