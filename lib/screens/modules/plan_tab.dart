import 'dart:async';

import 'package:flutter/material.dart';

import '../../lgs.dart';
import '../../models.dart';
import '../../services/plan_motoru.dart';
import '../../services/takip_db.dart';
import '../../widgets/common.dart';
import '../../widgets/grafik.dart';

const _mor = Color(0xFF7E57C2);

/// HAFTALIK ÇALIŞMA PLANI
class PlanTab extends StatefulWidget {
  const PlanTab({super.key, required this.student, required this.me});

  final Student student;
  final AppUser me;

  @override
  State<PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<PlanTab> {
  String get sid => widget.student.id;

  late DateTime _haftaBasi = haftaBasi(DateTime.now());
  late int _gun = DateTime.now().weekday - 1;
  bool _cizelge = false;
  bool _mesgul = false;

  StreamSubscription<HaftalikPlan?>? _planAbone;
  HaftalikPlan? _plan;
  bool _planYukleniyor = true;
  Object? _planHata;

  late final LiveValue<List<int>> _musait = LiveValue(TakipDb.musaitlik(sid));
  late final LiveValue<List<SoruGirisi>> _sorular = LiveValue(TakipDb.sorular(sid));
  late final LiveValue<List<LgsDeneme>> _denemeler =
      LiveValue(TakipDb.denemeler(sid));
  Future<HaftalikPlan?>? _oncekiPlan;

  String get _hafta => haftaAnahtari(_haftaBasi);
  bool get _buHafta => DateUtils.isSameDay(_haftaBasi, haftaBasi(DateTime.now()));

  @override
  void initState() {
    super.initState();
    _haftaYukle(ilk: true);
  }

  void _haftaYukle({bool ilk = false}) {
    _planAbone?.cancel();
    _planYukleniyor = true;
    _plan = null;
    _planHata = null;
    if (!ilk) setState(() {});
    _planAbone = TakipDb.plan(sid, _hafta).listen(
      (p) {
        if (!mounted) return;
        setState(() {
          _plan = p;
          _planYukleniyor = false;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _planHata = e;
          _planYukleniyor = false;
        });
      },
    );
    _oncekiPlan = TakipDb.planGetir(
        sid, haftaAnahtari(_haftaBasi.subtract(const Duration(days: 7))));
  }

  @override
  void dispose() {
    _planAbone?.cancel();
    _musait.dispose();
    _sorular.dispose();
    _denemeler.dispose();
    super.dispose();
  }

  void _haftaDegistir(int yon) {
    _haftaBasi = _haftaBasi.add(Duration(days: 7 * yon));
    _gun = _buHafta ? DateTime.now().weekday - 1 : 0;
    _haftaYukle();
  }

  Future<void> _kaydet(HaftalikPlan p, {String? mesaj}) async {
    setState(() => _plan = p); // anında göster
    await runSafe(context, () => TakipDb.planKaydet(sid, widget.me, p),
        success: mesaj);
  }

  Future<void> _adaptifHazirla() async {
    final mevcut = _plan;
    if (mevcut != null && mevcut.toplamDakika > 0) {
      final ok = await confirm(context,
          title: 'Plan yeniden hazırlansın mı?',
          message: 'Bu haftanın mevcut planı silinip son çalışma verilerine '
              'göre yeni bir plan hazırlanacak. Tamamlandı işaretleri sıfırlanır.',
          ok: 'Hazırla');
      if (!ok || !mounted) return;
    }
    setState(() => _mesgul = true);
    final motor = PlanMotoru(
      sorular: _sorular.value ?? const [],
      denemeler: _denemeler.value ?? const [],
    );
    final p = motor.uret(_hafta, _musait.value ?? TakipDb.varsayilanMusaitlik);
    if (p.toplamDakika == 0) {
      setState(() => _mesgul = false);
      showInfo(context, 'Müsaitlik süreleri boş. Önce haftalık müsait sürelerini girin.');
      return;
    }
    await _kaydet(p, mesaj: 'Haftalık plan hazırlandı: ${sureYaz(p.toplamDakika)}');
    if (mounted) setState(() => _mesgul = false);
  }

  Future<void> _musaitlikDuzenle() async {
    final ilk = List.of(_musait.value ?? TakipDb.varsayilanMusaitlik);
    final sonuc = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MusaitlikSayfasi(ilk: ilk),
    );
    if (sonuc == null || !mounted) return;
    await runSafe(context, () => TakipDb.musaitlikKaydet(sid, widget.me, sonuc),
        success: 'Müsaitlik kaydedildi. Planı yenilemek için "Adaptif plan hazırla"ya bas.');
  }

