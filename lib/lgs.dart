import 'package:flutter/material.dart';

/// LGS dersleri, konuları ve puan hesabı.
class LgsDers {
  const LgsDers({
    required this.ad,
    required this.kisa,
    required this.soru,
    required this.katsayi,
    required this.ikon,
    required this.renk,
  });

  final String ad; // uygulamadaki ders adı (subjects listesindeki ile aynı)
  final String kisa;
  final int soru; // LGS'deki soru sayısı
  final int katsayi; // ağırlık
  final IconData ikon;
  final Color renk;
}

const lgsDersler = <LgsDers>[
  LgsDers(
      ad: 'Türkçe',
      kisa: 'Türkçe',
      soru: 20,
      katsayi: 4,
      ikon: Icons.menu_book_outlined,
      renk: Color(0xFFE53935)),
  LgsDers(
      ad: 'Matematik',
      kisa: 'Mat',
      soru: 20,
      katsayi: 4,
      ikon: Icons.calculate_outlined,
      renk: Color(0xFF1E88E5)),
  LgsDers(
      ad: 'Fen Bilimleri',
      kisa: 'Fen',
      soru: 20,
      katsayi: 4,
      ikon: Icons.science_outlined,
      renk: Color(0xFF43A047)),
  LgsDers(
      ad: 'T.C. İnkılap Tarihi',
      kisa: 'İnkılap',
      soru: 10,
      katsayi: 1,
      ikon: Icons.flag_outlined,
      renk: Color(0xFFFB8C00)),
  LgsDers(
      ad: 'Din Kültürü',
      kisa: 'Din',
      soru: 10,
      katsayi: 1,
      ikon: Icons.mosque_outlined,
      renk: Color(0xFF8E24AA)),
  LgsDers(
      ad: 'İngilizce',
      kisa: 'İng',
      soru: 10,
      katsayi: 1,
      ikon: Icons.translate,
      renk: Color(0xFF00897B)),
];

LgsDers? lgsDers(String ad) {
  for (final d in lgsDersler) {
    if (d.ad == ad) return d;
  }
  return null;
}

/// 8. sınıf LGS konuları (ünite / kazanım grupları).
const lgsKonular = <String, List<String>>{
  'Türkçe': [
    'Sözcükte Anlam',
    'Cümlede Anlam',
    'Paragrafta Anlam',
    'Sözel Mantık ve Görsel Okuma',
    'Fiilimsiler',
    'Cümlenin Ögeleri',
    'Fiillerde Çatı',
    'Cümle Türleri',
    'Yazım Kuralları',
    'Noktalama İşaretleri',
    'Anlatım Bozuklukları',
    'Metin Türleri',
    'Söz Sanatları',
    'Deyimler ve Atasözleri',
  ],
  'Matematik': [
    'Çarpanlar ve Katlar',
    'Üslü İfadeler',
    'Kareköklü İfadeler',
    'Veri Analizi',
    'Basit Olayların Olma Olasılığı',
    'Cebirsel İfadeler ve Özdeşlikler',
    'Doğrusal Denklemler',
    'Eşitsizlikler',
    'Üçgenler',
    'Eşlik ve Benzerlik',
    'Dönüşüm Geometrisi',
    'Geometrik Cisimler',
  ],
  'Fen Bilimleri': [
    'Mevsimler ve İklim',
    'DNA ve Genetik Kod',
    'Basınç',
    'Madde ve Endüstri',
    'Basit Makineler',
    'Enerji Dönüşümleri ve Çevre Bilimi',
    'Elektrik Yükleri ve Elektrik Enerjisi',
  ],
  'T.C. İnkılap Tarihi': [
    'Bir Kahraman Doğuyor',
    'Millî Uyanış',
    'Ya İstiklal Ya Ölüm!',
    'Çağdaşlaşan Türkiye',
    'Demokratikleşme Çabaları',
    'Atatürk Dönemi Dış Politika',
    'Atatürk\'ün Ölümü ve Sonrası',
  ],
  'Din Kültürü': [
    'Kader İnancı',
    'Zekât ve Sadaka',
    'Din ve Hayat',
    'Hz. Muhammed\'in Örnekliği',
    'Kur\'an-ı Kerim ve Özellikleri',
  ],
  'İngilizce': [
    'Friendship',
    'Teen Life',
    'In the Kitchen',
    'On the Phone',
    'The Internet',
    'Adventures',
    'Tourism',
    'Chores',
    'Science',
    'Natural Forces',
  ],
};

/// Doğru / yanlış / boş üçlüsü.
class Dyb {
  const Dyb(this.d, this.y, this.b);

  static const bos = Dyb(0, 0, 0);

  final int d;
  final int y;
  final int b;

  int get toplam => d + y + b;

  /// LGS'de 3 yanlış 1 doğruyu götürür.
  double get net => d - y / 3;

  /// Çözülen sorulardaki başarı oranı (0-1).
  double get basari => toplam == 0 ? 0 : d / toplam;

  Dyb operator +(Dyb o) => Dyb(d + o.d, y + o.y, b + o.b);

  Map<String, int> toMap() => {'d': d, 'y': y, 'b': b};

  factory Dyb.fromMap(dynamic m) {
    if (m is! Map) return bos;
    int n(dynamic v) => v is num ? v.toInt() : 0;
    return Dyb(n(m['d']), n(m['y']), n(m['b']));
  }
}

/// Ders adı -> D/Y/B haritası (Firestore'a map olarak yazılır).
Map<String, Dyb> dersHaritasi(dynamic m) {
  final out = <String, Dyb>{};
  if (m is Map) {
    m.forEach((k, v) => out[k.toString()] = Dyb.fromMap(v));
  }
  return out;
}

Map<String, dynamic> dersHaritasiYaz(Map<String, Dyb> m) => {
      for (final e in m.entries)
        if (e.value.toplam > 0) e.key: e.value.toMap(),
    };

/// Ağırlıklı LGS neti (en fazla 270).
double lgsAgirlikliNet(Map<String, Dyb> dersler) {
  var t = 0.0;
  for (final d in lgsDersler) {
    final r = dersler[d.ad];
    if (r == null) continue;
    t += (r.net < 0 ? 0 : r.net) * d.katsayi;
  }
  return t;
}

const lgsAzamiAgirlikliNet = 270.0;

/// Yaklaşık LGS puanı. Gerçek puan MEB'in standart puan hesabıyla bulunur;
/// bu değer yalnızca gelişimi izlemek için doğrusal bir tahmindir.
double lgsTahminiPuan(Map<String, Dyb> dersler) =>
    194.75 + lgsAgirlikliNet(dersler) * (500 - 194.75) / lgsAzamiAgirlikliNet;

/// Haftanın Pazartesi günü.
DateTime haftaBasi(DateTime d) {
  final g = DateTime(d.year, d.month, d.day);
  return g.subtract(Duration(days: g.weekday - 1));
}

String haftaAnahtari(DateTime d) {
  final p = haftaBasi(d);
  String iki(int n) => n.toString().padLeft(2, '0');
  return '${p.year}-${iki(p.month)}-${iki(p.day)}';
}

const gunKisa = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
const gunUzun = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar'
];

String sureYaz(int dakika) {
  if (dakika <= 0) return '0 dk';
  final s = dakika ~/ 60;
  final d = dakika % 60;
  if (s == 0) return '$d dk';
  if (d == 0) return '$s sa';
  return '$s sa $d dk';
}
