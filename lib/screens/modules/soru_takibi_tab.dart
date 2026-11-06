import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../lgs.dart';
import '../../models.dart';
import '../../services/takip_db.dart';
import '../../widgets/common.dart';
import '../../widgets/dyb_giris.dart';
import '../../widgets/grafik.dart';

/// GÜNLÜK SORU TAKİBİ
/// Ders ders (karma) ya da konu bazlı çözülen soru sayıları girilir;
/// günlük seri, haftalık grafik, ders başarıları ve zayıf konular gösterilir.
class SoruTakibiTab extends StatefulWidget {
  const SoruTakibiTab({super.key, required this.student, required this.me});

  final Student student;
  final AppUser me;

  @override
  State<SoruTakibiTab> createState() => _SoruTakibiTabState();
}

class _SoruTakibiTabState extends State<SoruTakibiTab> {
  late final LiveValue<List<SoruGirisi>> _girisler =
      LiveValue(TakipDb.sorular(widget.student.id));
  bool _tumGecmis = false;

  @override
  void dispose() {
    _girisler.dispose();
    super.dispose();
  }

  void _ac(Widget ekran) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ekran));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _girisler,
        builder: (context, _) {
          if (_girisler.error != null) {
            return EmptyState(
                icon: Icons.error_outline, text: errorText(_girisler.error!));
          }
          if (_girisler.loading) return const Loading();
          final liste = _girisler.value!;
          return _govde(context, liste);
        },
      ),
    );
  }

  Widget _govde(BuildContext context, List<SoruGirisi> liste) {
    final cs = Theme.of(context).colorScheme;
    final bugun = today();
    final hafta7 = bugun.subtract(const Duration(days: 6));

    Dyb gunToplam(DateTime g) => liste
        .where((e) => DateUtils.isSameDay(e.tarih, g))
        .fold(Dyb.bos, (a, e) => a + e.toplam);

    final bugunku = gunToplam(bugun);
    final son7 = liste.where((e) => !e.tarih.isBefore(hafta7)).toList();
    final hafta = son7.fold(Dyb.bos, (a, e) => a + e.toplam);

    // Günlük seri: bugünden (ya da dünden) geriye kesintisiz giriş yapılan gün sayısı.
    final gunler = liste.map((e) => DateUtils.dateOnly(e.tarih)).toSet();
    var seri = 0;
    var g = gunler.contains(bugun) ? bugun : bugun.subtract(const Duration(days: 1));
    while (gunler.contains(g)) {
      seri++;
      g = g.subtract(const Duration(days: 1));
    }

    final gunSoru = List.generate(7, (i) {
      final gun = hafta7.add(Duration(days: i));
      return gunToplam(gun).toplam.toDouble();
    });
    final gunEtiket =
        List.generate(7, (i) => gunKisa[hafta7.add(Duration(days: i)).weekday - 1]);

    // Derslere göre son 7 gün
    final dersHafta = <String, Dyb>{};
    for (final e in son7) {
      e.dersBazli.forEach((k, v) => dersHafta[k] = (dersHafta[k] ?? Dyb.bos) + v);
    }
    final enCokSoru = dersHafta.values
        .fold<int>(0, (a, b) => b.toplam > a ? b.toplam : a);

    // Zayıf konular: son 30 gün, en az 5 soru
    final ay = bugun.subtract(const Duration(days: 30));
    final konular = <String, Dyb>{};
    for (final e in liste.where((e) => !e.karma && !e.tarih.isBefore(ay))) {
      final k = '${e.ders}|${e.konu}';
      konular[k] = (konular[k] ?? Dyb.bos) + e.sonuc;
    }
    final zayif = konular.entries.where((e) => e.value.toplam >= 5).toList()
      ..sort((a, b) => a.value.basari.compareTo(b.value.basari));

    final gecmis = _tumGecmis ? liste : liste.take(15).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        VurguKart(
          renk: const Color(0xFF5C6BC0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.today),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Bugün (${fmtShort(bugun)})',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  if (seri > 0)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('🔥 $seri gün seri',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              DybOzet(
                  d: bugunku.d, y: bugunku.y, b: bugunku.b, net: bugunku.net),
              const SizedBox(height: 12),
              Text(
                'Son 7 gün: ${hafta.toplam} soru  •  başarı %${(hafta.basari * 100).round()}  •  ${hafta.net.toStringAsFixed(1)} net',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => _ac(KarmaGirisEkrani(
                    student: widget.student, me: widget.me)),
                icon: const Icon(Icons.grid_view_rounded),
                label: const Text('Karma Giriş'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => _ac(KonuGirisEkrani(
                    student: widget.student, me: widget.me)),
                icon: const Icon(Icons.track_changes),
                label: const Text('Konu Bazlı'),
              ),
            ),
          ],
        ),
        const SectionTitle('Son 7 gün çözülen soru'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            child: MiniBars(values: gunSoru, labels: gunEtiket, height: 110),
          ),
        ),
        const SectionTitle('Derslere göre (son 7 gün)'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: dersHafta.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Bu hafta henüz soru girişi yok.'),
                  )
                : Column(
                    children: [
                      for (final d in lgsDersler)
                        if ((dersHafta[d.ad]?.toplam ?? 0) > 0)
                          DersCubugu(
                            ikon: d.ikon,
                            ad: d.ad,
                            renk: d.renk,
                            oran: dersHafta[d.ad]!.toplam / enCokSoru,
                            deger: '${dersHafta[d.ad]!.toplam} soru',
                            alt:
                                'Başarı %${(dersHafta[d.ad]!.basari * 100).round()}  •  ${dersHafta[d.ad]!.net.toStringAsFixed(1)} net',
                          ),
                    ],
                  ),
          ),
        ),
        if (zayif.isNotEmpty) ...[
          const SectionTitle('Tekrar edilmesi gereken konular'),
          Card(
            child: Column(
              children: [
                for (final e in zayif.take(5))
                  ListTile(
                    leading: Icon(lgsDers(e.key.split('|').first)?.ikon ??
                        Icons.topic_outlined,
                        color: lgsDers(e.key.split('|').first)?.renk),
                    title: Text(e.key.split('|').last),
                    subtitle: Text(
                        '${e.key.split('|').first}  •  ${e.value.toplam} soru'),
                    trailing: Text('%${(e.value.basari * 100).round()}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: e.value.basari < 0.6
                                ? cs.error
                                : Colors.orange.shade800)),
                  ),
              ],
            ),
          ),
        ],
        SectionTitle('Giriş geçmişi (${liste.length})'),
        if (liste.isEmpty)
          const EmptyState(
            icon: Icons.edit_note,
            text: 'Henüz giriş yok.\nGün sonunda "Karma Giriş" ile derslerde '
                'çözdüğün soruları yaz.',
          )
        else ...[
          for (final e in gecmis)
            _GirisKarti(student: widget.student, me: widget.me, giris: e),
          if (liste.length > gecmis.length)
            TextButton(
              onPressed: () => setState(() => _tumGecmis = true),
              child: Text('Tümünü göster (${liste.length})'),
            ),
        ],
      ],
    );
  }
}

