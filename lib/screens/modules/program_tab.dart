import 'package:flutter/material.dart';

import '../../lgs.dart';
import '../../models.dart';
import '../../services/program_db.dart';
import '../../services/takip_db.dart';
import '../../widgets/common.dart';
import '../../widgets/grafik.dart';

const _yesil = Color(0xFF00897B);
const _calismaRenk = Color(0xFF7E57C2);
final _bosRenk = Colors.green.shade300;
const _yemekRenk = Color(0xFFBCAAA4);

Color _renk(String tur) => switch (tur) {
      'calisma' => _calismaRenk,
      'bos' => _bosRenk,
      'yemek' => _yemekRenk,
      _ => etkinlikTuru(tur).renk,
    };

IconData _ikon(String tur) => switch (tur) {
      'calisma' => Icons.edit_note,
      'bos' => Icons.weekend_outlined,
      'yemek' => Icons.restaurant,
      _ => etkinlikTuru(tur).ikon,
    };

/// HAFTALIK PROGRAM: okul, dershane ve diğer saatler; boş zaman ve
/// önerilen çalışma saatleri.
class ProgramTab extends StatefulWidget {
  const ProgramTab({super.key, required this.student, required this.me});

  final Student student;
  final AppUser me;

  @override
  State<ProgramTab> createState() => _ProgramTabState();
}

class _ProgramTabState extends State<ProgramTab> {
  String get sid => widget.student.id;
  late final LiveValue<List<ProgramEtkinligi>> _etkinlikler =
      LiveValue(ProgramDb.etkinlikler(sid));
  late final LiveValue<GunDuzeni> _duzen = LiveValue(ProgramDb.duzen(sid));
  late final LiveValue<HaftalikPlan?> _plan =
      LiveValue(TakipDb.plan(sid, haftaAnahtari(DateTime.now())));
  late final LiveValue<List<int>> _musait = LiveValue(TakipDb.musaitlik(sid));
  late int _gun = DateTime.now().weekday - 1;

  @override
  void dispose() {
    _etkinlikler.dispose();
    _duzen.dispose();
    _plan.dispose();
    _musait.dispose();
    super.dispose();
  }

  bool _yetki(ProgramEtkinligi e) => widget.me.role.isAdult || e.createdBy == widget.me.uid;

