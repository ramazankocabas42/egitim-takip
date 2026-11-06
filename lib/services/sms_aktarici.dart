import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../lgs.dart';
import '../models.dart';
import 'db.dart';
import 'kitap_katalog.dart';
import 'notifications.dart';
import 'takip_db.dart';

/// Telefonun SMS kutusundaki kurum (ör. ERCIYESEGTM) deneme sonuçlarını
/// bulup ilgili öğrencinin LGS denemelerine otomatik ekler.
///
/// - Sadece okuma izni kullanır, SMS göndermez/silmez.
/// - Öğrenci, mesajdaki ad soyaddan bulunur ("... ÖĞRENCİMİZ AYŞE KOCABAŞ ...").
/// - İşlenen mesajlar öğrenci bazında kaydedilir; aynı mesaj iki kez eklenmez,
///   silinen deneme tekrar eklenmez.
class SmsAktarici {
  SmsAktarici._();

  static const _kanal = MethodChannel('egitim_takip/sms');

  /// Gönderen adında aranan ifade (büyük/küçük harf duyarsız).
  static const gonderen = 'ERCIYES';

  static bool _calisiyor = false;
  static DateTime? _sonTarama;

  static bool get destekleniyor => !kIsWeb && Platform.isAndroid;

  static Future<bool> izinVar() async {
    if (!destekleniyor) return false;
    try {
      return await _kanal.invokeMethod<bool>('izinVar') ?? false;
    } catch (e) {
      debugPrint('SMS izni kontrol edilemedi: $e');
      return false;
    }
  }

  static Future<bool> izinIste() async {
    if (!destekleniyor) return false;
    try {
      return await _kanal.invokeMethod<bool>('izinIste') ?? false;
    } catch (e) {
      debugPrint('SMS izni istenemedi: $e');
      return false;
    }
  }

  static String _ozet(String s) {
    var h = 0x811c9dc5;
    for (final c in utf8.encode(s.replaceAll(RegExp(r'\s+'), ' ').trim())) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }

  static Student? _ogrenciBul(List<Student> ogrenciler, String metin) {
    final kelimeler = KitapKatalog.kelimelereAyir(metin).toSet();
    Student? bulunan;
    var enUzun = 0;
    for (final o in ogrenciler) {
      final ad = KitapKatalog.kelimelereAyir(o.name);
      if (ad.isEmpty) continue;
      if (ad.every(kelimeler.contains) && ad.length > enUzun) {
        bulunan = o;
        enUzun = ad.length;
      }
    }
    return bulunan;
  }

  static String _baslik(String s) => s
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) {
        final k = w.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
        return (k[0] == 'i' ? 'İ' : k[0].toUpperCase()) + k.substring(1);
      })
      .join(' ');

  /// Mesajdaki deneme uygulamada zaten var mı?
  static bool _zatenVar(
      List<LgsDeneme> mevcut, String anahtar, KurumSonucu s, DateTime tarih) {
    final t = s.dersler.values.fold(Dyb.bos, (a, b) => a + b);
    for (final d in mevcut) {
      if (d.smsAnahtar == anahtar) return true;
      if (!DateUtils.isSameDay(d.tarih, tarih)) continue;
      if (s.puan != null && d.puan != null && (s.puan! - d.puan!).abs() < 0.01) {
        return true;
      }
      final dt = d.toplam;
      if (dt.d == t.d && dt.y == t.y) return true;
    }
    return false;
  }

  /// Mesajları tarar; eklenen denemelerin kısa açıklamalarını döndürür.
  /// [zorla] false ise son taramadan bu yana 1 dakika geçmeden tekrar taramaz.
  /// [esitle] true ise daha önce eklenip silinmiş denemeler de geri eklenir:
  /// mesajlarda olup uygulamada olmayan her sonuç eklenir.
  static Future<List<String>> tara(AppUser me,
      {bool zorla = false, bool esitle = false}) async {
    if (!destekleniyor || _calisiyor) return const [];
    final simdi = DateTime.now();
    if (!zorla &&
        _sonTarama != null &&
        simdi.difference(_sonTarama!) < const Duration(minutes: 1)) {
      return const [];
    }
    _calisiyor = true;
    _sonTarama = simdi;
    final eklenen = <String>[];
    try {
      if (!await izinVar()) return const [];
      final ogrenciler = await Db.myStudents(me).first;
      if (ogrenciler.isEmpty) return const [];

      final ham = await _kanal.invokeMethod<List<dynamic>>('oku', {
            'gonderen': gonderen,
            'ifade': 'DENEME SINAV',
            'sonra': simdi
                .subtract(const Duration(days: 180))
                .millisecondsSinceEpoch,
          }) ??
          const [];

      final islenenler = <String, Set<String>>{};
      final mevcutlar = <String, List<LgsDeneme>>{};
      // Eskiden yeniye işle ki bildirimler sırayla gelsin.
      for (final s in ham.reversed) {
        if (s is! Map) continue;
        final metin = (s['metin'] ?? '').toString();
        final sonuc = kurumMesajiCoz(metin);
        if (sonuc == null || sonuc.dersler.length < 3) continue;
        final ogr = _ogrenciBul(ogrenciler, metin);
        if (ogr == null) continue;

        final anahtar = _ozet(metin);
        final kume = islenenler[ogr.id] ??= await TakipDb.smsIslenenler(ogr.id);
        if (!esitle && kume.contains(anahtar)) continue;

        final smsTarihi = s['tarih'] is num
            ? DateTime.fromMillisecondsSinceEpoch((s['tarih'] as num).toInt())
            : simdi;
        final mevcut = mevcutlar[ogr.id] ??=
            List.of(await TakipDb.denemeler(ogr.id).first);
        if (_zatenVar(mevcut, anahtar, sonuc, sonuc.tarih ?? smsTarihi)) {
          if (!kume.contains(anahtar)) {
            await TakipDb.smsIslendi(ogr.id, me, anahtar);
            kume.add(anahtar);
          }
          continue;
        }
        await TakipDb.denemeKaydet(
          ogr.id,
          me,
          ad: sonuc.ad.isEmpty ? 'Deneme' : sonuc.ad,
          yayin: _baslik(sonuc.kurum),
          tarih: sonuc.tarih ?? smsTarihi,
          puan: sonuc.puan,
          dersler: sonuc.dersler,
          kaynak: 'sms',
          smsAnahtar: anahtar,
        );
        mevcut.add(LgsDeneme(
          id: '',
          ad: sonuc.ad,
          yayin: '',
          tarih: sonuc.tarih ?? smsTarihi,
          puan: sonuc.puan,
          dersler: sonuc.dersler,
          createdBy: me.uid,
          smsAnahtar: anahtar,
        ));
        await TakipDb.smsIslendi(ogr.id, me, anahtar);
        kume.add(anahtar);

        final puan = (sonuc.puan ?? lgsTahminiPuan(sonuc.dersler)).toStringAsFixed(2);
        final aciklama = '${ogr.name}: ${sonuc.ad} — $puan puan';
        eklenen.add(aciklama);
        Bildirim.goster(
          Bildirim.kimlik('sms/$anahtar'),
          'Yeni deneme sonucu eklendi',
          aciklama,
        );
      }
    } catch (e) {
      debugPrint('SMS taranamadı: $e');
    } finally {
      _calisiyor = false;
    }
    return eklenen;
  }
}
