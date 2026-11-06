import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/ekran_okuyucu.dart';

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

/// Uygulama içinden e-Okul VBS'ye giriş. Giriş bilgileri (T.C. no, okul no,
/// güvenlik kodu) yalnızca e-Okul sayfasına yazılır; uygulama bunları
/// okumaz ve saklamaz. Gezilen sayfalardaki sınav tarihi, not ve yıl sonu
/// notları toplanır; "Eşitle" ile Okul sekmesine aktarılır.
class EOkulEkrani extends StatefulWidget {
  const EOkulEkrani({super.key});

  @override
  State<EOkulEkrani> createState() => _EOkulEkraniState();
}

class _EOkulEkraniState extends State<EOkulEkrani> {
  late final WebViewController _c;
  final _toplanan = EkranSonucu();
  int _ilerleme = 0;
  bool _okunuyor = false;
  Timer? _gecikme;

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
          // Sayfa yüklenince sessizce oku (içerik geç gelebilir diye kısa bekle).
          _gecikme?.cancel();
          _gecikme = Timer(const Duration(milliseconds: 900), () => _sayfayiOku());
        },
      ))
      ..loadRequest(Uri.parse(_baslangic));
  }

  @override
  void dispose() {
    _gecikme?.cancel();
    // Ortak telefonda oturum açık kalmasın.
    WebViewCookieManager().clearCookies();
    super.dispose();
  }

  Future<List<List<String>>> _satirlar() async {
    Object r = await _c.runJavaScriptReturningResult(_okumaJs);
    // Android sonucu JSON dizgesi olarak (tırnaklı) döndürebilir.
    for (var i = 0; i < 2 && r is String; i++) {
      try {
        r = jsonDecode(r as String) as Object;
      } catch (_) {
        break;
      }
    }
    if (r is! List) return const [];
    return [
      for (final x in r)
        if (x is List) [for (final c in x) c.toString()],
    ];
  }

  /// Açık sayfayı okur; bulunanları toplananlara ekler. Yeni kayıt sayısını döndürür.
  Future<int> _sayfayiOku() async {
    try {
      final once = _toplanan.adet;
      final sonuc = EkranOkuyucu.metinOku(await _satirlar());
      if (!mounted) return 0;
      setState(() => _toplanan.ekle(sonuc));
      return _toplanan.adet - once;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _esitle() async {
    setState(() => _okunuyor = true);
    await _sayfayiOku();
    if (!mounted) return;
    setState(() => _okunuyor = false);
    if (_toplanan.bos) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(seconds: 6),
        content: Text('Henüz bilgi bulunamadı. Giriş yaptıktan sonra "Sınav Tarihleri", '
            '"Not Bilgileri" ve "Yıl Sonu Notları" sayfalarını açın, sonra Eşitle\'ye basın.'),
      ));
      return;
    }
    Navigator.pop(context, _toplanan);
  }

  Future<void> _metniKopyala() async {
    final satirlar = await _satirlar();
    await Clipboard.setData(
        ClipboardData(text: satirlar.map((r) => r.join(' | ')).join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sayfa metni panoya kopyalandı. Paylaşmadan önce T.C. kimlik '
            'numarası gibi bilgileri silin.')));
  }

  @override
  Widget build(BuildContext context) {
    final t = _toplanan;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
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
                onPressed: () => _c.reload(),
                icon: const Icon(Icons.refresh)),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'ana') _c.loadRequest(Uri.parse(_baslangic));
                if (v == 'kopya') _metniKopyala();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'ana', child: Text('e-Okul ana sayfası')),
                PopupMenuItem(value: 'kopya', child: Text('Sayfa metnini kopyala')),
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
        body: WebViewWidget(controller: _c),
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
                          ? 'Giriş yapın, sonra sınav tarihi / not / yıl sonu sayfalarını açın.'
                          : 'Bulunan: ${t.sinavlar.length} sınav tarihi, '
                              '${t.notlar.length} not, ${t.yilSonlari.length} yıl sonu',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _lacivert),
                    onPressed: _okunuyor ? null : _esitle,
                    icon: _okunuyor
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.sync),
                    label: Text(t.bos ? 'Eşitle' : 'Eşitle (${t.adet})'),
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
