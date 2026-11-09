import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models.dart';
import '../../services/ags_icerik.dart';
import '../../services/osym_db.dart';
import '../../widgets/common.dart';
import '../osym_screen.dart' show pencereJs;

const _yesil = Color(0xFF2E7D32);
const _kaynak = 'gunluk-deneme';
const _osymCikmis =
    'https://www.osym.gov.tr/TR,33337/2025-ags-ve-2025-oabt-temel-soru-kitapciklari-ve-cevap-anahtarlari-yayimlandi-13072025.html';

String _n(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2).replaceAll('.', ',');

const _dersIkon = <String, IconData>{
  'sozel': Icons.menu_book_outlined,
  'sayisal': Icons.calculate_outlined,
  'tarih': Icons.account_balance_outlined,
  'cografya': Icons.public,
  'egitim': Icons.school_outlined,
  'mevzuat': Icons.gavel_outlined,
  'pdr': Icons.psychology_outlined,
};

/// AGS HAZIRLIK: her gün yeni deneme, ders ders konu özetleri ve soru bankası,
/// ÖSYM'nin resmî çıkmış soru sayfası.
class AgsTab extends StatefulWidget {
  const AgsTab({super.key, required this.student, required this.me});

  final Student student;
  final AppUser me;

  @override
  State<AgsTab> createState() => _AgsTabState();
}

