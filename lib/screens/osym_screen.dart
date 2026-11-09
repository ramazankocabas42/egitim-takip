import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/kitap_katalog.dart';
import '../services/osym_ayristirici.dart';
import 'eokul_screen.dart' show sayfaOkumaJs;

const _mavi = Color(0xFF0D47A1);
const _baslangic = 'https://ais.osym.gov.tr/';

const _linkJs = r'''
(function(){
  var out=[];
  var el=document.querySelectorAll('a,button,[onclick]');
  for(var i=0;i<el.length;i++){
    var t=(el[i].textContent||'').replace(/\s+/g,' ').trim();
    if(!t||t.length>80) continue;
    var h='';
    var ham=el[i].getAttribute&&el[i].getAttribute('href');
    if(ham&&ham.charAt(0)!=='#'&&ham.toLowerCase().indexOf('javascript')!==0&&el[i].href&&el[i].href.indexOf('http')===0){h=el[i].href;}
    out.push([t,h]);
  }
  return JSON.stringify(out);
})();
''';

String _tiklaJs(String metin) => '''
(function(t){
  var el=document.querySelectorAll('a,button,[onclick]');
  for(var i=0;i<el.length;i++){
    if((el[i].textContent||'').replace(/\\s+/g,' ').trim()===t){el[i].click();return 'ok';}
  }
  return 'yok';
})(${jsonEncode(metin)});
''';

/// Yeni pencerede açılan bağlantılar (target=_blank, window.open) WebView'da
/// hiçbir şey yapmaz; bunları aynı pencerede açtırır.
const pencereJs = r'''
(function(){
  if(window.__ettPencere) return 'ok';
  window.__ettPencere = 1;
  window.open = function(u){ if(u){ try{ location.href = new URL(u, location.href).href; }catch(e){ location.href = u; } } return window; };
  function duzelt(){
    var l = document.querySelectorAll('a[target],form[target]');
    for(var i=0;i<l.length;i++){ l[i].removeAttribute('target'); }
  }
  duzelt();
  try{ new MutationObserver(duzelt).observe(document.documentElement,{childList:true,subtree:true}); }catch(e){}
  return 'ok';
})();
''';

const _secici = 'a,button,input[type=button],input[type=submit],[onclick]';

/// Tablo satırlarındaki "Görüntüle" / "İncele" / "Detay" düğmeleri: [satır metni, sıra].
const _goruntuleJs = r'''
(function(){
  var el = document.querySelectorAll('a,button,input[type=button],input[type=submit],[onclick]');
  var out = [];
  for(var i=0;i<el.length;i++){
    var e = el[i];
    var t = ((e.textContent || e.value || '') + '').replace(/\s+/g,' ').trim();
    if(!/g[öo]r[üu]nt[üu]le|incele|detay/i.test(t)) continue;
    var tr = e.closest ? e.closest('tr') : null;
    var r = tr ? (tr.textContent || '').replace(/\s+/g,' ').trim() : t;
    out.push([r.slice(0,160), i]);
  }
  return JSON.stringify(out);
})();
''';

String _siraylaTiklaJs(int i) => '''
(function(){
  var el = document.querySelectorAll('$_secici');
  if(el[$i]){ el[$i].click(); return 'ok'; }
  return 'yok';
})();
''';

/// ÖSYM Aday İşlemleri Sistemi'ne uygulama içinden giriş. T.C. kimlik no ve
/// şifre yalnızca ÖSYM / e-Devlet sayfasına yazılır, uygulamada saklanmaz.
/// Gezilen sayfalardaki test bazında doğru / yanlış / boş sayıları ve puanlar
/// toplanır; "Eşitle" sonuç sayfalarını sırayla açıp okur.
class OsymEkrani extends StatefulWidget {
  const OsymEkrani({super.key});

  static String? sonSayfa;

  @override
  State<OsymEkrani> createState() => _OsymEkraniState();
}

