import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/ekran_okuyucu.dart';
import '../services/kitap_katalog.dart';

const _lacivert = Color(0xFF283593);
const _baslangic = 'https://e-okul.meb.gov.tr/';

/// Sayfadaki (ve aynı kökenli çerçevelerdeki) tablo satırlarını ve
/// tablo dışı yazı satırlarını JSON olarak döndürür.
const _okumaJs = r'''
(function(){
  var out=[];
  function temiz(s){return (s||'').replace(/\s+/g,' ').trim();}
  function gez(doc){
    try{
      var trs=doc.querySelectorAll('tr');
      for(var i=0;i<trs.length;i++){
        var tr=trs[i];
        if(tr.querySelector('table')) continue;
        var c=[];
        for(var k=0;k<tr.cells.length;k++){c.push(temiz(tr.cells[k].innerText));}
        if(c.join('').length) out.push(c);
      }
      var t=(doc.body&&doc.body.innerText)||'';
      var l=t.split('\n');
      for(var j=0;j<l.length;j++){
        if(l[j].indexOf('\t')>=0) continue;
        var x=temiz(l[j]);
        if(x) out.push([x]);
      }
      var fr=doc.querySelectorAll('iframe,frame');
      for(var f=0;f<fr.length;f++){
        try{ if(fr[f].contentDocument) gez(fr[f].contentDocument); }catch(e){}
      }
    }catch(e){}
  }
  gez(document);
  return JSON.stringify(out);
})();
''';

/// Menüdeki tıklanabilir öğeler: [metin, kullanılabilir adres ya da ''].
const _linkJs = r'''
(function(){
  var out=[];
  var el=document.querySelectorAll('a,button,[onclick],[role=menuitem]');
  for(var i=0;i<el.length;i++){
    var t=(el[i].textContent||'').replace(/\s+/g,' ').trim();
    if(!t||t.length>60) continue;
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
  var el=document.querySelectorAll('a,button,[onclick],[role=menuitem]');
  for(var i=0;i<el.length;i++){
    if((el[i].textContent||'').replace(/\\s+/g,' ').trim()===t){el[i].click();return 'ok';}
  }
  return 'yok';
})(${jsonEncode(metin)});
''';

String _katla(String s) => KitapKatalog.kelimelereAyir(s).join(' ');

/// Eşitlemede açılacak sayfalar; anahtarlar öncelik sırasıyla denenir.
const _hedefler = <(String, List<String>)>[
  ('Sınav ve Proje/Ödev Tarihleri', ['sinav ve proje', 'sinav tarihleri']),
  ('Not Bilgisi', ['not bilgisi', 'ders notlari']),
  ('Yıl Sonu Notları', ['yil sonu notlari', 'yil sonu not']),
];

/// Uygulama içinden e-Okul VBS'ye giriş. Giriş bilgileri yalnızca e-Okul /
/// e-Devlet sayfasına yazılır; uygulama bunları okumaz ve saklamaz.
/// Öğrenci menüsü açılınca Eşitle kendiliğinden başlar: sınav tarihleri,
/// not bilgisi ve yıl sonu notları sayfalarını sırayla açıp okur.
class EOkulEkrani extends StatefulWidget {
  const EOkulEkrani({super.key, required this.ogrenciAdi});

  final String ogrenciAdi;

  /// Uygulama açık kaldıkça son VBS sayfası (yeniden giriş gerekmesin diye).
  static String? sonSayfa;

  @override
  State<EOkulEkrani> createState() => _EOkulEkraniState();
}