  Future<void> _etkinlikDuzenle([ProgramEtkinligi? e, String? sablon]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _EtkinlikDialog(
          sid: sid, me: widget.me, etkinlik: e, sablon: sablon),
    );
  }

  Future<void> _duzenDuzenle(GunDuzeni d) async {
    await openSheet<void>(context, _DuzenSheet(sid: sid, me: widget.me, duzen: d));
  }

  Future<void> _plana(List<GunAnalizi> hafta) async {
    final dk = hafta.map((g) => g.calismaDk).toList();
    await runSafe(context, () => TakipDb.musaitlikKaydet(sid, widget.me, dk),
        success: 'Çalışma süreleri Plan sekmesine aktarıldı. Orada "Adaptif plan '
            'hazırla" ile ders ders plan oluşturabilirsin.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([_etkinlikler, _duzen, _plan, _musait]),
        builder: (context, _) {
          if (_etkinlikler.error != null) {
            return EmptyState(
                icon: Icons.error_outline, text: errorText(_etkinlikler.error!));
          }
          if (_etkinlikler.loading) return const Loading();
          final duzen = _duzen.value ?? const GunDuzeni();
          final motor = ZamanMotoru(_etkinlikler.value!, duzen);
          final hafta = motor.hafta(plan: _plan.value);
          return _govde(context, _etkinlikler.value!, duzen, hafta);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_program',
        backgroundColor: _yesil,
        foregroundColor: Colors.white,
        onPressed: () => _etkinlikDuzenle(),
        icon: const Icon(Icons.add),
        label: const Text('Etkinlik'),
      ),
    );
  }

  Widget _govde(BuildContext context, List<ProgramEtkinligi> etk, GunDuzeni duzen,
      List<GunAnalizi> hafta) {
    final bugunNo = DateTime.now().weekday - 1;
    final secili = hafta[_gun];
    final toplamCalisma = hafta.fold(0, (s, g) => s + g.calismaDk);
    final toplamBos = hafta.fold(0, (s, g) => s + g.bosDk);
    final musait = _musait.value ?? TakipDb.varsayilanMusaitlik;
    final planlaUyumlu =
        List.generate(7, (g) => (musait[g] - hafta[g].calismaDk).abs() <= 10).every((x) => x);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        _bugunKarti(hafta[bugunNo]),
        if (etk.isEmpty) _hizliBaslangic(),
        // Gün seçici
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var g = 0; g < 7; g++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(g == bugunNo ? '${gunKisa[g]} •' : gunKisa[g]),
                    selected: _gun == g,
                    selectedColor: _yesil.withValues(alpha: 0.2),
                    onSelected: (_) => setState(() => _gun = g),
                  ),
                ),
            ],
          ),
        ),
        _gunKarti(secili),
        SectionTitle('Haftalık görünüm'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
            child: Column(
              children: [
                for (final g in hafta)
                  InkWell(
                    onTap: () => setState(() => _gun = g.gun),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                              width: 34,
                              child: Text(gunKisa[g.gun],
                                  style: TextStyle(
                                      fontWeight: g.gun == _gun
                                          ? FontWeight.w800
                                          : FontWeight.w500))),
                          Expanded(child: _GunCubugu(g)),
                          SizedBox(
                            width: 58,
                            child: Text(sureYaz(g.calismaDk),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _calismaRenk)),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                const Row(
                  children: [
                    SizedBox(width: 34),
                    Expanded(child: _SaatEtiketleri()),
                    SizedBox(width: 58),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    for (final t in {...etk.map((e) => e.tur)})
                      _Lejant(_renk(t), etkinlikTuru(t).ad),
                    _Lejant(_bosRenk, 'Boş'),
                    const _Lejant(_calismaRenk, 'Önerilen çalışma'),
                  ],
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
                child: StatCard(
                    icon: Icons.weekend_outlined,
                    label: 'Haftalık boş zaman',
                    value: sureYaz(toplamBos),
                    color: Colors.green)),
            const SizedBox(width: 8),
            Expanded(
                child: StatCard(
                    icon: Icons.edit_note,
                    label: 'Önerilen çalışma',
                    value: sureYaz(toplamCalisma),
                    color: _calismaRenk)),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (final t in etkinlikTurleri)
                if (hafta.any((g) => g.sureOf(t.id) > 0))
                  ListTile(
                    dense: true,
                    leading: Icon(t.ikon, color: t.renk),
                    title: Text(t.ad),
                    trailing: Text(
                        '${sureYaz(hafta.fold(0, (s, g) => s + g.sureOf(t.id)))} / hafta',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: planlaUyumlu
                    ? const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 18),
                          SizedBox(width: 6),
                          Expanded(
                              child: Text(
                                  'Çalışma planındaki süreler bu programla uyumlu.',
                                  style: TextStyle(fontSize: 12.5))),
                        ],
                      )
                    : FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: _calismaRenk,
                            minimumSize: const Size.fromHeight(46)),
                        onPressed: () => _plana(hafta),
                        icon: const Icon(Icons.sync_alt),
                        label: const Text('Önerilen süreleri çalışma planına aktar'),
                      ),
              ),
            ],
          ),
        ),
        SectionTitle('Etkinlikler (${etk.length})'),
        if (etk.isEmpty)
          const Card(
              child: Padding(
            padding: EdgeInsets.all(14),
            child: Text('Okul, dershane, kurs gibi düzenli saatleri ekleyin.'),
          ))
        else
          for (final e in etk) _etkinlikKarti(e),
        const SectionTitle('Gün düzeni'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.bedtime_outlined, color: _yesil),
            title: Text('Hafta içi ${saatYaz(duzen.haftaIciKalkis)}–${saatYaz(duzen.haftaIciYatma)}, '
                'hafta sonu ${saatYaz(duzen.haftaSonuKalkis)}–${saatYaz(duzen.haftaSonuYatma)}'),
            subtitle: Text('Yemek ${saatYaz(duzen.yemekBas)} (${duzen.yemekDk} dk) • yol '
                '${duzen.yolDk} dk • dönüş molası ${duzen.dinlenmeDk} dk\n'
                'Günlük çalışma hedefi: hafta içi ${sureYaz(duzen.hedefHaftaIci)}, '
                'hafta sonu ${sureYaz(duzen.hedefHaftaSonu)}'),
            isThreeLine: true,
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _duzenDuzenle(duzen),
          ),
        ),
      ],
    );
  }

  Widget _bugunKarti(GunAnalizi g) {
    final simdi = DateTime.now().hour * 60 + DateTime.now().minute;
    final akis = g.akis;
    Aralik? su;
    for (final a in akis) {
      if (a.bas <= simdi && simdi < a.bit) su = a;
    }
    final sonraki = g.calisma.where((c) => c.bas > simdi).toList();
    String durum;
    if (simdi < g.kalkis || simdi >= g.yatma) {
      durum = 'Uyku saati 🌙';
    } else if (su == null) {
      durum = 'Şu an hazırlık / yol / mola zamanı';
    } else if (su.tur == 'calisma') {
      durum = 'Şu an çalışma zamanı: ${su.ad} (${saatYaz(su.bit)}\'e kadar)';
    } else if (su.tur == 'bos') {
      durum = 'Şu an serbest zaman';
    } else {
      durum = 'Şu an: ${su.ad} (${saatYaz(su.bit)}\'e kadar)';
    }
    return VurguKart(
      renk: _yesil,
      child: Row(
        children: [
          YuzdeHalka(
            oran: g.bosDk == 0 ? 0 : (g.calismaDk / g.bosDk).clamp(0, 1).toDouble(),
            ust: sureYaz(g.calismaDk),
            alt: 'çalışma',
            renk: Colors.white,
            boyut: 96,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bugün • ${gunUzun[g.gun]}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(durum),
                const SizedBox(height: 4),
                Text('Etkinlik ${sureYaz(g.etkinlikDk)} • boş ${sureYaz(g.bosDk)}',
                    style: const TextStyle(fontSize: 12.5)),
                if (sonraki.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Sıradaki çalışma: ${saatYaz(sonraki.first.bas)} — ${sonraki.first.ad}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hizliBaslangic() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hızlı başlangıç',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Hazır şablonu seçip saatleri düzeltin:'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ActionChip(
                    avatar: const Icon(Icons.school, size: 18),
                    label: const Text('Okul (Pzt–Cum)'),
                    onPressed: () => _etkinlikDuzenle(null, 'okul')),
                ActionChip(
                    avatar: const Icon(Icons.apartment, size: 18),
                    label: const Text('Dershane hafta içi'),
                    onPressed: () => _etkinlikDuzenle(null, 'dershane')),
                ActionChip(
                    avatar: const Icon(Icons.apartment, size: 18),
                    label: const Text('Dershane hafta sonu'),
                    onPressed: () => _etkinlikDuzenle(null, 'dershaneHs')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _gunKarti(GunAnalizi g) {
    final akis = g.akis;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${gunUzun[g.gun]} akışı',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                Text('Boş ${sureYaz(g.bosDk)}',
                    style: TextStyle(
                        color: Colors.green.shade700, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            _GunCubugu(g, yukseklik: 22),
            const SizedBox(height: 4),
            const _SaatEtiketleri(),
            const SizedBox(height: 8),
            _satir(Aralik(g.kalkis, g.kalkis, ad: 'Kalkış', tur: 'kalkis'),
                ikon: Icons.wb_sunny_outlined, renk: Colors.amber.shade700),
            for (final a in akis) _satir(a),
            _satir(Aralik(g.yatma, g.yatma, ad: 'Yatış', tur: 'yatis'),
                ikon: Icons.bedtime_outlined, renk: Colors.indigo),
          ],
        ),
      ),
    );
  }

  Widget _satir(Aralik a, {IconData? ikon, Color? renk}) {
    final r = renk ?? _renk(a.tur);
    final tekNokta = a.bas == a.bit;
    final baslik = switch (a.tur) {
      'bos' => 'Serbest zaman',
      'calisma' => a.ad == 'Ders çalışma' ? 'Ders çalışma' : '${a.ad} çalışması',
      _ => a.ad,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
                tekNokta ? saatYaz(a.bas) : '${saatYaz(a.bas)}–${saatYaz(a.bit)}',
                style: const TextStyle(fontSize: 12.5)),
          ),
          Container(
            width: 4,
            height: 30,
            decoration:
                BoxDecoration(color: r, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 8),
          Icon(ikon ?? _ikon(a.tur), size: 18, color: r),
          const SizedBox(width: 6),
          Expanded(
            child: Text(baslik,
                style: TextStyle(
                    fontWeight:
                        a.tur == 'calisma' ? FontWeight.w700 : FontWeight.w500)),
          ),
          if (!tekNokta)
            Text(sureYaz(a.sure),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ],
      ),
    );
  }

  Widget _etkinlikKarti(ProgramEtkinligi e) {
    final t = etkinlikTuru(e.tur);
    final gunler = e.gunler.length == 5 && e.gunler.every((g) => g < 5)
        ? 'Hafta içi'
        : (e.gunler.length == 7 ? 'Her gün' : e.gunler.map((g) => gunKisa[g]).join(', '));
    return Card(
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: t.renk.withValues(alpha: 0.14),
            child: Icon(t.ikon, color: t.renk)),
        title: Text(e.ad, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('$gunler • ${saatYaz(e.bas)}–${saatYaz(e.bit)}'),
        trailing: Text(sureYaz(e.sure * e.gunler.length),
            style: TextStyle(color: t.renk, fontWeight: FontWeight.w700)),
        onTap: _yetki(e) ? () => _etkinlikDuzenle(e) : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gün çubuğu (06:00 - 24:00)
// ---------------------------------------------------------------------------
const _cubukBas = 6 * 60, _cubukBit = 24 * 60;

class _GunCubugu extends StatelessWidget {
  const _GunCubugu(this.g, {this.yukseklik = 14});

  final GunAnalizi g;
  final double yukseklik;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      double x(int dk) =>
          ((dk.clamp(_cubukBas, _cubukBit) - _cubukBas) / (_cubukBit - _cubukBas)) * w;
      return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          height: yukseklik,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: Colors.grey.shade300)),
              // Uyanık olunan süre
              Positioned(
                left: x(g.kalkis),
                width: x(g.yatma) - x(g.kalkis),
                top: 0,
                bottom: 0,
                child: ColoredBox(color: Colors.grey.shade100),
              ),
              for (final a in g.akis)
                Positioned(
                  left: x(a.bas),
                  width: (x(a.bit) - x(a.bas)).clamp(0, w).toDouble(),
                  top: 0,
                  bottom: 0,
                  child: ColoredBox(color: _renk(a.tur)),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _SaatEtiketleri extends StatelessWidget {
  const _SaatEtiketleri();

  @override
  Widget build(BuildContext context) {
    const saatler = [6, 9, 12, 15, 18, 21, 24];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final s in saatler)
          Text(s.toString().padLeft(2, '0'),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }
}

class _Lejant extends StatelessWidget {
  const _Lejant(this.renk, this.ad);
  final Color renk;
  final String ad;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: renk, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(ad, style: const TextStyle(fontSize: 11.5)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Etkinlik ekleme / düzenleme
// ---------------------------------------------------------------------------
class _EtkinlikDialog extends StatefulWidget {
  const _EtkinlikDialog(
      {required this.sid, required this.me, this.etkinlik, this.sablon});

  final String sid;
  final AppUser me;
  final ProgramEtkinligi? etkinlik;
  final String? sablon;

  @override
  State<_EtkinlikDialog> createState() => _EtkinlikDialogState();
}

class _EtkinlikDialogState extends State<_EtkinlikDialog> {
  late final TextEditingController _ad;
  late String _tur;
  late Set<int> _gunler;
  late int _bas, _bit;
  bool _mesgul = false;

  @override
  void initState() {
    super.initState();
    final e = widget.etkinlik;
    switch (widget.sablon) {
      case 'okul':
        _ad = TextEditingController(text: 'Okul');
        _tur = 'okul';
        _gunler = {0, 1, 2, 3, 4};
        _bas = 8 * 60 + 20;
        _bit = 15 * 60 + 10;
      case 'dershane':
        _ad = TextEditingController(text: 'Dershane');
        _tur = 'dershane';
        _gunler = {0, 2, 4};
        _bas = 16 * 60;
        _bit = 18 * 60 + 30;
      case 'dershaneHs':
        _ad = TextEditingController(text: 'Dershane');
        _tur = 'dershane';
        _gunler = {5, 6};
        _bas = 9 * 60 + 30;
        _bit = 14 * 60;
      default:
        _ad = TextEditingController(text: e?.ad ?? '');
        _tur = e?.tur ?? 'okul';
        _gunler = {...?e?.gunler};
        _bas = e?.bas ?? 16 * 60;
        _bit = e?.bit ?? 18 * 60;
    }
  }

  @override
  void dispose() {
    _ad.dispose();
    super.dispose();
  }

  Future<void> _saatSec(bool bas) async {
    final d = bas ? _bas : _bit;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: d ~/ 60, minute: d % 60),
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return;
    setState(() {
      if (bas) {
        _bas = t.hour * 60 + t.minute;
      } else {
        _bit = t.hour * 60 + t.minute;
      }
    });
  }

  Future<void> _kaydet() async {
    final ad = _ad.text.trim().isEmpty ? etkinlikTuru(_tur).ad : _ad.text.trim();
    if (_gunler.isEmpty) {
      showInfo(context, 'En az bir gün seçin.');
      return;
    }
    if (_bit <= _bas) {
      showInfo(context, 'Bitiş saati başlangıçtan sonra olmalı.');
      return;
    }
    setState(() => _mesgul = true);
    final nav = Navigator.of(context);
    final ok = await runSafe(
      context,
      () => ProgramDb.etkinlikKaydet(widget.sid, widget.me,
          id: widget.etkinlik?.id,
          ad: ad,
          tur: _tur,
          gunler: _gunler.toList()..sort(),
          bas: _bas,
          bit: _bit),
      success: 'Kaydedildi.',
    );
    if (ok) {
      nav.pop();
    } else if (mounted) {
      setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.etkinlik == null ? 'Etkinlik ekle' : 'Etkinliği düzenle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _tur,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Tür', border: OutlineInputBorder()),
              items: [
                for (final t in etkinlikTurleri)
                  DropdownMenuItem(
                    value: t.id,
                    child: Row(children: [
                      Icon(t.ikon, color: t.renk, size: 20),
                      const SizedBox(width: 8),
                      Text(t.ad),
                    ]),
                  ),
              ],
              onChanged: (v) => setState(() => _tur = v ?? _tur),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ad,
              decoration: InputDecoration(
                  labelText: 'Ad (ör. ${etkinlikTuru(_tur).ad})',
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            const Text('Günler', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                for (var g = 0; g < 7; g++)
                  FilterChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(gunKisa[g]),
                    selected: _gunler.contains(g),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _gunler.add(g);
                      } else {
                        _gunler.remove(g);
                      }
                    }),
                  ),
              ],
            ),
            Wrap(
              spacing: 6,
              children: [
                TextButton(
                    onPressed: () => setState(() => _gunler = {0, 1, 2, 3, 4}),
                    child: const Text('Hafta içi')),
                TextButton(
                    onPressed: () => setState(() => _gunler = {5, 6}),
                    child: const Text('Hafta sonu')),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _saatSec(true),
                    icon: const Icon(Icons.login),
                    label: Text(saatYaz(_bas)),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('–'),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _saatSec(false),
                    icon: const Icon(Icons.logout),
                    label: Text(saatYaz(_bit)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (widget.etkinlik != null)
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              final ok = await runSafe(
                  context, () => ProgramDb.etkinlikSil(widget.sid, widget.etkinlik!.id));
              if (ok) nav.pop();
            },
            child: Text('Sil', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _mesgul ? null : _kaydet, child: const Text('Kaydet')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Gün düzeni ayarları
// ---------------------------------------------------------------------------
class _DuzenSheet extends StatefulWidget {
  const _DuzenSheet({required this.sid, required this.me, required this.duzen});

  final String sid;
  final AppUser me;
  final GunDuzeni duzen;

  @override
  State<_DuzenSheet> createState() => _DuzenSheetState();
}

class _DuzenSheetState extends State<_DuzenSheet> {
  late final Map<String, int> _d =
      widget.duzen.toMap().map((k, v) => MapEntry(k, v as int));

  Future<void> _saat(String k) async {
    final v = _d[k]!;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (v ~/ 60) % 24, minute: v % 60),
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return;
    var dk = t.hour * 60 + t.minute;
    // Gece yarısından sonra yatış (ör. 00:30) -> 24:30
    if (k.endsWith('Yatma') && dk < 4 * 60) dk += 24 * 60;
    setState(() => _d[k] = dk);
  }

  Widget _saatSatiri(String k, String ad, IconData ikon) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(ikon, color: _yesil),
        title: Text(ad),
        trailing: OutlinedButton(onPressed: () => _saat(k), child: Text(saatYaz(_d[k]!))),
      );

  Widget _sureSatiri(String k, String ad, int adim, int enAz, int enCok) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(ad),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                onPressed: _d[k]! - adim < enAz
                    ? null
                    : () => setState(() => _d[k] = _d[k]! - adim),
                icon: const Icon(Icons.remove_circle_outline)),
            SizedBox(
                width: 64,
                child: Text(sureYaz(_d[k]!),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            IconButton(
                onPressed: _d[k]! + adim > enCok
                    ? null
                    : () => setState(() => _d[k] = _d[k]! + adim),
                icon: const Icon(Icons.add_circle_outline)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: 'Gün düzeni',
      children: [
        _saatSatiri('haftaIciKalkis', 'Hafta içi kalkış', Icons.wb_sunny_outlined),
        _saatSatiri('haftaIciYatma', 'Hafta içi yatış', Icons.bedtime_outlined),
        _saatSatiri('haftaSonuKalkis', 'Hafta sonu kalkış', Icons.wb_sunny_outlined),
        _saatSatiri('haftaSonuYatma', 'Hafta sonu yatış', Icons.bedtime_outlined),
        _saatSatiri('yemekBas', 'Akşam yemeği', Icons.restaurant),
        _sureSatiri('yemekDk', 'Yemek süresi', 15, 0, 120),
        _sureSatiri('yolDk', 'Yol / hazırlık (gidiş ve dönüş)', 5, 0, 90),
        _sureSatiri('dinlenmeDk', 'Dönüşte dinlenme molası', 15, 0, 120),
        const Divider(),
        _sureSatiri('hedefHaftaIci', 'Günlük çalışma hedefi (hafta içi)', 30, 0, 480),
        _sureSatiri('hedefHaftaSonu', 'Günlük çalışma hedefi (hafta sonu)', 30, 0, 600),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: _yesil, minimumSize: const Size.fromHeight(48)),
          onPressed: () async {
            final nav = Navigator.of(context);
            final ok = await runSafe(
                context,
                () => ProgramDb.duzenKaydet(
                    widget.sid, widget.me, widget.duzen.kopya(_d)),
                success: 'Kaydedildi.');
            if (ok) nav.pop();
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
