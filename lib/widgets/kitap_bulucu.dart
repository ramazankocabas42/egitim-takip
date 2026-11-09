import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/kapak_okuyucu.dart';
import '../services/kitap_katalog.dart';
import 'common.dart' show DersAyari;

/// Kitap ekleme formlarının üstündeki arama kutusu: ad / yayınevi / ISBN
/// yazarak arar ya da barkod okutur. Seçilen kitap [onSecildi] ile döner.
/// Barkod hiçbir yerde bulunamazsa başlığı boş bir kitap (sadece ISBN) döner.
class KitapBulucu extends StatefulWidget {
  const KitapBulucu({super.key, required this.onSecildi});

  final ValueChanged<KatalogKitap> onSecildi;

  @override
  State<KitapBulucu> createState() => _KitapBulucuState();
}

class _KitapBulucuState extends State<KitapBulucu> {
  final _sorgu = TextEditingController();
  Timer? _gecikme;
  int _istek = 0;
  bool _yukleniyor = false;
  bool _arandi = false;
  List<KatalogKitap> _sonuclar = const [];
  String? _bilgi; // fotoğraf / karekod sonrası açıklama

  @override
  void dispose() {
    _gecikme?.cancel();
    _sorgu.dispose();
    super.dispose();
  }

  void _yazildi(String v) {
    _gecikme?.cancel();
    _bilgi = null;
    if (v.trim().length < 2) {
      setState(() {
        _sonuclar = const [];
        _arandi = false;
        _yukleniyor = false;
      });
      return;
    }
    setState(() {});
    _gecikme = Timer(const Duration(milliseconds: 450), () => _ara(v));
  }

  Future<void> _ara(String v) async {
    final no = ++_istek;
    setState(() => _yukleniyor = true);
    final sonuc = await KitapKatalog.ara(v);
    if (!mounted || no != _istek) return;
    setState(() {
      _sonuclar = sonuc.take(8).toList();
      _yukleniyor = false;
      _arandi = true;
    });
  }

