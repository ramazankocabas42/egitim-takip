import 'package:flutter/material.dart';

/// ÖSYM sınavları (YKS, KPSS, AGS) tanımları: testler, soru sayıları,
/// konular ve puan türleri. Soru sayıları ÖSYM'nin yıllara göre
/// değişebileceği için girişte düzeltilebilir.

class OsymTest {
  const OsymTest(this.id, this.ad, this.soru, this.konular,
      {this.renk = Colors.indigo, this.takmaAdlar = const []});
  final String id;
  final String ad;
  final int soru;
  final List<String> konular;
  final Color renk;

  /// ÖSYM sayfalarında geçebilecek diğer adlar (ayrıştırma için).
  final List<String> takmaAdlar;
}

class OsymSinavTuru {
  const OsymSinavTuru({
    required this.id,
    required this.ad,
    required this.grup,
    required this.testler,
    required this.puanlar,
    this.yanlisBolen = 4,
    this.aciklama = '',
  });
  final String id;
  final String ad;
  final String grup; // YKS | KPSS | AGS
  final List<OsymTest> testler;
  final List<String> puanlar; // puan türleri
  final int yanlisBolen; // kaç yanlış bir doğruyu götürür
  final String aciklama;

  int get toplamSoru => testler.fold(0, (s, t) => s + t.soru);
  OsymTest? test(String id) {
    for (final t in testler) {
      if (t.id == id) return t;
    }
    return null;
  }
}

