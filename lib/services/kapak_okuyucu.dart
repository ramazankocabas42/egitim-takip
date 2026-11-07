import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'kitap_katalog.dart';

/// Kitap kapağı / arka kapak fotoğrafından çıkarılan bilgi.
class KapakSonucu {
  KapakSonucu({this.isbn, required this.sorgular, required this.satirlar});

  /// Fotoğraftaki barkoddan ya da "ISBN ..." yazısından bulunan ISBN.
  final String? isbn;

  /// Web'de / katalogda denenecek aramalar (en olasıdan başlayarak).
  final List<String> sorgular;

  /// Okunan yazılar (büyük yazıdan küçüğe).
  final List<String> satirlar;
}

/// Telefonda (çevrimdışı) çalışır: ML Kit ile yazı tanıma ve barkod okuma.
class KapakOkuyucu {
  KapakOkuyucu._();

  static final _isbnRe = RegExp(r'97[89][\d\s-]{10,16}');

  /// Metin içinden geçerli bir ISBN arar.
  static String? metindenIsbn(String metin) {
    for (final m in _isbnRe.allMatches(metin)) {
      final i = KitapKatalog.isbnTemizle(m.group(0)!);
      if (i != null) return i;
    }
    return null;
  }

  static Future<KapakSonucu> oku(String yol) async {
    String? isbn;

    // 1) Fotoğrafta barkod / karekod var mı?
    MobileScannerController? tarayici;
    try {
      tarayici = MobileScannerController(autoStart: false);
      final yakalanan = await tarayici.analyzeImage(yol);
      for (final b in yakalanan?.barcodes ?? const <Barcode>[]) {
        final ham = b.rawValue ?? '';
        isbn ??= KitapKatalog.isbnTemizle(ham) ?? metindenIsbn(ham);
      }
    } catch (_) {
      // barkod yoksa ya da okunamazsa yazıya geç
    } finally {
      try {
        await tarayici?.dispose();
      } catch (_) {}
    }

    // 2) Kapaktaki yazılar: büyük yazı = kitap adı.
    final satirlar = <(String, double)>[];
    final tanima = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final r = await tanima.processImage(InputImage.fromFilePath(yol));
      isbn ??= metindenIsbn(r.text);
      for (final blok in r.blocks) {
        for (final s in blok.lines) {
          final t = s.text.trim();
          final harf = RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]').allMatches(t).length;
          if (t.length < 2 || harf < 2) continue;
          if (RegExp(r'^(www\.|http|isbn|tel|fiyat)', caseSensitive: false).hasMatch(t)) {
            continue;
          }
          satirlar.add((t, s.boundingBox.height));
        }
      }
    } catch (_) {
      // yazı tanınamadı
    } finally {
      await tanima.close();
    }
    satirlar.sort((a, b) => b.$2.compareTo(a.$2));
    final metinler = satirlar.map((e) => e.$1).toList();

    String kisalt(Iterable<String> l) {
      final kelimeler = l.join(' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      return kelimeler.take(8).join(' ');
    }

    final sorgular = <String>{};
    if (metinler.isNotEmpty) {
      sorgular.add(kisalt(metinler.take(3)));
      sorgular.add(kisalt(metinler.take(2)));
      sorgular.add(kisalt(metinler.take(1)));
      // Sınıf numarası küçük yazıyla yazılmışsa onu da ekle
      final sinif = RegExp(r'\b(1[0-2]|[1-9])\s*\.?\s*(sınıf|SINIF|Sınıf)')
          .firstMatch(metinler.join(' '));
      if (sinif != null) sorgular.add('${sinif.group(1)}. sınıf ${kisalt(metinler.take(1))}');
    }
    sorgular.removeWhere((q) => q.trim().length < 3);
    return KapakSonucu(isbn: isbn, sorgular: sorgular.toList(), satirlar: metinler);
  }
}
