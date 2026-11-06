import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';

/// Uygulama içi güncelleme: GitHub'daki son sürümü kontrol eder, daha yeniyse
/// kullanıcıya sorar, APK'yı indirip kurulum ekranını açar.
class Guncelleme {
  Guncelleme._();

  /// Derleme sırasında `--dart-define=BUILD_NUMBER=...` ile verilir.
  /// Yerel derlemelerde 0'dır ve güncelleme kontrolü yapılmaz.
  static const int buSurum = int.fromEnvironment('BUILD_NUMBER');

  static const _depo = 'ramazankocabas42/egitim-takip';
  static const _apkAdi = 'egitim-takip.apk';

  static bool _kontrolEdildi = false;

  /// Uygulama açılışında bir kez çağrılır.
  static Future<void> kontrolEt(BuildContext context) async {
    if (_kontrolEdildi || buSurum == 0) return;
    _kontrolEdildi = true;
    try {
      final r = await http.get(
        Uri.https('api.github.com', '/repos/$_depo/releases/latest'),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map) return;
      final etiket = (j['tag_name'] ?? '').toString(); // ör. surum-12
      final yeni = int.tryParse(etiket.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (yeni <= buSurum) return;

      String? url;
      final dosyalar = j['assets'];
      if (dosyalar is List) {
        for (final a in dosyalar) {
          if (a is Map && a['name'] == _apkAdi) {
            url = a['browser_download_url']?.toString();
          }
        }
      }
      if (url == null || !context.mounted) return;

      final notlar = _notlar((j['body'] ?? '').toString());
      final evet = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.system_update),
          title: const Text('Yeni sürüm var'),
          content: Text(
            'Sürüm $yeni yayınlandı (sizdeki: $buSurum).'
            '${notlar.isEmpty ? '' : '\n\n$notlar'}'
            '\n\nŞimdi güncellemek ister misiniz?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Sonra')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Güncelle')),
          ],
        ),
      );
      if (evet == true && context.mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _IndirmeDialog(url: url!),
        );
      }
    } catch (e) {
      debugPrint('Güncelleme kontrolü yapılamadı: $e');
    }
  }

  /// Sürüm notlarındaki kurulum talimatını atıp kısa açıklamayı bırakır.
  static String _notlar(String govde) => govde
      .split('\n')
      .map((s) => s.trim())
      .where((s) =>
          s.isNotEmpty &&
          !s.contains('.apk') &&
          !s.contains('http') &&
          !s.startsWith('Co-Authored-By') &&
          !s.startsWith('Claude-Session'))
      .take(6)
      .join('\n');
}

class _IndirmeDialog extends StatefulWidget {
  const _IndirmeDialog({required this.url});

  final String url;

  @override
  State<_IndirmeDialog> createState() => _IndirmeDialogState();
}

class _IndirmeDialogState extends State<_IndirmeDialog> {
  StreamSubscription<OtaEvent>? _abonelik;
  double? _yuzde;
  String _durum = 'İndiriliyor...';
  bool _hata = false;

  @override
  void initState() {
    super.initState();
    _baslat();
  }

  void _baslat() {
    setState(() {
      _hata = false;
      _yuzde = null;
      _durum = 'İndiriliyor...';
    });
    try {
      _abonelik = OtaUpdate()
          .execute(widget.url, destinationFilename: 'egitim-takip.apk')
          .listen(_olay, onError: (Object e) => _hataGoster('$e'));
    } catch (e) {
      _hataGoster('$e');
    }
  }

  void _olay(OtaEvent e) {
    if (!mounted) return;
    switch (e.status) {
      case OtaStatus.DOWNLOADING:
        setState(() => _yuzde = (double.tryParse(e.value ?? '') ?? 0) / 100);
      case OtaStatus.INSTALLING:
      case OtaStatus.INSTALLATION_DONE:
        // Android'in kurulum ekranı açıldı; bu pencere kapanabilir.
        Navigator.of(context).pop();
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        _hataGoster(
            'Uygulama yükleme izni verilmedi. Ayarlardan "Eğitim Takip" için '
            '"Bilinmeyen uygulamaları yükle" iznini açıp tekrar deneyin.');
      case OtaStatus.DOWNLOAD_ERROR:
        _hataGoster('İndirme başarısız. İnternet bağlantınızı kontrol edin.');
      default:
        if (e.status.name.contains('ERROR')) {
          _hataGoster('Güncelleme yapılamadı (${e.value ?? e.status.name}).');
        }
    }
  }

  void _hataGoster(String mesaj) {
    if (!mounted) return;
    setState(() {
      _hata = true;
      _durum = mesaj;
    });
  }

  @override
  void dispose() {
    _abonelik?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Güncelleniyor'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_hata
              ? _durum
              : _yuzde == null
                  ? _durum
                  : 'İndiriliyor... %${(_yuzde! * 100).round()}'),
          if (!_hata) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _yuzde),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (!_hata) {
              try {
                OtaUpdate().cancel();
              } catch (_) {}
            }
            Navigator.of(context).pop();
          },
          child: Text(_hata ? 'Kapat' : 'Vazgeç'),
        ),
        if (_hata)
          FilledButton(onPressed: _baslat, child: const Text('Tekrar dene')),
      ],
    );
  }
}