const _turkce = [
  'Sözcükte Anlam', 'Cümlede Anlam', 'Paragraf', 'Ses Bilgisi', 'Yazım Kuralları',
  'Noktalama İşaretleri', 'Sözcük Türleri', 'Sözcükte Yapı', 'Cümlenin Ögeleri',
  'Cümle Türleri', 'Fiilimsiler', 'Anlatım Bozukluğu',
];
const _temelMat = [
  'Temel Kavramlar', 'Sayı Basamakları', 'Bölme ve Bölünebilme', 'EBOB-EKOK',
  'Rasyonel Sayılar', 'Basit Eşitsizlikler', 'Mutlak Değer', 'Üslü Sayılar', 'Köklü Sayılar',
  'Çarpanlara Ayırma', 'Oran-Orantı', 'Denklem Çözme', 'Sayı-Kesir Problemleri',
  'Yaş Problemleri', 'Yüzde-Kâr-Zarar', 'Hareket Problemleri', 'İşçi-Havuz Problemleri',
  'Karışım Problemleri', 'Grafik Problemleri', 'Kümeler', 'Mantık', 'Fonksiyonlar',
  'Polinomlar', 'Permütasyon-Kombinasyon', 'Olasılık', 'Veri-İstatistik',
  'Geometri: Açılar ve Üçgenler', 'Geometri: Dörtgenler ve Çokgenler',
  'Geometri: Çember ve Daire', 'Geometri: Katı Cisimler', 'Geometri: Analitik',
];
const _tytSosyal = [
  'Tarih: Tarih Bilimi', 'Tarih: İlk Türk Devletleri', 'Tarih: İslam ve Türk-İslam Devletleri',
  'Tarih: Osmanlı Kuruluş-Yükselme', 'Tarih: Osmanlı Duraklama-Dağılma',
  'Tarih: Kurtuluş Savaşı', 'Tarih: Atatürk İlke ve İnkılapları',
  'Coğrafya: Doğa ve İnsan', 'Coğrafya: Harita Bilgisi', 'Coğrafya: İklim',
  'Coğrafya: Yer Şekilleri', 'Coğrafya: Nüfus ve Yerleşme', 'Coğrafya: Ekonomik Faaliyetler',
  'Coğrafya: Bölgeler ve Afetler', 'Felsefe: Felsefeye Giriş', 'Felsefe: Bilgi ve Varlık',
  'Felsefe: Ahlak ve Sanat', 'Felsefe: Din, Siyaset, Bilim', 'Din: İnanç ve İbadet',
  'Din: Ahlak ve Değerler', 'Din: Hz. Muhammed ve İslam Düşüncesi',
];
const _tytFen = [
  'Fizik: Fizik Bilimine Giriş', 'Fizik: Madde ve Özellikleri', 'Fizik: Hareket ve Kuvvet',
  'Fizik: İş-Güç-Enerji', 'Fizik: Isı ve Sıcaklık', 'Fizik: Elektrostatik ve Elektrik',
  'Fizik: Manyetizma', 'Fizik: Basınç ve Kaldırma', 'Fizik: Dalgalar', 'Fizik: Optik',
  'Kimya: Kimya Bilimi', 'Kimya: Atom ve Periyodik Sistem', 'Kimya: Kimyasal Türler Arası Etkileşimler',
  'Kimya: Maddenin Halleri', 'Kimya: Karışımlar', 'Kimya: Asit-Baz-Tuz',
  'Kimya: Kimyasal Tepkimeler', 'Kimya: Kimya Her Yerde',
  'Biyoloji: Canlıların Ortak Özellikleri', 'Biyoloji: Hücre', 'Biyoloji: Sınıflandırma',
  'Biyoloji: Hücre Bölünmeleri', 'Biyoloji: Kalıtım', 'Biyoloji: Ekosistem',
];
const _aytTarih = [
  'Tarih: Tarih ve Zaman', 'Tarih: İlk ve Orta Çağ Türk Dünyası', 'Tarih: İslam Medeniyeti',
  'Tarih: Türklerin İslamiyeti Kabulü', 'Tarih: Osmanlı Siyaseti (1302-1600)',
  'Tarih: Değişen Dünya Dengeleri (1600-1774)', 'Tarih: Uluslararası İlişkiler (1774-1914)',
  'Tarih: XX. Yüzyıl Başlarında Osmanlı', 'Tarih: Milli Mücadele', 'Tarih: Atatürkçülük ve İnkılaplar',
  'Tarih: II. Dünya Savaşı ve Soğuk Savaş', 'Tarih: Küreselleşen Dünya',
];
const _aytCografya = [
  'Coğrafya: Ekosistemler', 'Coğrafya: Nüfus Politikaları', 'Coğrafya: Ekonomik Faaliyetler',
  'Coğrafya: Türkiye Ekonomisi', 'Coğrafya: Bölgeler ve Ülkeler', 'Coğrafya: Küresel Ortam',
  'Coğrafya: Çevre ve Toplum',
];
const _aytEdebiyat = [
  'Edebiyat: Anlam Bilgisi', 'Edebiyat: Dil Bilgisi', 'Edebiyat: Şiir Bilgisi', 'Edebiyat: Edebi Sanatlar',
  'Edebiyat: İslamiyet Öncesi Türk Edebiyatı', 'Edebiyat: Halk Edebiyatı', 'Edebiyat: Divan Edebiyatı',
  'Edebiyat: Tanzimat Edebiyatı', 'Edebiyat: Servet-i Fünun ve Fecr-i Ati', 'Edebiyat: Milli Edebiyat',
  'Edebiyat: Cumhuriyet Dönemi', 'Edebiyat: Edebi Akımlar', 'Edebiyat: Roman, Hikâye, Tiyatro',
];
const _aytMat = [
  'Polinomlar', 'İkinci Dereceden Denklemler', 'Eşitsizlikler', 'Parabol', 'Fonksiyonlar',
  'Permütasyon-Kombinasyon-Olasılık', 'Karmaşık Sayılar', 'Logaritma', 'Diziler',
  'Trigonometri', 'Limit ve Süreklilik', 'Türev', 'İntegral',
  'Geometri: Üçgenler', 'Geometri: Çokgenler ve Dörtgenler', 'Geometri: Çember ve Daire',
  'Geometri: Analitik Geometri', 'Geometri: Dönüşümler', 'Geometri: Katı Cisimler',
];
const _aytFen = [
  'Fizik: Vektörler', 'Fizik: Kuvvet, Tork ve Denge', 'Fizik: Hareket ve Newton Yasaları',
  'Fizik: İş-Enerji, İtme-Momentum', 'Fizik: Çembersel ve Harmonik Hareket',
  'Fizik: Elektrik Alan ve Potansiyel', 'Fizik: Manyetizma ve İndüksiyon', 'Fizik: Dalga Mekaniği',
  'Fizik: Modern Fizik', 'Kimya: Modern Atom Teorisi', 'Kimya: Gazlar', 'Kimya: Sıvı Çözeltiler',
  'Kimya: Tepkimelerde Enerji ve Hız', 'Kimya: Kimyasal Denge', 'Kimya: Asit-Baz Dengesi',
  'Kimya: Elektrokimya', 'Kimya: Organik Kimya', 'Biyoloji: Sinir ve Endokrin Sistem',
  'Biyoloji: Duyu, Destek ve Hareket', 'Biyoloji: Sindirim, Dolaşım, Solunum, Boşaltım',
  'Biyoloji: Üreme ve Gelişme', 'Biyoloji: Genden Proteine', 'Biyoloji: Fotosentez ve Solunum',
  'Biyoloji: Bitki Biyolojisi', 'Biyoloji: Komünite ve Popülasyon',
];
const _felsefeGrubu = [
  'Felsefe: Felsefe Tarihi', 'Mantık: Klasik ve Sembolik Mantık', 'Psikoloji: Temel Süreçler',
  'Psikoloji: Öğrenme, Bellek, Düşünme', 'Sosyoloji: Birey ve Toplum', 'Sosyoloji: Toplumsal Kurumlar',
  'Din: İslam Düşüncesi ve Yorumlar',
];
const _kpssTarih = [
  'Tarih: İslamiyet Öncesi Türk Tarihi', 'Tarih: Türk-İslam Devletleri', 'Tarih: Osmanlı Siyasi Tarihi',
  'Tarih: Osmanlı Kültür ve Medeniyeti', 'Tarih: XX. Yüzyıl Osmanlı', 'Tarih: Kurtuluş Savaşı Hazırlık',
  'Tarih: Kurtuluş Savaşı', 'Tarih: Atatürk İlke ve İnkılapları', 'Tarih: Atatürk Dönemi Dış Politika',
  'Tarih: Çağdaş Türk ve Dünya Tarihi',
];
const _kpssCografya = [
  'Coğrafya: Coğrafi Konum', 'Coğrafya: Yer Şekilleri', 'Coğrafya: İklim ve Bitki Örtüsü',
  'Coğrafya: Nüfus ve Yerleşme', 'Coğrafya: Tarım ve Hayvancılık', 'Coğrafya: Madenler ve Enerji',
  'Coğrafya: Sanayi', 'Coğrafya: Ulaşım, Ticaret, Turizm', 'Coğrafya: Bölgesel Coğrafya',
];
const _vatandaslik = [
  'Vatandaşlık: Hukuka Giriş', 'Vatandaşlık: Anayasa Hukuku', 'Vatandaşlık: 1982 Anayasası',
  'Vatandaşlık: Yasama', 'Vatandaşlık: Yürütme', 'Vatandaşlık: Yargı', 'Vatandaşlık: İdare Hukuku',
  'Vatandaşlık: Temel Hak ve Özgürlükler',
];