class _GirisKarti extends StatelessWidget {
  const _GirisKarti(
      {required this.student, required this.me, required this.giris});

  final Student student;
  final AppUser me;
  final SoruGirisi giris;

  @override
  Widget build(BuildContext context) {
    final t = giris.toplam;
    final yetki = me.role.isAdult || giris.createdBy == me.uid;
    final d = giris.karma ? null : lgsDers(giris.ders);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor:
                  (d?.renk ?? Theme.of(context).colorScheme.primary).withValues(alpha: 0.14),
              child: Icon(
                  giris.karma ? Icons.grid_view_rounded : (d?.ikon ?? Icons.topic),
                  color: d?.renk ?? Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    giris.karma
                        ? 'Karma giriş • ${fmtDate(giris.tarih)}'
                        : '${giris.konu} • ${fmtShort(giris.tarih)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    giris.karma
                        ? giris.dersler.entries
                            .where((e) => e.value.toplam > 0)
                            .map((e) =>
                                '${lgsDers(e.key)?.kisa ?? e.key} ${e.value.toplam}')
                            .join('  •  ')
                        : giris.ders,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${t.toplam} soru  •  D ${t.d}  Y ${t.y}  B ${t.b}  •  ${t.net.toStringAsFixed(2)} net'
                    '${giris.sure > 0 ? '  •  ${sureYaz(giris.sure)}' : ''}',
                  ),
                  if (giris.not.isNotEmpty)
                    Text(giris.not,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontStyle: FontStyle.italic)),
                ],
              ),
            ),
            if (yetki)
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'duzenle') {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => giris.karma
                          ? KarmaGirisEkrani(student: student, me: me, giris: giris)
                          : KonuGirisEkrani(student: student, me: me, giris: giris),
                    ));
                  } else if (v == 'sil') {
                    final ok = await confirm(context,
                        title: 'Giriş silinsin mi?',
                        message: '${fmtDate(giris.tarih)} • ${t.toplam} soru',
                        ok: 'Sil',
                        destructive: true);
                    if (!ok || !context.mounted) return;
                    await runSafe(context,
                        () => TakipDb.sil(student.id, 'soruGirisleri', giris.id));
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'duzenle', child: Text('Düzenle')),
                  PopupMenuItem(value: 'sil', child: Text('Sil')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tarih seçici düğmesi
// ---------------------------------------------------------------------------
class TarihDugmesi extends StatelessWidget {
  const TarihDugmesi({super.key, required this.tarih, required this.degisti, this.etiket = 'Tarih'});

  final DateTime tarih;
  final ValueChanged<DateTime> degisti;
  final String etiket;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      onPressed: () async {
        final s = await showDatePicker(
          context: context,
          initialDate: tarih,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
        );
        if (s != null) degisti(s);
      },
      icon: const Icon(Icons.calendar_month_outlined),
      label: Text('$etiket: ${fmtDate(tarih)}'),
    );
  }
}