class _AgsTabState extends State<AgsTab> {
  late final _sonuclar = LiveValue(OsymDb.sonuclar(widget.student.id));
  AgsIcerik? _icerik;
  List<AgsDenemeBilgi>? _liste;
  String? _hata;
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _sonuclar.dispose();
    super.dispose();
  }

  Future<void> _yukle({bool yenile = false}) async {
    setState(() => _yukleniyor = true);
    try {
      _icerik = await AgsIcerik.yukle();
    } catch (e) {
      _hata = '$e';
    }
    try {
      _liste = await AgsIcerik.denemeListesi(yenile: yenile);
      _hata = null;
    } catch (_) {
      _liste = null;
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  Future<void> _denemeAc(AgsDenemeBilgi? b) async {
    final ic = _icerik;
    if (ic == null) return;
    AgsDeneme d;
    if (b == null) {
      d = ic.cevrimdisiDeneme(AgsIcerik.bugun());
    } else {
      try {
        d = await AgsIcerik.deneme(b);
      } catch (e) {
        if (mounted) showError(context, 'Deneme indirilemedi, internet bağlantını kontrol et.');
        return;
      }
    }
    if (!mounted || d.sorular.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CozumEkrani(
        baslik: d.ad,
        sorular: d.sorular,
        icerik: ic,
        pratik: false,
        kaydet: (cevaplar) => _kaydet(d, cevaplar, ic),
      ),
    ));
  }

  Future<void> _kaydet(AgsDeneme d, List<int?> cevaplar, AgsIcerik ic) async {
    final sid = widget.student.id;
    // Sınav türüne göre (AGS / ÖABT) testleri ve konu eksiklerini topla
    final testler = <String, Map<String, (int, int, int)>>{};
    final konular = <String, Map<String, int>>{};
    for (var i = 0; i < d.sorular.length; i++) {
      final s = d.sorular[i];
      final ders = ic.ders(s.ders);
      if (ders == null) continue;
      final t = testler.putIfAbsent(ders.sinav, () => {});
      final o = t[ders.test] ?? (0, 0, 0);
      final c = cevaplar[i];
      final dogru = c == s.cevap;
      t[ders.test] = (o.$1 + 1, o.$2 + (dogru ? 1 : 0), o.$3 + (c != null && !dogru ? 1 : 0));
      if (!dogru) {
        final k = konular.putIfAbsent(ders.sinav, () => {});
        final key = '${ders.test}|${s.konu}';
        k[key] = (k[key] ?? 0) + 1;
      }
    }
    final tarih = DateTime.tryParse(d.tarih) ?? DateTime.now();
    for (final e in testler.entries) {
      await OsymDb.kaydet(
        sid,
        widget.me,
        tur: e.key,
        ad: d.kayitAdi,
        tarih: tarih,
        resmi: false,
        kaynak: _kaynak,
        testler: {for (final t in e.value.entries) t.key: TestSonucu(soru: t.value.$1, d: t.value.$2, y: t.value.$3)},
        puanlar: const {},
        konuHata: konular[e.key] ?? const {},
      );
    }
  }

  void _cikmisSorular() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const WebSayfa(baslik: 'ÖSYM çıkmış sorular', adres: _osymCikmis),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ic = _icerik;
    if (_yukleniyor && ic == null) return const Loading();
    if (ic == null) return EmptyState(icon: Icons.error_outline, text: _hata ?? 'İçerik açılamadı.');
    return ListenableBuilder(
      listenable: _sonuclar,
      builder: (context, _) {
        final cozulen = <String>{
          for (final s in _sonuclar.value ?? const <OsymSonuc>[])
            if (s.kaynak == _kaynak) s.ad,
        };
        final liste = _liste;
        final bugun = AgsIcerik.bugun();
        final gunun = liste == null || liste.isEmpty ? null : liste.first;
        return RefreshIndicator(
          onRefresh: () => _yukle(yenile: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _GununKarti(
                bilgi: gunun,
                bugunMu: gunun?.tarih == bugun,
                cozuldu: gunun != null && cozulen.contains('Günlük deneme ${gunun.tarih}'),
                cevrimdisi: liste == null,
                onBasla: () => _denemeAc(gunun),
              ),
              if (liste != null && liste.length > 1) ...[
                const SectionTitle('Önceki denemeler'),
                Card(
                  child: Column(children: [
                    for (final b in liste.skip(1).take(30))
                      ListTile(
                        dense: true,
                        leading: Icon(
                          cozulen.contains('Günlük deneme ${b.tarih}') ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: cozulen.contains('Günlük deneme ${b.tarih}') ? _yesil : null,
                        ),
                        title: Text(_tarihYaz(b.tarih)),
                        subtitle: Text('${b.soru} soru'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _denemeAc(b),
                      ),
                  ]),
                ),
              ],
              const SectionTitle('Dersler: konu özeti ve soru bankası'),
              for (final d in ic.dersler)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Icon(_dersIkon[d.id] ?? Icons.book_outlined)),
                    title: Text(d.ad),
                    subtitle: Text('${d.konular.length} konu · ${ic.dersSorulari(d.id).length} soru'
                        '${d.sinav == 'OABT' ? ' · ÖABT' : ''}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => DersEkrani(ders: d, icerik: ic),
                    )),
                  ),
                ),
              const SectionTitle('Çıkmış sorular'),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.history_edu_outlined)),
                  title: const Text('ÖSYM resmî soru kitapçıkları'),
                  subtitle: const Text(
                      'Geçmiş yılların soruları ve cevap anahtarları ÖSYM\'nin sitesinden açılır. '
                      'ÖSYM izni olmadan çoğaltılamadığı için uygulamaya kopyalanmaz.'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.open_in_new),
                  onTap: _cikmisSorular,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Konu özetleri ve sorular bu uygulama için özgün olarak hazırlanmıştır, ÖSYM\'ye ait değildir. '
                'Yapay zekâ desteğiyle yazıldığından nadiren hata içerebilir; şüpheli bir soruyu bildirmen yeterli. '
                'AGS ilk kez 13 Temmuz 2025\'te yapıldı; Eğitim Bilimleri için KPSS çıkmış soruları da faydalıdır.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

String _tarihYaz(String t) {
  final d = DateTime.tryParse(t);
  if (d == null) return t;
  const aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
  return '${d.day} ${aylar[d.month - 1]} ${d.year}';
}

class _GununKarti extends StatelessWidget {
  const _GununKarti({
    required this.bilgi,
    required this.bugunMu,
    required this.cozuldu,
    required this.cevrimdisi,
    required this.onBasla,
  });

  final AgsDenemeBilgi? bilgi;
  final bool bugunMu;
  final bool cozuldu;
  final bool cevrimdisi;
  final VoidCallback onBasla;