final osymSinavlari = <OsymSinavTuru>[
  OsymSinavTuru(
    id: 'TYT',
    ad: 'YKS - TYT',
    grup: 'YKS',
    aciklama: 'Temel Yeterlilik Testi',
    puanlar: ['TYT'],
    testler: [
      OsymTest('turkce', 'Türkçe', 40, _turkce, renk: Color(0xFFE53935)),
      OsymTest('sosyal', 'Sosyal Bilimler', 20, _tytSosyal, renk: Color(0xFF8E24AA)),
      OsymTest('temelmat', 'Temel Matematik', 40, _temelMat,
          renk: Color(0xFF1E88E5), takmaAdlar: ['Matematik']),
      OsymTest('fen', 'Fen Bilimleri', 20, _tytFen, renk: Color(0xFF43A047)),
    ],
  ),
  OsymSinavTuru(
    id: 'AYT',
    ad: 'YKS - AYT',
    grup: 'YKS',
    aciklama: 'Alan Yeterlilik Testleri',
    puanlar: ['SAY', 'EA', 'SÖZ'],
    testler: [
      OsymTest('edsos1', 'Türk Dili ve Edebiyatı-Sosyal Bilimler-1', 40,
          [..._aytEdebiyat, 'Tarih-1: Genel', 'Coğrafya-1: Genel'],
          renk: Color(0xFFE53935), takmaAdlar: ['Edebiyat-Sosyal Bilimler-1', 'Sosyal Bilimler-1']),
      OsymTest('sos2', 'Sosyal Bilimler-2', 40, [..._aytTarih, ..._aytCografya, ..._felsefeGrubu],
          renk: Color(0xFF8E24AA)),
      OsymTest('mat', 'Matematik', 40, _aytMat, renk: Color(0xFF1E88E5)),
      OsymTest('fen', 'Fen Bilimleri', 40, _aytFen, renk: Color(0xFF43A047)),
    ],
  ),
  OsymSinavTuru(
    id: 'YDT',
    ad: 'YKS - YDT',
    grup: 'YKS',
    aciklama: 'Yabancı Dil Testi',
    puanlar: ['DİL'],
    testler: [
      OsymTest('dil', 'Yabancı Dil', 80, [
        'Kelime Bilgisi', 'Dil Bilgisi', 'Cloze Test', 'Cümle Tamamlama', 'Çeviri (İng-Tr)',
        'Çeviri (Tr-İng)', 'Paragraf', 'Diyalog Tamamlama', 'Anlamca Yakın Cümle',
        'Paragrafta Anlam Bütünlüğü',
      ], renk: Color(0xFF00897B), takmaAdlar: ['İngilizce', 'Almanca', 'Arapça', 'Fransızca']),
    ],
  ),
  OsymSinavTuru(
    id: 'KPSS',
    ad: 'KPSS - GY/GK',
    grup: 'KPSS',
    aciklama: 'Genel Yetenek - Genel Kültür',
    puanlar: ['KPSSP3', 'KPSSP93', 'KPSSP94'],
    testler: [
      OsymTest('gy', 'Genel Yetenek', 60, [
        ..._turkce.map((k) => 'Türkçe: $k'), 'Türkçe: Sözel Mantık',
        ..._temelMat.take(19).map((k) => 'Matematik: $k'), 'Matematik: Sayısal Mantık',
        'Matematik: Geometri',
      ], renk: Color(0xFF1E88E5)),
      OsymTest('gk', 'Genel Kültür', 60,
          [..._kpssTarih, ..._kpssCografya, ..._vatandaslik, 'Güncel Bilgiler'],
          renk: Color(0xFFE53935)),
    ],
  ),
  OsymSinavTuru(
    id: 'AGS',
    ad: 'MEB - AGS',
    grup: 'AGS',
    aciklama: 'Akademi Giriş Sınavı (80 soru)',
    puanlar: ['AGS'],
    testler: [
      OsymTest('sozel', 'Sözel Yetenek', 15, [
        'Sözcükte Anlam', 'Cümlede Anlam', 'Anlatımın Oluşması', 'Paragrafta Anlam', 'Sözel Mantık',
      ], renk: Color(0xFFE53935)),
      OsymTest('sayisal', 'Sayısal Yetenek', 15, [
        'Temel İşlemler', 'Problemler', 'Sayısal Mantık', 'Veri Yorumlama', 'Geometri',
      ], renk: Color(0xFF1E88E5)),
      OsymTest('tarih', 'Tarih', 6, _kpssTarih, renk: Color(0xFF8E24AA)),
      OsymTest('cografya', 'Türkiye Coğrafyası', 6, _kpssCografya, renk: Color(0xFF6D4C41)),
      OsymTest('egitim', 'Eğitim Bilimleri ve Türk Milli Eğitim Sistemi', 30, [
        'Eğitimin Temelleri', 'Öğretim Teknolojileri', 'Öğretim Yöntem ve Teknikleri',
        'Sınıf Yönetimi', 'Program Okuryazarlığı', 'Ölçme ve Değerlendirme', 'Öğrenme Psikolojisi',
        'Gelişim Psikolojisi', 'Rehberlik', 'Türk Milli Eğitim Sisteminin Yapısı',
        'Türkiye Yüzyılı Maarif Modeli',
      ], renk: Color(0xFF43A047), takmaAdlar: ['Eğitim Bilimleri']),
      OsymTest('mevzuat', 'Mevzuat', 8, [
        'Anayasa\'da Eğitim', '1739 Sayılı Milli Eğitim Temel Kanunu', '222 Sayılı İlköğretim Kanunu',
        '7528 Sayılı Öğretmenlik Meslek Kanunu', 'Yönetmelikler',
      ], renk: Color(0xFFF9A825)),
    ],
  ),
  OsymSinavTuru(
    id: 'OABT',
    ad: 'MEB - ÖABT',
    grup: 'AGS',
    aciklama: 'Öğretmenlik Alan Bilgisi Testi (50 soru)',
    puanlar: ['ÖABT'],
    testler: [
      OsymTest('alan', 'Alan Bilgisi', 50, ['Alan Bilgisi', 'Alan Eğitimi'],
          renk: Color(0xFF3949AB), takmaAdlar: ['Öğretmenlik Alan Bilgisi', 'ÖABT']),
    ],
  ),
];

OsymSinavTuru? osymTuru(String id) {
  for (final t in osymSinavlari) {
    if (t.id == id) return t;
  }
  return null;
}

const osymGruplari = ['YKS', 'KPSS', 'AGS'];