class _SureNotAlanlari extends StatelessWidget {
  const _SureNotAlanlari({required this.sure, required this.not});

  final TextEditingController sure;
  final TextEditingController not;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: TextField(
            controller: sure,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
                labelText: 'Süre (dk)',
                prefixIcon: Icon(Icons.timer_outlined),
                isDense: true,
                border: OutlineInputBorder()),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: not,
            decoration: const InputDecoration(
                labelText: 'Not (isteğe bağlı)',
                isDense: true,
                border: OutlineInputBorder()),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Karma giriş
// ---------------------------------------------------------------------------
class KarmaGirisEkrani extends StatefulWidget {
  const KarmaGirisEkrani(
      {super.key, required this.student, required this.me, this.giris});

  final Student student;
  final AppUser me;
  final SoruGirisi? giris;

  @override
  State<KarmaGirisEkrani> createState() => _KarmaGirisEkraniState();
}

class _KarmaGirisEkraniState extends State<KarmaGirisEkrani> {
  late DateTime _tarih = widget.giris?.tarih ?? today();
  late final Map<String, DybDenetleyici> _d = {
    for (final d in lgsDersler)
      d.ad: DybDenetleyici(widget.giris?.dersler[d.ad] ?? Dyb.bos),
  };
  late final _sure = TextEditingController(
      text: (widget.giris?.sure ?? 0) > 0 ? '${widget.giris!.sure}' : '');
  late final _not = TextEditingController(text: widget.giris?.not ?? '');
  bool _mesgul = false;

  @override
  void dispose() {
    for (final c in _d.values) {
      c.dispose();
    }
    _sure.dispose();
    _not.dispose();
    super.dispose();
  }

  Dyb get _toplam => _d.values.fold(Dyb.bos, (a, c) => a + c.deger);