  Future<void> _blokDuzenle(int gun, [int? indeks]) async {
    final p = _plan ?? HaftalikPlan.bos(_hafta);
    final eski = indeks == null ? null : p.gunler[gun][indeks];
    final yeni = await showDialog<PlanBlok>(
      context: context,
      builder: (_) => _BlokDialog(blok: eski),
    );
    if (yeni == null) return;
    final gunler = [for (final g in p.gunler) List.of(g)];
    if (indeks == null) {
      gunler[gun].add(yeni);
    } else {
      gunler[gun][indeks] = yeni;
    }
    await _kaydet(HaftalikPlan(hafta: _hafta, gunler: gunler, adaptif: p.adaptif));
  }

  Future<void> _blokSil(int gun, int indeks) async {
    final p = _plan!;
    final gunler = [for (final g in p.gunler) List.of(g)];
    gunler[gun].removeAt(indeks);
    await _kaydet(HaftalikPlan(hafta: _hafta, gunler: gunler, adaptif: p.adaptif));
  }

  Future<void> _tamamDegistir(int gun, int indeks, bool v) async {
    final p = _plan!;
    final gunler = [for (final g in p.gunler) List.of(g)];
    gunler[gun][indeks] = gunler[gun][indeks].kopya(tamam: v);
    await _kaydet(HaftalikPlan(hafta: _hafta, gunler: gunler, adaptif: p.adaptif));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_musait, _sorular, _denemeler]),
      builder: (context, _) {
        if (_planHata != null) {
          return EmptyState(icon: Icons.error_outline, text: errorText(_planHata!));
        }
        if (_planYukleniyor) return const Loading();
        return _govde(context);
      },
    );
  }

  Widget _govde(BuildContext context) {
    final plan = _plan;
    final bitis = _haftaBasi.add(const Duration(days: 6));
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
      children: [
        Row(
          children: [
            IconButton(
                onPressed: () => _haftaDegistir(-1),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text(
                '${fmtShort(_haftaBasi)} – ${fmtShort(bitis)}${_buHafta ? '  (bu hafta)' : ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
                onPressed: () => _haftaDegistir(1),
                icon: const Icon(Icons.chevron_right)),
          ],
        ),
        VurguKart(
          renk: _mor,
          child: Row(
            children: [
              YuzdeHalka(
                oran: plan?.tamamOrani ?? 0,
                ust: '%${((plan?.tamamOrani ?? 0) * 100).round()}',
                alt: 'tamam',
                renk: Colors.white,
                boyut: 92,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Haftalık Program',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('Planlanan: ${sureYaz(plan?.toplamDakika ?? 0)}'),
                    Text('Tamamlanan: ${sureYaz(plan?.tamamDakika ?? 0)}'),
                    if (plan?.adaptif == true)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Row(children: [
                          Icon(Icons.auto_awesome, size: 16),
                          SizedBox(width: 4),
                          Text('Adaptif plan'),
                        ]),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _KocKarti(
          oncekiPlan: _oncekiPlan,
          sorular: _sorular.value ?? const [],
          haftaBasi: _haftaBasi,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: _mor),
                    SizedBox(width: 8),
                    Text('Adaptif plan',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                    'Müsait sürelerine, son 2 haftanın soru verilerine ve deneme '
                    'netlerine göre zayıf derslere daha çok yer veren bir plan hazırlanır.'),
                const SizedBox(height: 10),
                _DersIhtiyaclari(
                  durum: PlanMotoru(
                    sorular: _sorular.value ?? const [],
                    denemeler: _denemeler.value ?? const [],
                  ).dersDurumlari(),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: _mor, minimumSize: const Size.fromHeight(48)),
                  onPressed: _mesgul ? null : _adaptifHazirla,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(plan == null || plan.toplamDakika == 0
                      ? 'Adaptif plan hazırla'
                      : 'Planı yeniden hazırla'),
                ),
                TextButton.icon(
                  onPressed: _musaitlikDuzenle,
                  icon: const Icon(Icons.schedule),
                  label: Text(
                      'Müsaitlik: ${sureYaz((_musait.value ?? TakipDb.varsayilanMusaitlik).fold(0, (a, b) => a + b))} / hafta — düzenle'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
                value: false, icon: Icon(Icons.view_day_outlined), label: Text('Günlük')),
            ButtonSegment(
                value: true,
                icon: Icon(Icons.calendar_view_week),
                label: Text('Haftalık Çizelge')),
          ],
          selected: {_cizelge},
          onSelectionChanged: (s) => setState(() => _cizelge = s.first),
        ),
        const SizedBox(height: 12),
        if (_cizelge) _cizelgeGorunumu(plan) else _gunlukGorunum(plan),
      ],
    );
  }

  Widget _gunlukGorunum(HaftalikPlan? plan) {
    final cs = Theme.of(context).colorScheme;
    final bloklar = plan?.gunler[_gun] ?? const <PlanBlok>[];
    final planlanan = bloklar.fold<int>(0, (a, b) => a + b.dakika);
    final tamam = bloklar.where((b) => b.tamam).fold<int>(0, (a, b) => a + b.dakika);
    final bugunIndeks = _buHafta ? DateTime.now().weekday - 1 : -1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var g = 0; g < 7; g++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() => _gun = g),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: g == _gun ? _mor : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                        border: g == bugunIndeks && g != _gun
                            ? Border.all(color: _mor, width: 2)
                            : null,
                      ),
                      child: Column(
                        children: [
                          Text(gunKisa[g],
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: g == _gun ? Colors.white : null)),
                          const SizedBox(height: 2),
                          Text(
                            '${_haftaBasi.add(Duration(days: g)).day}',
                            style: TextStyle(
                                fontSize: 12,
                                color: g == _gun ? Colors.white70 : cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (plan?.gunler[g].isEmpty ?? true)
                                  ? Colors.transparent
                                  : (plan!.gunler[g].every((b) => b.tamam)
                                      ? Colors.green
                                      : (g == _gun ? Colors.white : _mor)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: Text(gunUzun[_gun],
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            subtitle: Text(planlanan == 0
                ? 'Bugün için: boş gün 😊'
                : 'Planlanan: ${sureYaz(planlanan)}  •  Tamamlanan: ${sureYaz(tamam)}'),
            trailing: IconButton.filledTonal(
              tooltip: 'Blok ekle',
              onPressed: () => _blokDuzenle(_gun),
              icon: const Icon(Icons.add),
            ),
          ),
        ),
        if (bloklar.isEmpty)
          Card(
            color: cs.surfaceContainerLow,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Bu gün dinlenme günü olarak planlanmış.'),
            ),
          )
        else
          for (var i = 0; i < bloklar.length; i++)
            _BlokKarti(
              blok: bloklar[i],
              sira: i + 1,
              degisti: (v) => _tamamDegistir(_gun, i, v),
              duzenle: () => _blokDuzenle(_gun, i),
              sil: () => _blokSil(_gun, i),
            ),
      ],
    );
  }

  Widget _cizelgeGorunumu(HaftalikPlan? plan) {
    final cs = Theme.of(context).colorScheme;
    if (plan == null || plan.toplamDakika == 0) {
      return const EmptyState(
          icon: Icons.calendar_view_week,
          text: 'Bu hafta için plan yok.\n"Adaptif plan hazırla" ile oluştur.');
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var g = 0; g < 7; g++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    children: [
                      Text(gunKisa[g],
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(sureYaz(plan.gunDakika(g)).replaceAll(' ', ''),
                          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      for (final b in plan.gunler[g])
                        Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          height: 22 + b.dakika * 0.6,
                          width: double.infinity,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: (lgsDers(b.ders)?.renk ?? _mor)
                                .withValues(alpha: b.tamam ? 0.35 : 0.9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (b.tamam)
                                const Icon(Icons.check, size: 14, color: Colors.white),
                              FittedBox(
                                child: Text(lgsDers(b.ders)?.kisa ?? b.ders,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700)),
                              ),
                              FittedBox(
                                child: Text('${b.dakika}dk',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 10)),
                              ),
                            ],
                          ),
                        ),
                      if (plan.gunler[g].isEmpty)
                        Icon(Icons.weekend_outlined,
                            size: 18, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DersIhtiyaclari extends StatelessWidget {
  const _DersIhtiyaclari({required this.durum});

  final List<DersDurumu> durum;

  @override
  Widget build(BuildContext context) {
    final toplam = durum.fold<double>(0, (a, b) => a + b.ihtiyac);
    final sirali = List.of(durum)..sort((a, b) => b.ihtiyac.compareTo(a.ihtiyac));
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final d in sirali)
          Chip(
            visualDensity: VisualDensity.compact,
            side: BorderSide.none,
            backgroundColor: d.ders.renk.withValues(alpha: 0.12),
            avatar: Icon(d.ders.ikon, size: 16, color: d.ders.renk),
            label: Text(
              '${d.ders.kisa} %${(d.ihtiyac / toplam * 100).round()}'
              '${d.basari == null ? '' : ' • başarı %${(d.basari! * 100).round()}'}',
              style: TextStyle(
                  color: d.ders.renk, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _KocKarti extends StatelessWidget {
  const _KocKarti({
    required this.oncekiPlan,
    required this.sorular,
    required this.haftaBasi,
  });

  final Future<HaftalikPlan?>? oncekiPlan;
  final List<SoruGirisi> sorular;
  final DateTime haftaBasi;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<HaftalikPlan?>(
        future: oncekiPlan,
        builder: (context, snap) {
          final mesajlar = KocDegerlendirmesi(
            oncekiPlan: snap.data,
            sorular: sorular,
            buHafta: haftaBasi,
          ).mesajlar();
          return ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.insights, color: _mor),
            title: const Text('Haftalık Koç Değerlendirmesi',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Geçen haftanın bu haftaya yansıması'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (snap.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator()
              else if (mesajlar.isEmpty)
                const Text(
                    'Henüz karşılaştırılabilecek tamamlanmış bir hafta yok. Bu haftadan '
                    'itibaren çalışma verilerin takip edilerek sonraki planlar buna '
                    'göre değerlendirilecek.')
              else
                for (final m in mesajlar)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  ', style: TextStyle(color: _mor)),
                        Expanded(child: Text(m)),
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _BlokKarti extends StatelessWidget {
  const _BlokKarti({
    required this.blok,
    required this.sira,
    required this.degisti,
    required this.duzenle,
    required this.sil,
  });

  final PlanBlok blok;
  final int sira;
  final ValueChanged<bool> degisti;
  final VoidCallback duzenle;
  final VoidCallback sil;

  @override
  Widget build(BuildContext context) {
    final d = lgsDers(blok.ders);
    final renk = d?.renk ?? _mor;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => degisti(!blok.tamam),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: renk, width: 5)),
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
          child: Row(
            children: [
              Checkbox(
                value: blok.tamam,
                activeColor: renk,
                onChanged: (v) => degisti(v ?? false),
              ),
              Icon(d?.ikon ?? Icons.book_outlined, color: renk),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$sira. ${blok.ders}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            decoration:
                                blok.tamam ? TextDecoration.lineThrough : null)),
                    if (blok.konu.isNotEmpty)
                      Text(blok.konu, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Text(sureYaz(blok.dakika),
                  style: TextStyle(fontWeight: FontWeight.w700, color: renk)),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'd' ? duzenle() : sil(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'd', child: Text('Düzenle')),
                  PopupMenuItem(value: 's', child: Text('Sil')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlokDialog extends StatefulWidget {
  const _BlokDialog({this.blok});

  final PlanBlok? blok;

  @override
  State<_BlokDialog> createState() => _BlokDialogState();
}

class _BlokDialogState extends State<_BlokDialog> {
  late String _ders = widget.blok?.ders.isNotEmpty == true
      ? widget.blok!.ders
      : lgsDersler.first.ad;
  late final _konu = TextEditingController(text: widget.blok?.konu ?? '');
  late double _dakika = (widget.blok?.dakika ?? 40).toDouble().clamp(10, 180).toDouble();

  @override
  void dispose() {
    _konu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final oneriler = lgsKonular[_ders] ?? const <String>[];
    return AlertDialog(
      title: Text(widget.blok == null ? 'Çalışma bloğu ekle' : 'Bloğu düzenle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _ders,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Ders', border: OutlineInputBorder()),
              items: [
                for (final d in lgsDersler)
                  DropdownMenuItem(value: d.ad, child: Text(d.ad)),
              ],
              onChanged: (v) => setState(() => _ders = v ?? _ders),
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              key: ValueKey(_ders),
              initialValue: TextEditingValue(text: _konu.text),
              optionsBuilder: (v) => oneriler.where(
                  (k) => k.toLowerCase().contains(v.text.toLowerCase())),
              onSelected: (k) => _konu.text = k,
              fieldViewBuilder: (context, c, focus, onSubmit) {
                c.addListener(() => _konu.text = c.text);
                return TextField(
                  controller: c,
                  focusNode: focus,
                  decoration: const InputDecoration(
                      labelText: 'Konu (isteğe bağlı)',
                      border: OutlineInputBorder()),
                );
              },
            ),
            const SizedBox(height: 12),
            Text('Süre: ${sureYaz(_dakika.round())}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Slider(
              value: _dakika,
              min: 10,
              max: 180,
              divisions: 34,
              label: '${_dakika.round()} dk',
              onChanged: (v) => setState(() => _dakika = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            PlanBlok(
              ders: _ders,
              konu: _konu.text.trim(),
              dakika: _dakika.round(),
              tamam: widget.blok?.tamam ?? false,
            ),
          ),
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

class _MusaitlikSayfasi extends StatefulWidget {
  const _MusaitlikSayfasi({required this.ilk});

  final List<int> ilk;

  @override
  State<_MusaitlikSayfasi> createState() => _MusaitlikSayfasiState();
}

class _MusaitlikSayfasiState extends State<_MusaitlikSayfasi> {
  late final List<double> _dk =
      widget.ilk.map((e) => e.toDouble().clamp(0, 360).toDouble()).toList();

  @override
  Widget build(BuildContext context) {
    final toplam = _dk.fold<double>(0, (a, b) => a + b).round();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Haftalık müsaitlik',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text('Okul ve kurs dışında her gün ders çalışmaya ayırabileceğin süre. '
                  'Toplam: ${sureYaz(toplam)} / hafta'),
              const SizedBox(height: 8),
              for (var g = 0; g < 7; g++)
                Row(
                  children: [
                    SizedBox(
                        width: 84,
                        child: Text(gunUzun[g],
                            style: const TextStyle(fontWeight: FontWeight.w600))),
                    Expanded(
                      child: Slider(
                        value: _dk[g],
                        min: 0,
                        max: 360,
                        divisions: 24,
                        label: sureYaz(_dk[g].round()),
                        onChanged: (v) => setState(() => _dk[g] = v),
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: Text(
                        _dk[g] == 0 ? 'Dinlenme' : sureYaz(_dk[g].round()),
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () =>
                    Navigator.pop(context, _dk.map((e) => e.round()).toList()),
                child: const Text('Kaydet'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