class _EOkulEkraniState extends State<EOkulEkrani> {
  late final WebViewController _c;
  final _toplanan = EkranSonucu();
  final _metinler = <String, String>{}; // sayfa -> metin (destek için)
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
        onPageFinished: (_) {
          final y = _yuklendi;
          if (y != null && !y.isCompleted) y.complete();
          if (_esitleniyor) return;
          _gecikme?.cancel();
          _gecikme = Timer(const Duration(milliseconds: 1200), _sayfaAcildi);
        },
      ))
      ..loadRequest(Uri.parse(EOkulEkrani.sonSayfa ?? _baslangic));
  }

  @override
  void dispose() {
    _gecikme?.cancel();
    super.dispose();
  }

  Future<Object?> _jsSonuc(String js) async {
    Object r = await _c.runJavaScriptReturningResult(js);
    // Android sonucu JSON dizgesi olarak (tırnaklı) döndürebilir.
    for (var i = 0; i < 2 && r is String; i++) {
      try {
        r = jsonDecode(r as String) as Object;
      } catch (_) {
        break;
      }
    }
    return r;
  }

  Future<List<List<String>>> _satirlar() async {
    final r = await _jsSonuc(_okumaJs);
    if (r is! List) return const [];
    return [
      for (final x in r)
        if (x is List) [for (final c in x) c.toString()],
    ];
  }

  Future<List<(String, String)>> _linkler() async {
    try {
      final r = await _jsSonuc(_linkJs);
      if (r is! List) return const [];
      return [
        for (final x in r)
          if (x is List && x.length >= 2) (x[0].toString(), x[1].toString()),
      ];
    } catch (_) {
      return const [];
    }
  }

  (String, String)? _hedefBul(List<(String, String)> linkler, List<String> anahtarlar) {
    for (final a in anahtarlar) {
      for (final l in linkler) {
        if (_katla(l.$1).contains(a)) return l;
      }
    }
    return null;
  }

  /// Sayfa kendiliğinden yüklendiğinde: oku; öğrenci menüsü görünüyorsa
  /// (giriş yapılmış) ilk seferde eşitlemeyi kendiliğinden başlat.
  Future<void> _sayfaAcildi() async {
    if (!mounted || _esitleniyor) return;
    await _sayfayiOku('Açık sayfa');
    final linkler = await _linkler();
    final menu = _hedefler.where((h) => _hedefBul(linkler, h.$2) != null).length;
    if (menu < 2 || !mounted) return;
    EOkulEkrani.sonSayfa = await _c.currentUrl();
    if (_otomatikDenendi) return;
    _otomatikDenendi = true;
    if (!await _ogrenciDogruMu()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('e-Okul\'da açık öğrenci "${widget.ogrenciAdi}" görünmüyor. '
            'Doğru öğrenciyi seçip Eşitle\'ye basın.'),
      ));
      return;
    }
    await _esitle();
  }

  Future<bool> _ogrenciDogruMu() async {
    try {
      final r = await _jsSonuc('(document.body&&document.body.innerText)||""');
      final sayfa = KitapKatalog.kelimelereAyir(r?.toString() ?? '').toSet();
      final ad = KitapKatalog.kelimelereAyir(widget.ogrenciAdi);
      return ad.isEmpty || ad.every(sayfa.contains);
    } catch (_) {
      return true;
    }
  }

  /// Bir eylemi çalıştırıp sayfa yüklenmesini (en fazla [sure]) bekler.
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

  Future<int> _sayfayiOku(String ad) async {
    try {
      final once = _toplanan.adet;
      final satirlar = await _satirlar();
      _metinler[ad] = satirlar.map((r) => r.join(' | ')).join('\n');
      final sonuc = EkranOkuyucu.metinOku(satirlar);
      if (!mounted) return 0;
      setState(() => _toplanan.ekle(sonuc));
      return _toplanan.adet - once;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _esitle() async {
    if (_esitleniyor) return;
    _gecikme?.cancel();
    setState(() {
      _esitleniyor = true;
      _otomatikDenendi = true;
      _durum = 'Menü inceleniyor...';
    });
    final ana = await _c.currentUrl();
    await _sayfayiOku('Açık sayfa');
    final linkler = await _linkler();
    final eksik = <String>[];
    var sira = 0;
    for (final (ad, anahtarlar) in _hedefler) {
      sira++;
      if (!mounted) return;
      final link = _hedefBul(linkler, anahtarlar);
      if (link == null) {
        eksik.add(ad);
        continue;
      }
      setState(() => _durum = '$ad okunuyor ($sira/${_hedefler.length})');
      try {
        if (link.$2.isNotEmpty) {
          await _bekle(() => _c.loadRequest(Uri.parse(link.$2)));
        } else {
          // Adresi olmayan menü öğesi: menünün olduğu sayfada tıkla.
          if (ana != null && await _c.currentUrl() != ana) {
            await _bekle(() => _c.loadRequest(Uri.parse(ana)));
          }
          await _bekle(() => _c.runJavaScript(_tiklaJs(link.$1)),
              sure: const Duration(seconds: 12));
        }
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        await _sayfayiOku(ad);
      } catch (_) {
        eksik.add(ad);
      }
    }
    // Menünün olduğu sayfaya geri dön (oturum açık kalır).
    if (ana != null && mounted) {
      setState(() => _durum = 'Ana sayfaya dönülüyor...');
      await _bekle(() => _c.loadRequest(Uri.parse(ana)), sure: const Duration(seconds: 10));
      EOkulEkrani.sonSayfa = ana;
    }
    if (!mounted) return;
    setState(() {
      _esitleniyor = false;
      _durum = null;
    });
    if (_toplanan.bos) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(eksik.length == _hedefler.length
            ? 'Önce e-Okul\'a giriş yapıp öğrenciyi seçin; menü açılınca eşitleme kendiliğinden başlar.'
            : 'Sayfalarda bilgi bulunamadı. ⋮ menüsünden "Okunan sayfaları kopyala" ile '
                'metni gönderirseniz okuma düzeltilir.'),
      ));
      return;
    }
    Navigator.pop(context, _toplanan);
  }

  Future<void> _metniKopyala() async {
    if (_metinler.isEmpty) await _sayfayiOku('Açık sayfa');
    final metin = _metinler.entries.map((e) => '=== ${e.key} ===\n${e.value}').join('\n\n');
    await Clipboard.setData(ClipboardData(text: metin));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Okunan sayfaların metni panoya kopyalandı. Paylaşmadan önce '
            'T.C. kimlik numarası gibi bilgileri silin.')));
  }

  Future<void> _oturumuKapat() async {
    await WebViewCookieManager().clearCookies();
    EOkulEkrani.sonSayfa = null;
    _otomatikDenendi = false;
    await _c.loadRequest(Uri.parse(_baslangic));
  }

  @override
  Widget build(BuildContext context) {
    final t = _toplanan;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _esitleniyor) return;
        final nav = Navigator.of(context);
        if (await _c.canGoBack()) {
          await _c.goBack();
        } else {
          nav.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _lacivert,
          foregroundColor: Colors.white,
          title: const Text('e-Okul VBS'),
          actions: [
            IconButton(
                tooltip: 'Yenile',
                onPressed: _esitleniyor ? null : () => _c.reload(),
                icon: const Icon(Icons.refresh)),
            PopupMenuButton<String>(
              enabled: !_esitleniyor,
              onSelected: (v) {
                if (v == 'ana') _c.loadRequest(Uri.parse(_baslangic));
                if (v == 'kopya') _metniKopyala();
                if (v == 'cikis') _oturumuKapat();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'ana', child: Text('e-Okul giriş sayfası')),
                PopupMenuItem(value: 'kopya', child: Text('Okunan sayfaları kopyala')),
                PopupMenuItem(value: 'cikis', child: Text('e-Okul oturumunu kapat')),
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
                            const CircularProgressIndicator(color: _lacivert),
                            const SizedBox(height: 16),
                            Text(_durum ?? 'Eşitleniyor...',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Text(
                                '${t.sinavlar.length} sınav tarihi • ${t.notlar.length} not • '
                                '${t.yilSonlari.length} yıl sonu',
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
                      t.bos
                          ? 'Giriş yapıp öğrenciyi seçin; eşitleme kendiliğinden başlar.'
                          : 'Bulunan: ${t.sinavlar.length} sınav tarihi, '
                              '${t.notlar.length} not, ${t.yilSonlari.length} yıl sonu',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _lacivert),
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