  @override
  Widget build(BuildContext context) {
    final b = bilgi;
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.local_fire_department, color: cs.onPrimaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  b == null ? 'Bugünün denemesi' : (bugunMu ? 'Bugünün denemesi' : 'Son deneme · ${_tarihYaz(b.tarih)}'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
                ),
              ),
              if (cozuldu) const Chip(label: Text('Çözüldü'), visualDensity: VisualDensity.compact),
            ]),
            const SizedBox(height: 8),
            Text(
              cevrimdisi
                  ? 'İnternete bağlanılamadı. Soru bankasından 20 soruluk bir deneme hazırlandı.'
                  : '${b?.soru ?? 20} soru: Sözel, Sayısal, Tarih, Coğrafya, Eğitim Bilimleri, Mevzuat ve PDR ÖABT. '
                      'Sonuç ÖSYM Sınavları sekmesine deneme olarak kaydedilir; yanlış konular Önerilerim\'e yansır.',
              style: TextStyle(color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onBasla,
              icon: Icon(cozuldu ? Icons.replay : Icons.play_arrow),
              label: Text(cozuldu ? 'Yeniden çöz' : 'Denemeye başla'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bir dersin konu özetleri ve soru bankası.
class DersEkrani extends StatelessWidget {
  const DersEkrani({super.key, required this.ders, required this.icerik});

  final AgsDers ders;
  final AgsIcerik icerik;

  @override
  Widget build(BuildContext context) {
    final sorular = icerik.dersSorulari(ders.id);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(ders.ad),
          bottom: const TabBar(tabs: [Tab(text: 'Konu özeti'), Tab(text: 'Soru bankası')]),
        ),
        body: TabBarView(children: [
          ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final k in ders.konular)
                Card(
                  child: ExpansionTile(
                    title: Text(k.ad.replaceFirst(RegExp(r'^(Tarih|Coğrafya): '), '')),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(k.ozet, style: const TextStyle(height: 1.45)),
                      const SizedBox(height: 8),
                      if (sorular.any((s) => s.konu == k.ad))
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            icon: const Icon(Icons.quiz_outlined),
                            label: Text('Bu konudan ${sorular.where((s) => s.konu == k.ad).length} soru çöz'),
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => CozumEkrani(
                                baslik: k.ad,
                                sorular: sorular.where((s) => s.konu == k.ad).toList(),
                                icerik: icerik,
                                pratik: true,
                              ),
                            )),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          sorular.isEmpty
              ? const EmptyState(icon: Icons.quiz_outlined, text: 'Bu derste henüz soru yok.')
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('${sorular.length} soru. Her soruda cevabın hemen kontrol edilir ve çözüm açıklaması gösterilir.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Tüm soruları çöz'),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => CozumEkrani(baslik: ders.ad, sorular: sorular, icerik: icerik, pratik: true),
                      )),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.shuffle),
                      label: const Text('Karışık 10 soru'),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => CozumEkrani(
                          baslik: '${ders.ad} · karışık',
                          sorular: ([...sorular]..shuffle()).take(10).toList(),
                          icerik: icerik,
                          pratik: true,
                        ),
                      )),
                    ),
                  ],
                ),
        ]),
      ),
    );
  }
}

/// Soru çözme ekranı. pratik: her soruda anında geri bildirim;
/// deneme: sonda toplu sonuç ve kayıt.
class CozumEkrani extends StatefulWidget {
  const CozumEkrani({
    super.key,
    required this.baslik,
    required this.sorular,
    required this.icerik,
    required this.pratik,
    this.kaydet,
  });

  final String baslik;
  final List<AgsSoru> sorular;
  final AgsIcerik icerik;
  final bool pratik;
  final Future<void> Function(List<int?> cevaplar)? kaydet;

  @override
  State<CozumEkrani> createState() => _CozumEkraniState();
}

class _CozumEkraniState extends State<CozumEkrani> {
  late final List<int?> _cevap = List.filled(widget.sorular.length, null);
  late final List<bool> _kontrol = List.filled(widget.sorular.length, false);
  int _i = 0;
  bool _bitti = false;
  bool _kaydediliyor = false;