  Future<void> _kaydet() async {
    if (_toplam.toplam == 0) {
      showInfo(context, 'En az bir derse soru sayısı girin.');
      return;
    }
    setState(() => _mesgul = true);
    final nav = Navigator.of(context);
    final ok = await runSafe(
      context,
      () => TakipDb.soruKaydet(
        widget.student.id,
        widget.me,
        id: widget.giris?.id,
        tur: 'karma',
        tarih: _tarih,
        dersler: {for (final e in _d.entries) e.key: e.value.deger},
        sure: int.tryParse(_sure.text) ?? 0,
        not: _not.text.trim(),
      ),
      success: 'Kaydedildi: ${_toplam.toplam} soru, ${_toplam.net.toStringAsFixed(2)} net',
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
          title: Text(widget.giris == null ? 'Karma Veri Girişi' : 'Girişi Düzenle')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 120),
        children: [
          TarihDugmesi(tarih: _tarih, degisti: (t) => setState(() => _tarih = t)),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: Listenable.merge(_d.values.toList()),
            builder: (context, _) {
              final t = _toplam;
              return VurguKart(
                renk: const Color(0xFF5C6BC0),
                child: DybOzet(d: t.d, y: t.y, b: t.b, net: t.net),
              );
            },
          ),
          for (final d in lgsDersler) DersDybKart(ders: d, denetleyici: _d[d.ad]!),
          const SizedBox(height: 6),
          _SureNotAlanlari(sure: _sure, not: _not),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _mesgul ? null : _kaydet,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Kaydet'),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Konu bazlı giriş
// ---------------------------------------------------------------------------
class KonuGirisEkrani extends StatefulWidget {
  const KonuGirisEkrani(
      {super.key, required this.student, required this.me, this.giris});

  final Student student;
  final AppUser me;
  final SoruGirisi? giris;

  @override
  State<KonuGirisEkrani> createState() => _KonuGirisEkraniState();
}

class _KonuGirisEkraniState extends State<KonuGirisEkrani> {
  static const _diger = 'Diğer (kendim yazacağım)';

  late DateTime _tarih = widget.giris?.tarih ?? today();
  late String? _ders = widget.giris?.ders.isNotEmpty == true ? widget.giris!.ders : null;
  String? _konu;
  final _ozelKonu = TextEditingController();
  late final _dyb = DybDenetleyici(widget.giris?.sonuc ?? Dyb.bos);
  late final _sure = TextEditingController(
      text: (widget.giris?.sure ?? 0) > 0 ? '${widget.giris!.sure}' : '');
  late final _not = TextEditingController(text: widget.giris?.not ?? '');
  bool _mesgul = false;

  @override
  void initState() {
    super.initState();
    final g = widget.giris;
    if (g != null && g.konu.isNotEmpty) {
      if ((lgsKonular[g.ders] ?? const []).contains(g.konu)) {
        _konu = g.konu;
      } else {
        _konu = _diger;
        _ozelKonu.text = g.konu;
      }
    }
  }

  @override
  void dispose() {
    _ozelKonu.dispose();
    _dyb.dispose();
    _sure.dispose();
    _not.dispose();
    super.dispose();
  }

  String get _konuAdi => _konu == _diger ? _ozelKonu.text.trim() : (_konu ?? '');

  Future<void> _kaydet() async {
    if (_ders == null) {
      showInfo(context, 'Önce ders seçin.');
      return;
    }
    if (_konuAdi.isEmpty) {
      showInfo(context, 'Konuyu seçin ya da yazın.');
      return;
    }
    if (_dyb.deger.toplam == 0) {
      showInfo(context, 'Doğru, yanlış ya da boş sayısı girin.');
      return;
    }
    setState(() => _mesgul = true);
    final nav = Navigator.of(context);
    final ok = await runSafe(
      context,
      () => TakipDb.soruKaydet(
        widget.student.id,
        widget.me,
        id: widget.giris?.id,
        tur: 'konu',
        tarih: _tarih,
        ders: _ders!,
        konu: _konuAdi,
        sonuc: _dyb.deger,
        sure: int.tryParse(_sure.text) ?? 0,
        not: _not.text.trim(),
      ),
      success: 'Kaydedildi: $_konuAdi',
    );
    if (ok) {
      nav.pop();
    } else if (mounted) {
      setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final konular = _ders == null ? const <String>[] : (lgsKonular[_ders] ?? const []);
    return Scaffold(
      appBar: AppBar(
          title: Text(
              widget.giris == null ? 'Konu Bazlı Veri Girişi' : 'Girişi Düzenle')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 120),
        children: [
          Card(
            color: cs.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Belirli bir konu üzerinde çözdüğün soruları buraya gir. '
                'Aynı soruları Karma Girişe ayrıca ekleme.',
              ),
            ),
          ),
          const SizedBox(height: 10),
          TarihDugmesi(tarih: _tarih, degisti: (t) => setState(() => _tarih = t)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _ders,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Ders', border: OutlineInputBorder()),
            items: [
              for (final d in lgsDersler)
                DropdownMenuItem(
                  value: d.ad,
                  child: Row(children: [
                    Icon(d.ikon, color: d.renk, size: 20),
                    const SizedBox(width: 10),
                    Text(d.ad),
                  ]),
                ),
            ],
            onChanged: (v) => setState(() {
              _ders = v;
              _konu = null;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(_ders),
            value: _konu,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Kazanım / Konu', border: OutlineInputBorder()),
            hint: Text(_ders == null ? 'Önce ders seç' : 'Konu seç'),
            items: [
              for (final k in [...konular, _diger])
                DropdownMenuItem(value: k, child: Text(k)),
            ],
            onChanged: _ders == null ? null : (v) => setState(() => _konu = v),
          ),
          if (_konu == _diger) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _ozelKonu,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Konu adı', border: OutlineInputBorder()),
            ),
          ],
          const SizedBox(height: 16),
          DybAlanlari(denetleyici: _dyb),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: _dyb,
            builder: (context, _) {
              final v = _dyb.deger;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700),
                    const SizedBox(width: 10),
                    Text(
                      'Doğru: ${v.d}   Net: ${v.net.toStringAsFixed(2)}   (%${(v.basari * 100).toStringAsFixed(0)})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          _SureNotAlanlari(sure: _sure, not: _not),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _mesgul ? null : _kaydet,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Kaydet'),
          ),
        ),
      ),
    );
  }
}
