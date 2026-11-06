import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../lgs.dart';
import '../../models.dart';
import '../../services/takip_db.dart';
import '../../widgets/common.dart';
import '../../widgets/dyb_giris.dart';
import '../../widgets/grafik.dart';
import 'soru_takibi_tab.dart' show TarihDugmesi;

const _yesil = Color(0xFF2E7D32);

/// Bir ders netinin yaklaşık puan karşılığı.
double _netPuani(LgsDers d) =>
    d.katsayi * (500 - 194.75) / lgsAzamiAgirlikliNet;

/// LGS DENEMELERİ + HEDEF
class LgsTab extends StatefulWidget {
  const LgsTab({super.key, required this.student, required this.me});

  final Student student;
  final AppUser me;

  @override
  State<LgsTab> createState() => _LgsTabState();
}

class _LgsTabState extends State<LgsTab> {
  late final LiveValue<List<LgsDeneme>> _denemeler =
      LiveValue(TakipDb.denemeler(widget.student.id));
  late final LiveValue<LgsHedef> _hedef =
      LiveValue(TakipDb.hedef(widget.student.id));

  @override
  void dispose() {
    _denemeler.dispose();
    _hedef.dispose();
    super.dispose();
  }

  void _denemeAc([LgsDeneme? d]) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            DenemeGirisEkrani(student: widget.student, me: widget.me, deneme: d),
      ));

  Future<void> _hedefDuzenle(LgsHedef h) async {
    final puan = TextEditingController(
        text: h.puan == null ? '' : h.puan!.toStringAsFixed(0));
    final okul = TextEditingController(text: h.okul);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.flag_circle_outlined, size: 36),
        title: const Text('LGS hedefi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: puan,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Hedef puan (ör. 450)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: okul,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Hedef lise (isteğe bağlı)',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
        ],
      ),
    );
    final p = double.tryParse(puan.text.replaceAll(',', '.'));
    final o = okul.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      puan.dispose();
      okul.dispose();
    });
    if (ok != true || !mounted) return;
    if (p != null && (p < 100 || p > 500)) {
      showInfo(context, 'Hedef puan 100 ile 500 arasında olmalı.');
      return;
    }
    await runSafe(context,
        () => TakipDb.hedefKaydet(widget.student.id, widget.me, p, o),
        success: 'Hedef kaydedildi.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([_denemeler, _hedef]),
        builder: (context, _) {
          if (_denemeler.error != null) {
            return EmptyState(
                icon: Icons.error_outline, text: errorText(_denemeler.error!));
          }
          if (_denemeler.loading) return const Loading();
          return _govde(context, _denemeler.value!,
              _hedef.value ?? const LgsHedef());
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_lgs',
        backgroundColor: _yesil,
        foregroundColor: Colors.white,
        onPressed: () => _denemeAc(),
        icon: const Icon(Icons.post_add),
        label: const Text('Deneme Ekle'),
      ),
    );
  }

  Widget _govde(BuildContext context, List<LgsDeneme> liste, LgsHedef hedef) {
    final son = liste.isEmpty ? null : liste.first;
    final son3 = liste.take(3).toList();
    final ort = son3.isEmpty
        ? null
        : son3.fold<double>(0, (a, d) => a + d.gosterilenPuan) / son3.length;
    final enIyi = liste.isEmpty
        ? null
        : liste.map((d) => d.gosterilenPuan).reduce(math.max);

    // Ders ortalama netleri (son 3)
    final dersOrt = <String, double>{};
    for (final d in lgsDersler) {
      if (son3.isEmpty) break;
      final t = son3.fold<double>(0, (a, x) {
        final n = x.dersler[d.ad]?.net ?? 0;
        return a + (n < 0 ? 0 : n);
      });
      dersOrt[d.ad] = t / son3.length;
    }

    final grafikListe = liste.take(12).toList().reversed.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        VurguKart(
          renk: _yesil,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Hedefim',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      hedef.puan == null
                          ? 'Belirlenmedi'
                          : hedef.puan!.toStringAsFixed(0),
                      style: const TextStyle(
                          fontSize: 30, fontWeight: FontWeight.w800),
                    ),
                    if (hedef.okul.isNotEmpty)
                      Text(hedef.okul,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Text(
                      son == null
                          ? 'Henüz deneme girilmedi.'
                          : 'Son deneme: ${son.gosterilenPuan.toStringAsFixed(1)}'
                              '\nSon 3 ortalaması: ${ort!.toStringAsFixed(1)}'
                              '\nEn iyi: ${enIyi!.toStringAsFixed(1)}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.92)),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                      ),
                      onPressed: () => _hedefDuzenle(hedef),
                      icon: const Icon(Icons.flag_outlined, size: 18),
                      label: Text(hedef.puan == null ? 'Hedef belirle' : 'Hedefi değiştir'),
                    ),
                  ],
                ),
              ),
              if (hedef.puan != null && ort != null)
                YuzdeHalka(
                  oran: ort / hedef.puan!,
                  ust: '%${(ort / hedef.puan! * 100).clamp(0, 999).round()}',
                  alt: 'hedefe',
                  renk: Colors.white,
                  boyut: 104,
                ),
            ],
          ),
        ),
        if (liste.isEmpty)
          const EmptyState(
            icon: Icons.assignment_outlined,
            text: 'Tam deneme sınavı sonuçlarını "Deneme Ekle" ile gir.\n'
                'Puanın, gelişim grafiğin ve hedefe ne kadar kaldığı burada görünecek.',
          )
        else ...[
          const SectionTitle('Puan gelişimi'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
              child: CizgiGrafik(
                degerler: grafikListe.map((d) => d.gosterilenPuan).toList(),
                etiketler: grafikListe.map((d) => fmtShort(d.tarih)).toList(),
                hedef: hedef.puan,
                renk: _yesil,
              ),
            ),
          ),
          SectionTitle('Ders netleri (son ${son3.length} ortalama)'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Column(
                children: [
                  for (final d in lgsDersler)
                    DersCubugu(
                      ikon: d.ikon,
                      ad: d.ad,
                      renk: d.renk,
                      oran: (dersOrt[d.ad] ?? 0) / d.soru,
                      deger:
                          '${(dersOrt[d.ad] ?? 0).toStringAsFixed(2)} / ${d.soru}',
                    ),
                ],
              ),
            ),
          ),
          _HedefYolu(dersOrt: dersOrt, hedef: hedef.puan, ort: ort),
          SectionTitle('Denemeler (${liste.length})'),
          for (var i = 0; i < liste.length; i++)
            _DenemeKarti(
              deneme: liste[i],
              onceki: i + 1 < liste.length ? liste[i + 1] : null,
              yetki: widget.me.role.isAdult || liste[i].createdBy == widget.me.uid,
              duzenle: () => _denemeAc(liste[i]),
              sil: () async {
                final ok = await confirm(context,
                    title: 'Deneme silinsin mi?',
                    message: liste[i].ad,
                    ok: 'Sil',
                    destructive: true);
                if (!ok || !mounted) return;
                await runSafe(context,
                    () => TakipDb.sil(widget.student.id, 'lgsDenemeleri', liste[i].id));
              },
            ),
        ],
      ],
    );
  }
}