  Future<void> _barkodOkut() async {
    FocusScope.of(context).unfocus();
    final isbn = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarkodTaraEkrani()),
    );
    if (isbn == null || !mounted) return;
    if (isbn.startsWith('q:')) {
      await _karekodIcerigi(isbn.substring(2));
      return;
    }
    final no = ++_istek;
    setState(() {
      _yukleniyor = true;
      _sonuclar = const [];
      _arandi = false;
      _sorgu.text = isbn;
    });
    final k = await KitapKatalog.isbnIleBul(isbn);
    if (!mounted || no != _istek) return;
    setState(() => _yukleniyor = false);
    widget.onSecildi(k ?? KatalogKitap(isbn: isbn, title: ''));
  }

  /// ISBN içermeyen karekod: adres ya da yazıdan anahtar kelimelerle ara.
  Future<void> _karekodIcerigi(String icerik) async {
    var sorgu = icerik.trim();
    final uri = Uri.tryParse(sorgu);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      final parcalar = [
        ...uri.pathSegments,
        ...uri.queryParameters.values,
      ]
          .expand((p) => p.split(RegExp(r'[-_+./]')))
          .where((w) =>
              w.length >= 2 &&
              RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]').hasMatch(w) &&
              !RegExp(r'^(html?|php|aspx?|www|index|urun|product|p|kitap)$', caseSensitive: false)
                  .hasMatch(w) &&
              !RegExp(r'[0-9a-f]{12,}', caseSensitive: false).hasMatch(w))
          .toList();
      sorgu = parcalar.take(8).join(' ');
      if (sorgu.isEmpty) {
        setState(() => _bilgi = 'Karekodda kitap bilgisi yok (${uri.host}). '
            'Kitabın adını yazın ya da kapağın fotoğrafını çekin.');
        return;
      }
    }
    if (sorgu.length > 80) sorgu = sorgu.substring(0, 80);
    setState(() {
      _sorgu.text = sorgu;
      _bilgi = 'Karekoddan okunan: "$sorgu"';
    });
    await _ara(sorgu);
  }

  /// Kapak fotoğrafı: barkod / ISBN yazısı varsa onunla, yoksa kapaktaki
  /// yazılarla (kitap adı, yayınevi) katalogda ve web'de arar.
  Future<void> _fotografla() async {
    FocusScope.of(context).unfocus();
    final XFile? foto;
    try {
      foto = await ImagePicker().pickImage(
          source: ImageSource.camera, maxWidth: 1800, imageQuality: 90);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Kamera açılamadı: $e')));
      }
      return;
    }
    if (foto == null || !mounted) return;
    final no = ++_istek;
    setState(() {
      _yukleniyor = true;
      _sonuclar = const [];
      _arandi = false;
      _bilgi = 'Fotoğraf okunuyor...';
    });
    final kapak = await KapakOkuyucu.oku(foto.path);
    if (!mounted || no != _istek) return;

    if (kapak.isbn != null) {
      final k = await KitapKatalog.isbnIleBul(kapak.isbn!);
      if (!mounted || no != _istek) return;
      if (k != null && k.title.isNotEmpty) {
        setState(() {
          _yukleniyor = false;
          _sorgu.text = kapak.isbn!;
          _bilgi = 'Fotoğraftaki barkod okundu: ${kapak.isbn}';
        });
        widget.onSecildi(k);
        return;
      }
    }

    if (kapak.sorgular.isEmpty) {
      setState(() {
        _yukleniyor = false;
        _bilgi = 'Fotoğrafta okunabilir yazı bulunamadı. Kapağı düz ve aydınlık '
            'bir yerde, yazılar net görünecek şekilde çekin.';
      });
      return;
    }

    setState(() => _bilgi = 'Kapaktan okunan: "${kapak.sorgular.first}" — web\'de aranıyor...');
    final bulunan = <KatalogKitap>[];
    final gorulen = <String>{};
    for (final q in kapak.sorgular) {
      final l = await KitapKatalog.ara(q);
      for (final k in l) {
        final anahtar = k.isbn.isNotEmpty ? k.isbn : k.title.toLowerCase();
        if (gorulen.add(anahtar)) bulunan.add(k);
      }
      if (bulunan.length >= 6) break;
    }
    if (!mounted || no != _istek) return;
    // Barkod okunup katalogda yoksa, bulunan ISBN'siz kitaba bu ISBN'i ver.
    final sonuc = kapak.isbn == null
        ? bulunan
        : [
            for (final k in bulunan)
              k.isbn.isEmpty
                  ? KatalogKitap(
                      isbn: kapak.isbn!,
                      title: k.title,
                      author: k.author,
                      publisher: k.publisher,
                      subject: k.subject,
                      totalPages: k.totalPages,
                      topics: k.topics,
                      kaynak: k.kaynak,
                    )
                  : k,
          ];
    setState(() {
      _yukleniyor = false;
      _arandi = true;
      _sorgu.text = kapak.sorgular.first;
      _sonuclar = sonuc.take(8).toList();
      _bilgi = sonuc.isEmpty
          ? 'Kapaktan okunan: "${kapak.sorgular.first}". Eşleşen kitap bulunamadı; '
              'yazıyı düzeltip arayabilir ya da bilgileri aşağıya girebilirsiniz.'
          : 'Kapaktan okunan: "${kapak.sorgular.first}". Doğru kitabı seçin:';
    });
    if (sonuc.isEmpty && kapak.isbn != null) {
      widget.onSecildi(KatalogKitap(isbn: kapak.isbn!, title: ''));
    }
  }

  String _hazirEtiket() {
    final k = hazirListeKapsami();
    if (k.kaynaklar.contains('AGS') && k.kaynaklar.length == 1) return 'Hazır listeden seç (AGS / ÖABT kitapları)';
    if (k.sinif != null && k.kaynaklar.length < 3) {
      return 'Hazır listeden seç (${k.sinif == 12 && !k.kaynaklar.contains('MEB') ? 'YKS' : '${k.sinif}. sınıf'} kitapları)';
    }
    return 'Hazır listeden seç (MEB, Tonguç, AGS)';
  }

  Future<void> _mebAc() async {
    FocusScope.of(context).unfocus();
    final k = await showModalBottomSheet<KatalogKitap>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const MebKitapSecici(),
    );
    if (k != null && mounted) _sec(k);
  }

  void _sec(KatalogKitap k) {
    FocusScope.of(context).unfocus();
    setState(() {
      _sonuclar = const [];
      _arandi = false;
      _bilgi = null;
    });
    widget.onSecildi(k);
  }

  @override
  Widget build(BuildContext context) {
    final renk = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _sorgu,
                onChanged: _yazildi,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) {
                  _gecikme?.cancel();
                  if (v.trim().length >= 2) _ara(v);
                },
                decoration: InputDecoration(
                  labelText: 'Kitabı bul',
                  hintText: 'Kitap adı, yayınevi ya da ISBN',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: _sorgu.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _sorgu.clear();
                            _yazildi('');
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Barkod / karekod okut',
              iconSize: 28,
              onPressed: _barkodOkut,
              icon: const Icon(Icons.qr_code_scanner),
            ),
            const SizedBox(width: 4),
            IconButton.filledTonal(
              tooltip: 'Kapağın fotoğrafını çek',
              iconSize: 28,
              onPressed: _fotografla,
              icon: const Icon(Icons.photo_camera_outlined),
            ),
          ],
        ),
        if (_yukleniyor)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
        if (_bilgi != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_bilgi!,
                style: TextStyle(fontSize: 12.5, color: renk.primary)),
          ),
        if (_arandi && _sonuclar.isEmpty && _bilgi == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Bulunamadı. Bilgileri aşağıya bir kez yazın; kaydedince '
              'bir dahaki sefere otomatik gelir.',
              style: TextStyle(color: renk.onSurfaceVariant),
            ),
          ),
        if (_sonuclar.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 8),
            child: Column(
              children: _sonuclar
                  .map((k) => ListTile(
                        dense: true,
                        leading: Icon(
                          k.kaynak == 'katalog'
                              ? Icons.verified_outlined
                              : Icons.public,
                          color: k.kaynak == 'katalog' ? renk.primary : null,
                        ),
                        title: Text(k.title,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: k.altBaslik.isEmpty
                            ? null
                            : Text(k.altBaslik,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _sec(k),
                      ))
                  .toList(),
            ),
          ),
        if (hazirListeKapsami().kaynaklar.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _mebAc,
              icon: const Icon(Icons.account_balance_outlined),
              label: Text(_hazirEtiket()),
            ),
          ),
        Text(
          'Barkodu / karekodu okutun, kapağın fotoğrafını çekin ya da kitabın adını yazın; bulunan kitap seçilince '
          'bilgileri tamsa hemen kaydedilir.',
          style: TextStyle(fontSize: 12, color: renk.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Kitabın arkasındaki barkodu (ISBN) okur ve 13 haneli ISBN döndürür.
class BarkodTaraEkrani extends StatefulWidget {
  const BarkodTaraEkrani({super.key});

  @override
  State<BarkodTaraEkrani> createState() => _BarkodTaraEkraniState();
}

class _BarkodTaraEkraniState extends State<BarkodTaraEkrani> {
  final _kontrol = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _bitti = false;
  String? _uyari;

  @override
  void dispose() {
    _kontrol.dispose();
    super.dispose();
  }

  void _okundu(BarcodeCapture yakalanan) {
    if (_bitti) return;
    for (final b in yakalanan.barcodes) {
      final ham = b.rawValue;
      if (ham == null) continue;
      final isbn = KitapKatalog.isbnTemizle(ham) ?? KapakOkuyucu.metindenIsbn(ham);
      if (isbn != null) {
        _bitti = true;
        Navigator.of(context).pop(isbn);
        return;
      }
      final kare = b.format == BarcodeFormat.qrCode || b.format == BarcodeFormat.dataMatrix;
      if (kare && ham.trim().length >= 3) {
        // Karekod: içeriğiyle aranacak
        _bitti = true;
        Navigator.of(context).pop('q:$ham');
        return;
      }
      setState(() => _uyari =
          'Bu bir kitap barkodu değil ($ham). 978 ile başlayan barkodu okutun.');
    }
  }

  Future<void> _elleYaz() async {
    final c = TextEditingController();
    final isbn = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Barkod numarası'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Ör. 9786258149043'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () {
              final v = KitapKatalog.isbnTemizle(c.text);
              if (v == null) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Geçerli bir ISBN değil, rakamları kontrol edin.')));
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    if (isbn != null && mounted && !_bitti) {
      _bitti = true;
      Navigator.of(context).pop(isbn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Barkod / karekod okutun'),
        actions: [
          IconButton(
            tooltip: 'Fener',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _kontrol.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _kontrol, onDetect: _okundu),
          Center(
            child: Container(
              width: 280,
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _uyari ??
                      'Kitabın arka kapağındaki barkodu ya da karekodu çerçeveye getirin.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _elleYaz,
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Numarayı elle yaz'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Barkod hiçbir yerde bulunamadığında ne yapılacağını anlatır.
Future<void> kayitsizKitapUyarisi(BuildContext context, String isbn,
    {required bool testKitabi}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.menu_book_outlined),
      title: const Text('Bu kitap henüz kayıtlı değil'),
      content: Text(
        'Barkod: $isbn\n\n'
        'Kitabın adını ve toplam sayfa sayısını (son sayfa numarası) yazın'
        '${testKitabi ? ', isterseniz içindekiler sayfasından konuları da ekleyin' : ''}.'
        '\n\nBir kez kaydettiğinizde bu barkod, sizde ve diğer kullanıcılarda '
        'bir dahaki sefere otomatik dolu gelir.',
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
      ],
    ),
  );
}

/// Öğrencinin kayıtlı sınıfına / hedef sınavına göre gösterilecek hazır
/// listeler ve sınıf. AGS hedefi: yalnız AGS / ÖABT kitapları; 6-12. sınıf:
/// yalnız o sınıfın MEB ve Tonguç kitapları; mezun + YKS: YKS kitapları.
/// Uygun liste yoksa boş döner (hazır liste düğmesi gizlenir).
({List<String> kaynaklar, int? sinif}) hazirListeKapsami() {
  final g = DersAyari.sinif;
  final h = DersAyari.hedef;
  if (g.isEmpty && h.isEmpty) {
    return (kaynaklar: KitapKatalog.hazirListeler.keys.toList(), sinif: null);
  }
  if (h == 'AGS') return (kaynaklar: const ['AGS'], sinif: null);
  final m = RegExp(r'^(\d+)\. Sınıf$').firstMatch(g);
  final n = m == null ? null : int.parse(m.group(1)!);
  if (n != null && n >= 6 && n <= 12) return (kaynaklar: const ['MEB', 'Tonguç'], sinif: n);
  if (h == 'YKS') return (kaynaklar: const ['Tonguç'], sinif: 12);
  return (kaynaklar: const <String>[], sinif: null);
}

/// Hazır kitap listeleri (MEB ders kitapları, Tonguç ...): kaynak ve sınıf
/// seçilir, kitaba dokununca döner.
class MebKitapSecici extends StatefulWidget {
  const MebKitapSecici({super.key});

  static int sonSinif = 8;
  static String? sonKaynak;
  static String sonDers = 'Tümü';

  @override
  State<MebKitapSecici> createState() => _MebKitapSeciciState();
}

const _turBasliklari = {
  'konu': 'Konu anlatımlı',
  'soru': 'Soru bankaları',
  'hazirlik': 'Hazırlık kitapları',
  'deneme': 'Denemeler',
  'cikmis': 'Çıkmış sorular',
  'diger': 'Diğer',
};

class _MebKitapSeciciState extends State<MebKitapSecici> {
  late final Future<List<HazirKitap>> _liste = KitapKatalog.hazirKitaplar();
  late int _sinif = hazirListeKapsami().sinif ?? MebKitapSecici.sonSinif;
  late final _kapsam = hazirListeKapsami();
  late String _kaynak = _kapsam.kaynaklar.contains(MebKitapSecici.sonKaynak)
      ? MebKitapSecici.sonKaynak!
      : (_kapsam.kaynaklar.isEmpty ? 'MEB' : _kapsam.kaynaklar.first);
  String _ders = MebKitapSecici.sonDers;

  static const _agsDersleri = [
    'Tümü', 'Sözel Yetenek', 'Sayısal Yetenek', 'Tarih', 'Türkiye Coğrafyası',
    'Eğitim Bilimleri', 'Mevzuat', 'Alan Bilgisi (ÖABT)', 'Genel / Karma',
  ];
  bool get _ags => _kaynak == 'AGS';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_kapsam.kaynaklar.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<String>(
              segments: [
                for (final k in _kapsam.kaynaklar)
                  ButtonSegment(
                      value: k,
                      label: Text(k == 'MEB' ? 'MEB' : (k == 'AGS' ? 'AGS / ÖABT' : k))),
              ],
              selected: {_kaynak},
              onSelectionChanged: (v) => setState(() {
                _kaynak = v.first;
                MebKitapSecici.sonKaynak = _kaynak;
              }),
            ),
          ),
          if (_ags || _kapsam.sinif == null)
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (_ags)
                  for (final d in _agsDersleri)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(d == 'Alan Bilgisi (ÖABT)' ? 'PDR ÖABT' : (d == 'Genel / Karma' ? 'Setler' : d)),
                        selected: _ders == d,
                        onSelected: (_) => setState(() {
                          _ders = d;
                          MebKitapSecici.sonDers = d;
                        }),
                      ),
                    )
                else
                for (var s = 6; s <= 12; s++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(s == 12 && _kaynak != 'MEB' ? '12 / YKS' : '$s. Sınıf'),
                      selected: _sinif == s,
                      onSelected: (_) => setState(() {
                        _sinif = s;
                        MebKitapSecici.sonSinif = s;
                      }),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<HazirKitap>>(
              future: _liste,
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final l = snap.data!
                    .where((m) => m.kaynak == _kaynak &&
                        (_ags ? (_ders == 'Tümü' || m.kitap.subject == _ders) : m.sinif == _sinif))
                    .toList();
                Widget oge(HazirKitap m) {
                  final k = m.kitap;
                  final alt = [
                    if (_ags && k.publisher.isNotEmpty) k.publisher,
                    k.subject,
                    if (k.totalPages > 0) '${k.totalPages} sayfa',
                    if (k.isbn.isNotEmpty) 'ISBN ${k.isbn}',
                  ].join(' • ');
                  return ListTile(
                    dense: true,
                    leading: Icon(m.tur == 'konu'
                        ? Icons.auto_stories_outlined
                        : (m.tur == 'soru' || m.tur == 'deneme'
                            ? Icons.quiz_outlined
                            : Icons.menu_book_outlined)),
                    title: Text(k.title),
                    subtitle: Text(alt),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () => Navigator.pop(context, k),
                  );
                }

                Widget baslik(String t) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
                    );
                final gruplar = <String, List<HazirKitap>>{};
                if (_kaynak == 'MEB') {
                  gruplar['Ortak dersler'] = l.where((m) => !m.secmeli).toList();
                  gruplar['Seçmeli dersler'] = l.where((m) => m.secmeli).toList();
                } else {
                  for (final t in _turBasliklari.entries) {
                    gruplar[t.value] = l.where((m) => m.tur == t.key).toList();
                  }
                }
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (l.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Bu seçim için listede kitap yok.'),
                      ),
                    for (final g in gruplar.entries)
                      if (g.value.isNotEmpty) ...[
                        baslik('${g.key} (${g.value.length})'),
                        ...g.value.map(oge),
                      ],
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(
                        'Sayfa sayısı yazmayan kitaplarda seçtikten sonra sayfa sayısını '
                        'girin. Elinizdeki kitabın barkodunu okutmak en doğru sonucu verir.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