class _OsymEkraniState extends State<OsymEkrani> {
  late final WebViewController _c;
  final _toplanan = <String, OsymTaslak>{};
  final _metinler = <String, String>{};
  int _ilerleme = 0;
  bool _esitleniyor = false;
  bool _otomatikDenendi = false;
  String? _durum;
  Timer? _gecikme;
  Completer<void>? _yuklendi;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(true)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _ilerleme = p);
        },
        onPageFinished: (url) {
          _c.runJavaScript(pencereJs).catchError((_) {});
          final y = _yuklendi;
          if (y != null && !y.isCompleted) y.complete();
          if (_esitleniyor) return;
          if (url.contains('osym.gov.tr')) OsymEkrani.sonSayfa = url;
          _gecikme?.cancel();
          _gecikme = Timer(const Duration(milliseconds: 1200), _sayfaAcildi);
        },
      ))
      ..loadRequest(Uri.parse(OsymEkrani.sonSayfa ?? _baslangic));
  }

  @override
  void dispose() {
    _gecikme?.cancel();
    super.dispose();
  }

  Future<Object?> _js(String js) async {
    Object r = await _c.runJavaScriptReturningResult(js);
    for (var i = 0; i < 2 && r is String; i++) {
      try {
        r = jsonDecode(r as String) as Object;
      } catch (_) {
        break;
      }
    }
    return r;
  }

  /// Giriş yapılmış bir ÖSYM sayfası açıldıysa aktarımı kendiliğinden başlat.
  Future<void> _sayfaAcildi() async {
    if (!mounted || _esitleniyor) return;
    await _oku('Açık sayfa');
    if (_otomatikDenendi || !mounted) return;
    try {
      final r = await _js(
          'JSON.stringify({p: !!document.querySelector("input[type=password]"), h: location.host})');
      if (r is! Map) return;
      final host = (r['h'] ?? '').toString();
      final sifreVar = r['p'] == true;
      if (!host.contains('osym.gov.tr') || sifreVar) return; // giriş sayfası / e-Devlet
      final sonucLinki = (await _linkler()).any((l) {
        final k = KitapKatalog.kelimelereAyir(l.$1).join(' ');
        return k.contains('sonuc') || k.contains('cevap kagidi');
      });
      final goruntule = (await _goruntuleler()).isNotEmpty;
      if (!sonucLinki && !goruntule && _toplanan.isEmpty) return;
      _otomatikDenendi = true;
      await _esitle();
    } catch (_) {}
  }

  Future<void> _oku(String ad) async {
    try {
      final r = await _js(sayfaOkumaJs);
      if (r is! List || !mounted) return;
      final satirlar = [
        for (final x in r)
          if (x is List) [for (final c in x) c.toString()],
      ];
      _metinler[ad] = satirlar.map((s) => s.join(' | ')).join('\n');
      final bulunan = OsymAyristirici.oku(satirlar);
      if (bulunan.isEmpty) return;
      setState(() {
        for (final t in bulunan) {
          final eski = _toplanan[t.anahtar];
          if (eski == null) {
            _toplanan[t.anahtar] = t;
          } else {
            eski.testler.addAll(t.testler);
            eski.puanlar.addAll(t.puanlar);
          }
        }
      });
    } catch (_) {}
  }

  Future<List<(String, String)>> _linkler() async {
    try {
      final r = await _js(_linkJs);
      if (r is! List) return const [];
      return [
        for (final x in r)
          if (x is List && x.length >= 2) (x[0].toString(), x[1].toString()),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<(String, int)>> _goruntuleler() async {
    try {
      final r = await _js(_goruntuleJs);
      if (r is! List) return const [];
      return [
        for (final x in r)
          if (x is List && x.length >= 2 && x[1] is num) (x[0].toString(), (x[1] as num).toInt()),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Liste sayfasına geri dön (önce geri tuşu, olmazsa adresi yeniden aç).
  Future<void> _listeyeDon(String? ana) async {
    if (ana == null || await _c.currentUrl() == ana) return;
    if (await _c.canGoBack()) {
      await _bekle(() => _c.goBack(), sure: const Duration(seconds: 8));
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    if (await _c.currentUrl() != ana) {
      await _bekle(() => _c.loadRequest(Uri.parse(ana)), sure: const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }

  Future<void> _bekle(Future<void> Function() eylem,
      {Duration sure = const Duration(seconds: 15)}) async {
    final y = Completer<void>();
    _yuklendi = y;
    await eylem();
    try {
      await y.future.timeout(sure);
    } catch (_) {}
    _yuklendi = null;
  }

  Future<void> _esitle() async {
    if (_esitleniyor) return;
    _gecikme?.cancel();
    setState(() {
      _esitleniyor = true;
      _durum = 'Sayfa inceleniyor...';
    });
    final ana = await _c.currentUrl();
    await _oku('Açık sayfa');
    // Sonuç / cevap kağıdı bağlantılarını sırayla aç
    final linkler = (await _linkler()).where((l) {
      final k = KitapKatalog.kelimelereAyir(l.$1).join(' ');
      return (k.contains('sonuc') || k.contains('cevap kagidi')) &&
          !k.contains('itiraz') &&
          !k.contains('basvuru');
    }).toList();
    final gorulen = <String>{};
    var n = 0;
    // Sonuç listesindeki "Görüntüle" düğmeleri: her satırı sırayla aç, oku, geri dön
    final satirlar = (await _goruntuleler()).where((g) {
      final k = KitapKatalog.kelimelereAyir(g.$1).join(' ');
      return !k.contains('itiraz') && !k.contains('basvuru');
    }).toList();
    for (var j = 0; j < satirlar.length && n < 10 && mounted; j++) {
      final g = satirlar[j];
      n++;
      final ad = g.$1.isEmpty ? 'Sonuç ${j + 1}' : g.$1;
      setState(() => _durum = '"$ad" okunuyor ($n/${satirlar.length})');
      try {
        await _listeyeDon(ana);
        await _c.runJavaScript(pencereJs);
        // Liste yeniden yüklendiyse düğmenin sırası değişmiş olabilir; satır metniyle bul
        final guncel = await _goruntuleler();
        var sira = g.$2;
        for (final x in guncel) {
          if (x.$1 == g.$1) {
            sira = x.$2;
            break;
          }
        }
        await _bekle(() => _c.runJavaScript(_siraylaTiklaJs(sira)), sure: const Duration(seconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 1800));
        await _oku(ad);
      } catch (_) {}
    }
    if (satirlar.isNotEmpty) await _listeyeDon(ana);
    for (final l in linkler) {
      if (n >= 10 || !mounted) break;
      if (!gorulen.add('${l.$1}|${l.$2}')) continue;
      n++;
      setState(() => _durum = '"${l.$1}" okunuyor ($n)');
      try {
        if (l.$2.isNotEmpty) {
          await _bekle(() => _c.loadRequest(Uri.parse(l.$2)));
        } else {
          if (ana != null && await _c.currentUrl() != ana) {
            await _bekle(() => _c.loadRequest(Uri.parse(ana)));
          }
          await _bekle(() => _c.runJavaScript(_tiklaJs(l.$1)), sure: const Duration(seconds: 10));
        }
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        await _oku(l.$1);
      } catch (_) {}
    }
    if (ana != null && n > 0 && mounted) {
      setState(() => _durum = 'Geri dönülüyor...');
      await _bekle(() => _c.loadRequest(Uri.parse(ana)), sure: const Duration(seconds: 10));
    }
    if (!mounted) return;
    setState(() {
      _esitleniyor = false;
      _durum = null;
    });
    if (_toplanan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(seconds: 9),
        content: Text('Sonuç bulunamadı. Giriş yaptıktan sonra ilgili sınavın "Cevap Kâğıdı '
            'Görüntüleme" ya da sonuç sayfasını açıp tekrar Eşitle\'ye basın. Olmazsa ⋮ menüsünden '
            '"Okunan sayfaları kopyala" ile metni gönderin.'),
      ));
      return;
    }
    Navigator.pop(context, _toplanan.values.toList());
  }

  Future<void> _kopyala() async {
    if (_metinler.isEmpty) await _oku('Açık sayfa');
    await Clipboard.setData(ClipboardData(
        text: _metinler.entries.map((e) => '=== ${e.key} ===\n${e.value}').join('\n\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sayfa metni kopyalandı. Paylaşmadan önce T.C. kimlik numarası gibi '
            'kişisel bilgileri silin.')));
  }

  Future<void> _cikis() async {
    await WebViewCookieManager().clearCookies();
    OsymEkrani.sonSayfa = null;
    await _c.loadRequest(Uri.parse(_baslangic));
  }

  @override
  Widget build(BuildContext context) {
    final sinavSayisi = _toplanan.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _esitleniyor) return;
        final nav = Navigator.of(context);
        if (await _c.canGoBack()) {
          await _c.goBack();
        } else {
          nav.pop(_toplanan.isEmpty ? null : _toplanan.values.toList());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _mavi,
          foregroundColor: Colors.white,
          title: const Text('ÖSYM AİS'),
          actions: [
            IconButton(
                onPressed: _esitleniyor ? null : () => _c.reload(),
                icon: const Icon(Icons.refresh)),
            PopupMenuButton<String>(
              enabled: !_esitleniyor,
              onSelected: (v) {
                if (v == 'ana') _c.loadRequest(Uri.parse(_baslangic));
                if (v == 'kopya') _kopyala();
                if (v == 'cikis') _cikis();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'ana', child: Text('AİS giriş sayfası')),
                PopupMenuItem(value: 'kopya', child: Text('Okunan sayfaları kopyala')),
                PopupMenuItem(value: 'cikis', child: Text('ÖSYM oturumunu kapat')),
              ],
            ),
          ],
          bottom: _ilerleme < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(
                      value: _ilerleme / 100, minHeight: 3, color: Colors.amber),
                )
              : null,
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _c),
            if (_esitleniyor)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(color: _mavi),
                            const SizedBox(height: 16),
                            Text(_durum ?? 'Eşitleniyor...',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Text('$sinavSayisi sınav bulundu',
                                style: const TextStyle(fontSize: 12.5)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Material(
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      sinavSayisi == 0
                          ? 'Giriş yapın; sonuçlar kendiliğinden aktarılır.'
                          : 'Bulunan: ${_toplanan.values.map((t) => t.ad).join(', ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _mavi),
                    onPressed: _esitleniyor ? null : _esitle,
                    icon: const Icon(Icons.sync),
                    label: const Text('Eşitle'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