/// Hedefe ulaşmak için hangi derste kaç net artış gerektiğini önerir.
class _HedefYolu extends StatelessWidget {
  const _HedefYolu({required this.dersOrt, required this.hedef, required this.ort});

  final Map<String, double> dersOrt;
  final double? hedef;
  final double? ort;

  @override
  Widget build(BuildContext context) {
    if (hedef == null || ort == null) return const SizedBox.shrink();
    final fark = hedef! - ort!;
    final cs = Theme.of(context).colorScheme;
    if (fark <= 0) {
      return Card(
        color: Colors.green.shade50,
        margin: const EdgeInsets.only(top: 12),
        child: const ListTile(
          leading: Icon(Icons.emoji_events, color: Colors.amber, size: 36),
          title: Text('Hedefin üzerindesin!'),
          subtitle: Text('Son denemelerin ortalaması hedefini geçti. Böyle devam!'),
        ),
      );
    }
    // Puan kazancı en yüksek olan (katsayı × boş kalan net) derslerden başla.
    final adaylar = lgsDersler
        .map((d) => MapEntry(d, d.soru - (dersOrt[d.ad] ?? 0)))
        .where((e) => e.value > 0.5)
        .toList()
      ..sort((a, b) =>
          (b.value * _netPuani(b.key)).compareTo(a.value * _netPuani(a.key)));
    var kalan = fark;
    final oneriler = <String>[];
    for (final e in adaylar) {
      if (kalan <= 0) break;
      final gerekliNet = math.min(e.value, kalan / _netPuani(e.key));
      final net = (gerekliNet * 2).ceil() / 2; // yarım nete yuvarla
      if (net <= 0) continue;
      kalan -= net * _netPuani(e.key);
      oneriler.add(
          '${e.key.ad}: +${net.toStringAsFixed(net % 1 == 0 ? 0 : 1)} net  (≈ +${(net * _netPuani(e.key)).toStringAsFixed(1)} puan)');
    }
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route_outlined, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Hedefe ${fark.toStringAsFixed(1)} puan kaldı',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Bu farkı en hızlı kapatacak net artışları:'),
            const SizedBox(height: 6),
            for (final o in oneriler)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(o)),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              'Türkçe, Matematik ve Fen\'de 1 net ≈ 4,5 puan; İnkılap, Din ve '
              'İngilizce\'de ≈ 1,1 puan. Puanlar yaklaşık hesaplanır.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _DenemeKarti extends StatelessWidget {
  const _DenemeKarti({
    required this.deneme,
    required this.onceki,
    required this.yetki,
    required this.duzenle,
    required this.sil,
  });

  final LgsDeneme deneme;
  final LgsDeneme? onceki;
  final bool yetki;
  final VoidCallback duzenle;
  final VoidCallback sil;

  @override
  Widget build(BuildContext context) {
    final t = deneme.toplam;
    final degisim =
        onceki == null ? null : deneme.gosterilenPuan - onceki!.gosterilenPuan;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(deneme.ad.isEmpty ? 'Deneme' : deneme.ad,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(
                          [
                            if (deneme.yayin.isNotEmpty) deneme.yayin,
                            fmtDate(deneme.tarih)
                          ].join('  •  '),
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(deneme.gosterilenPuan.toStringAsFixed(1),
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: _yesil)),
                    Text(
                      deneme.puan == null ? 'tahmini puan' : 'puan',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (degisim != null && degisim.abs() >= 0.1)
                      Text(
                        '${degisim > 0 ? '▲' : '▼'} ${degisim.abs().toStringAsFixed(1)}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: degisim > 0
                                ? Colors.green.shade700
                                : Colors.red.shade700),
                      ),
                  ],
                ),
                if (yetki)
                  PopupMenuButton<String>(
                    onSelected: (v) => v == 'd' ? duzenle() : sil(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'd', child: Text('Düzenle')),
                      PopupMenuItem(value: 's', child: Text('Sil')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in lgsDersler)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: d.renk.withValues(alpha: 0.12),
                    label: Text(
                      '${d.kisa} ${(deneme.dersler[d.ad]?.net ?? 0).toStringAsFixed(2)}',
                      style: TextStyle(
                          color: d.renk, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
                'D ${t.d}  Y ${t.y}  B ${t.b}  •  Toplam ${deneme.toplamNet.toStringAsFixed(2)} net'),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Deneme girişi
// ---------------------------------------------------------------------------
class DenemeGirisEkrani extends StatefulWidget {
  const DenemeGirisEkrani(
      {super.key, required this.student, required this.me, this.deneme});

  final Student student;
  final AppUser me;
  final LgsDeneme? deneme;

  @override
  State<DenemeGirisEkrani> createState() => _DenemeGirisEkraniState();
}

class _DenemeGirisEkraniState extends State<DenemeGirisEkrani> {
  late final _ad = TextEditingController(text: widget.deneme?.ad ?? '');
  late final _yayin = TextEditingController(text: widget.deneme?.yayin ?? '');
  late final _puan = TextEditingController(
      text: widget.deneme?.puan == null
          ? ''
          : widget.deneme!.puan!.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), ''));
  late DateTime _tarih = widget.deneme?.tarih ?? today();
  late final Map<String, DybDenetleyici> _d = {
    for (final d in lgsDersler)
      d.ad: DybDenetleyici(widget.deneme?.dersler[d.ad] ?? Dyb.bos),
  };
  bool _mesgul = false;

  @override
  void dispose() {
    _ad.dispose();
    _yayin.dispose();
    _puan.dispose();
    for (final c in _d.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, Dyb> get _dersler => {for (final e in _d.entries) e.key: e.value.deger};

  Future<void> _kaydet() async {
    final dersler = _dersler;
    final toplam = dersler.values.fold(Dyb.bos, (a, b) => a + b);
    if (toplam.toplam == 0) {
      showInfo(context, 'Ders sonuçlarını girin.');
      return;
    }
    for (final d in lgsDersler) {
      if ((dersler[d.ad]?.toplam ?? 0) > d.soru) {
        showInfo(context, '${d.ad} için en fazla ${d.soru} soru girilebilir.');
        return;
      }
    }
    double? puan;
    if (_puan.text.trim().isNotEmpty) {
      puan = double.tryParse(_puan.text.trim().replaceAll(',', '.'));
      if (puan == null || puan < 100 || puan > 500) {
        showInfo(context, 'Puan 100 ile 500 arasında olmalı (ya da boş bırakın).');
        return;
      }
    }
    setState(() => _mesgul = true);
    final nav = Navigator.of(context);
    final ok = await runSafe(
      context,
      () => TakipDb.denemeKaydet(
        widget.student.id,
        widget.me,
        id: widget.deneme?.id,
        ad: _ad.text.trim().isEmpty ? 'Deneme' : _ad.text.trim(),
        yayin: _yayin.text.trim(),
        tarih: _tarih,
        puan: puan,
        dersler: dersler,
      ),
      success: 'Deneme kaydedildi.',
    );
    if (ok) {
      nav.pop();
    } else if (mounted) {
      setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _yesil,
        foregroundColor: Colors.white,
        title: Text(widget.deneme == null ? 'Deneme Sonucu Gir' : 'Denemeyi Düzenle'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 120),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.orange),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              'Buraya yalnızca 6 dersli tam deneme sonuçları girilir. '
                              'Yaprak test ve branş denemeleri için "Soru Takibi"ni kullan.'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ad,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        labelText: 'Deneme adı (ör. Türkiye Geneli 3)',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _yayin,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Yayın / Kurum', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TarihDugmesi(
                      etiket: 'Deneme tarihi',
                      tarih: _tarih,
                      degisti: (t) => setState(() => _tarih = t)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _puan,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Puan (sonuç belgesindeki)',
                      helperText: 'Boş bırakırsan netlerden yaklaşık puan hesaplanır.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: Listenable.merge(_d.values.toList()),
            builder: (context, _) {
              final dersler = _dersler;
              final t = dersler.values.fold(Dyb.bos, (a, b) => a + b);
              return VurguKart(
                renk: _yesil,
                child: Column(
                  children: [
                    DybOzet(d: t.d, y: t.y, b: t.b, net: t.net),
                    const SizedBox(height: 10),
                    Text(
                      'Tahmini puan: ${lgsTahminiPuan(dersler).toStringAsFixed(1)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ],
                ),
              );
            },
          ),
          for (final d in lgsDersler)
            DersDybKart(ders: d, denetleyici: _d[d.ad]!, azami: d.soru),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: _yesil, minimumSize: const Size.fromHeight(52)),
            onPressed: _mesgul ? null : _kaydet,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Denemeyi Kaydet'),
          ),
        ),
      ),
    );
  }
}
