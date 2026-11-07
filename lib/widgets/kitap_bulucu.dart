import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/kitap_katalog.dart';

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

  @override
  void dispose() {
    _gecikme?.cancel();
    _sorgu.dispose();
    super.dispose();
  }

  void _yazildi(String v) {
    _gecikme?.cancel();
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
              tooltip: 'Barkod okut',
              iconSize: 28,
              onPressed: _barkodOkut,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ],
        ),
        if (_yukleniyor)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
        if (_arandi && _sonuclar.isEmpty)
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
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _mebAc,
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('Hazır listeden seç (MEB, Tonguç • 6-12. sınıf)'),
          ),
        ),
        Text(
          'Barkodu okutun ya da kitabın adını yazın; bulunan kitap seçilince '
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
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA],
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
      final isbn = KitapKatalog.isbnTemizle(ham);
      if (isbn != null) {
        _bitti = true;
        Navigator.of(context).pop(isbn);
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
        title: const Text('Barkodu okutun'),
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
                      'Kitabın arka kapağındaki barkodu çerçeveye getirin.',
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

/// Hazır kitap listeleri (MEB ders kitapları, Tonguç ...): kaynak ve sınıf
/// seçilir, kitaba dokununca döner.
class MebKitapSecici extends StatefulWidget {
  const MebKitapSecici({super.key});

  static int sonSinif = 8;
  static String sonKaynak = 'MEB';

  @override
  State<MebKitapSecici> createState() => _MebKitapSeciciState();
}

const _turBasliklari = {
  'konu': 'Konu anlatımlı',
  'soru': 'Soru bankaları',
  'hazirlik': 'Hazırlık kitapları',
  'deneme': 'Denemeler',
  'diger': 'Diğer',
};

class _MebKitapSeciciState extends State<MebKitapSecici> {
  late final Future<List<HazirKitap>> _liste = KitapKatalog.hazirKitaplar();
  int _sinif = MebKitapSecici.sonSinif;
  String _kaynak = MebKitapSecici.sonKaynak;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<String>(
              segments: [
                for (final k in KitapKatalog.hazirListeler.keys)
                  ButtonSegment(
                      value: k,
                      label: Text(k == 'MEB' ? 'MEB ders kitapları' : '$k Yayınları')),
              ],
              selected: {_kaynak},
              onSelectionChanged: (v) => setState(() {
                _kaynak = v.first;
                MebKitapSecici.sonKaynak = _kaynak;
              }),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
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
                    .where((m) => m.kaynak == _kaynak && m.sinif == _sinif)
                    .toList();
                Widget oge(HazirKitap m) {
                  final k = m.kitap;
                  final alt = [
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
                        child: Text('Bu sınıf için listede kitap yok.'),
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