  AgsSoru get _s => widget.sorular[_i];
  bool get _goster => widget.pratik && _kontrol[_i];

  Future<void> _bitir() async {
    final bos = _cevap.where((c) => c == null).length;
    if (!widget.pratik && bos > 0) {
      final ok = await confirm(context, title: 'Denemeyi bitir', message: '$bos soru boş. Denemeyi bitirmek istiyor musun?', ok: 'Bitir');
      if (!ok) return;
    }
    if (widget.kaydet != null) {
      setState(() => _kaydediliyor = true);
      await runSafe(context, () => widget.kaydet!(_cevap), success: 'Sonuç ÖSYM Sınavları sekmesine kaydedildi');
      _kaydediliyor = false;
    }
    if (mounted) setState(() => _bitti = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_bitti) return _sonuc(context);
    final s = _s;
    final cs = Theme.of(context).colorScheme;
    final ders = widget.icerik.ders(s.ders);
    final son = _i == widget.sorular.length - 1;
    return PopScope(
      canPop: widget.pratik || _cevap.every((c) => c == null),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await confirm(context, title: 'Denemeden çık', message: 'Çıkarsan işaretlediğin cevaplar kaydedilmez. Çıkılsın mı?', ok: 'Çık', destructive: true)) {
          nav.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.baslik, overflow: TextOverflow.ellipsis),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(value: (_i + 1) / widget.sorular.length),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text('Soru ${_i + 1} / ${widget.sorular.length} · ${ders?.ad ?? s.ders}',
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
            Text(s.konu.replaceFirst(RegExp(r'^(Tarih|Coğrafya): '), ''),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(s.soru, style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.4)),
            const SizedBox(height: 16),
            for (var k = 0; k < s.secenekler.length; k++) _secenek(context, s, k),
            if (_goster) ...[
              const SizedBox(height: 8),
              Card(
                color: _cevap[_i] == s.cevap ? Colors.green.shade50 : Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_cevap[_i] == s.cevap ? 'Doğru!' : 'Doğru cevap: ${'ABCDE'[s.cevap]}) ${s.secenekler[s.cevap]}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                    if (s.aciklama.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(s.aciklama, style: const TextStyle(color: Colors.black87)),
                    ],
                  ]),
                ),
              ),
            ],
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              IconButton.outlined(
                onPressed: _i == 0 ? null : () => setState(() => _i--),
                icon: const Icon(Icons.chevron_left),
              ),
              const SizedBox(width: 8),
              if (!widget.pratik)
                TextButton(
                  onPressed: _cevap[_i] == null ? null : () => setState(() => _cevap[_i] = null),
                  child: const Text('Boş bırak'),
                ),
              const Spacer(),
              if (widget.pratik && !_kontrol[_i])
                FilledButton(
                  onPressed: _cevap[_i] == null ? null : () => setState(() => _kontrol[_i] = true),
                  child: const Text('Kontrol et'),
                )
              else
                FilledButton.icon(
                  onPressed: _kaydediliyor ? null : (son ? _bitir : () => setState(() => _i++)),
                  icon: Icon(son ? Icons.flag : Icons.chevron_right),
                  label: Text(son ? 'Bitir' : 'Sonraki'),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _secenek(BuildContext context, AgsSoru s, int k) {
    final secili = _cevap[_i] == k;
    Color? renk;
    if (_goster) {
      if (k == s.cevap) {
        renk = Colors.green.shade100;
      } else if (secili) {
        renk = Colors.red.shade100;
      }
    } else if (secili) {
      renk = Theme.of(context).colorScheme.secondaryContainer;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: renk ?? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _goster ? null : () => setState(() => _cevap[_i] = k),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: secili ? Theme.of(context).colorScheme.primary : null,
                child: Text('ABCDE'[k],
                    style: TextStyle(fontSize: 12, color: secili ? Colors.white : null)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(s.secenekler[k],
                      style: TextStyle(color: renk != null && _goster ? Colors.black87 : null)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _sonuc(BuildContext context) {
    final ss = widget.sorular;
    var d = 0, y = 0, b = 0;
    final dersler = <String, List<int>>{}; // ders -> [s, d, y]
    final yanlislar = <int>[];
    for (var i = 0; i < ss.length; i++) {
      final c = _cevap[i];
      final l = dersler.putIfAbsent(ss[i].ders, () => [0, 0, 0]);
      l[0]++;
      if (c == null) {
        b++;
        yanlislar.add(i);
      } else if (c == ss[i].cevap) {
        d++;
        l[1]++;
      } else {
        y++;
        l[2]++;
        yanlislar.add(i);
      }
    }
    final net = d - y / 4;
    return Scaffold(
      appBar: AppBar(title: const Text('Sonuç')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(child: StatCard(icon: Icons.check, label: 'Doğru', value: '$d', color: Colors.green)),
            const SizedBox(width: 8),
            Expanded(child: StatCard(icon: Icons.close, label: 'Yanlış', value: '$y', color: Colors.red)),
            const SizedBox(width: 8),
            Expanded(child: StatCard(icon: Icons.remove, label: 'Boş', value: '$b', color: Colors.grey)),
          ]),
          const SizedBox(height: 8),
          Center(
            child: Text('Net: ${_n(net)} / ${ss.length}  (4 yanlış 1 doğruyu götürür)',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const SectionTitle('Derslere göre'),
          Card(
            child: Column(children: [
              for (final e in dersler.entries)
                ListTile(
                  dense: true,
                  leading: Icon(_dersIkon[e.key] ?? Icons.book_outlined),
                  title: Text(widget.icerik.ders(e.key)?.ad ?? e.key),
                  trailing: Text('${e.value[1]} D · ${e.value[2]} Y · ${e.value[0] - e.value[1] - e.value[2]} B'),
                ),
            ]),
          ),
          if (yanlislar.isNotEmpty) ...[
            const SectionTitle('Yanlış ve boşların çözümü'),
            for (final i in yanlislar)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${i + 1}. ${ss[i].konu.replaceFirst(RegExp(r'^(Tarih|Coğrafya): '), '')}',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(ss[i].soru),
                    const SizedBox(height: 6),
                    if (_cevap[i] != null)
                      Text('Senin cevabın: ${'ABCDE'[_cevap[i]!]}) ${ss[i].secenekler[_cevap[i]!]}',
                          style: const TextStyle(color: Colors.red)),
                    Text('Doğru cevap: ${'ABCDE'[ss[i].cevap]}) ${ss[i].secenekler[ss[i].cevap]}',
                        style: const TextStyle(color: _yesil, fontWeight: FontWeight.w600)),
                    if (ss[i].aciklama.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(ss[i].aciklama, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ]),
                ),
              ),
          ],
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tamam')),
        ],
      ),
    );
  }
}

/// Basit uygulama içi web sayfası (ÖSYM resmî sayfaları için).
class WebSayfa extends StatefulWidget {
  const WebSayfa({super.key, required this.baslik, required this.adres});

  final String baslik;
  final String adres;

  @override
  State<WebSayfa> createState() => _WebSayfaState();
}

class _WebSayfaState extends State<WebSayfa> {
  late final WebViewController _c;
  int _ilerleme = 0;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _ilerleme = p),
        onPageFinished: (_) => _c.runJavaScript(pencereJs).catchError((_) {}),
      ))
      ..loadRequest(Uri.parse(widget.adres));
  }

  @override
  Widget build(BuildContext context) {
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
          title: Text(widget.baslik),
          actions: [
            IconButton(
              tooltip: 'ÖSYM AİS (giriş)',
              icon: const Icon(Icons.login),
              onPressed: () => _c.loadRequest(Uri.parse('https://ais.osym.gov.tr/')),
            ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: () => _c.reload()),
          ],
          bottom: _ilerleme < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(value: _ilerleme / 100),
                )
              : null,
        ),
        body: WebViewWidget(controller: _c),
      ),
    );
  }
}
