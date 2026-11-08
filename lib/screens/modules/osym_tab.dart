import 'package:flutter/material.dart';

import '../../models.dart';
import '../../osym.dart';
import '../../services/osym_ayristirici.dart';
import '../../services/osym_db.dart';
import '../../widgets/common.dart';
import '../../widgets/grafik.dart';
import '../osym_screen.dart';

const _mavi = Color(0xFF0D47A1);

String _n(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2).replaceAll('.', ',');
String _p(double v) => v.toStringAsFixed(3).replaceAll('.', ',');

/// ÖSYM SINAVLARIM: YKS (TYT/AYT/YDT), KPSS, AGS/ÖABT sonuçları;
/// doğru / yanlış / boş, net, puan ve konu bazında eksikler.
class OsymTab extends StatefulWidget {
  const OsymTab({super.key, required this.student, required this.me, this.varsayilanGrup});

  final Student student;
  final AppUser me;
  final String? varsayilanGrup;

  @override
  State<OsymTab> createState() => _OsymTabState();
}

class _OsymTabState extends State<OsymTab> {
  String get sid => widget.student.id;
  late final _sonuclar = LiveValue(OsymDb.sonuclar(sid));
  late String _grup = widget.varsayilanGrup ?? 'Tümü';

  @override
  void dispose() {
    _sonuclar.dispose();
    super.dispose();
  }

  Future<void> _ekle([OsymSonuc? s]) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OsymGirisEkrani(sid: sid, me: widget.me, sonuc: s)));
  }

  Future<void> _osymdenAktar(List<OsymSonuc> mevcut) async {
    final bulunan = await Navigator.of(context)
        .push<List<OsymTaslak>>(MaterialPageRoute(builder: (_) => const OsymEkrani()));
    if (bulunan == null || bulunan.isEmpty || !mounted) return;
    await openSheet<void>(context, _AktarimSheet(sid: sid, me: widget.me, taslaklar: bulunan, mevcut: mevcut));
  }

  void _ac(OsymSonuc s) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OsymDetayEkrani(sid: sid, me: widget.me, sonucId: s.id, ilk: s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _sonuclar,
        builder: (context, _) {
          if (_sonuclar.error != null) {
            return EmptyState(icon: Icons.error_outline, text: errorText(_sonuclar.error!));
          }
          if (_sonuclar.loading) return const Loading();
          return _govde(_sonuclar.value!);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_osym',
        backgroundColor: _mavi,
        foregroundColor: Colors.white,
        onPressed: () => _ekle(),
        icon: const Icon(Icons.add),
        label: const Text('Sonuç ekle'),
      ),
    );
  }

  Widget _govde(List<OsymSonuc> hepsi) {
    final liste = _grup == 'Tümü'
        ? hepsi
        : hepsi.where((s) => s.tanim?.grup == _grup).toList();
    final son = liste.isEmpty ? null : liste.first;
    // Grafik: en çok girilen sınav türü
    final sayac = <String, int>{};
    for (final s in liste) {
      sayac[s.tur] = (sayac[s.tur] ?? 0) + 1;
    }
    final anaTur = sayac.isEmpty
        ? null
        : (sayac.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    final grafikListe = liste.where((s) => s.tur == anaTur).toList().reversed.toList();

    // Konu eksikleri (toplam)
    final konu = <String, int>{};
    for (final s in liste) {
      s.konuHata.forEach((k, v) => konu['${s.tur}|$k'] = (konu['${s.tur}|$k'] ?? 0) + v);
    }
    final konuSirali = konu.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        VurguKart(
          renk: _mavi,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ÖSYM Sınavlarım',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                son == null
                    ? 'YKS, KPSS ve AGS sonuçlarını ekleyin ya da ÖSYM\'den aktarın.'
                    : 'Son: ${son.ad} • ${_n(son.toplamNet)} net'
                        '${son.puanlar.isEmpty ? '' : ' • ${son.puanlar.entries.map((e) => '${e.key} ${_p(e.value)}').join(', ')}'}',
                style: const TextStyle(fontSize: 13.5),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.white, foregroundColor: _mavi),
                      onPressed: () => _osymdenAktar(hepsi),
                      icon: const Icon(Icons.login),
                      label: const Text('ÖSYM\'den aktar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70)),
                      onPressed: () => _ekle(),
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Elle ekle'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final g in ['Tümü', ...osymGruplari])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(g),
                    selected: _grup == g,
                    onSelected: (_) => setState(() => _grup = g),
                  ),
                ),
            ],
          ),
        ),
        if (liste.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Henüz sonuç yok.\n\n• "ÖSYM\'den aktar" ile ÖSYM Aday İşlemleri Sistemi\'ne '
                'giriş yapıp sonuçlarınızı otomatik alabilirsiniz.\n• "Elle ekle" ile geçmiş '
                'sınavlarınızı ya da denemelerinizi doğru / yanlış sayılarıyla girebilirsiniz.',
              ),
            ),
          ),
        if (grafikListe.length >= 2) ...[
          SectionTitle('${osymTuru(anaTur!)?.ad ?? anaTur} net gelişimi'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: CizgiGrafik(
                degerler: grafikListe.map((s) => s.toplamNet).toList(),
                etiketler: grafikListe.map((s) => fmtShort(s.tarih)).toList(),
                renk: _mavi,
                ondalik: 1,
              ),
            ),
          ),
        ],
        if (anaTur != null && grafikListe.isNotEmpty) ...[
          const SectionTitle('Test bazında başarı (son 3)'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Column(
                children: [
                  for (final t in osymTuru(anaTur)!.testler)
                    Builder(builder: (_) {
                      final l = grafikListe.reversed
                          .where((s) => s.testler[t.id] != null)
                          .take(3)
                          .map((s) => s.testler[t.id]!)
                          .toList();
                      if (l.isEmpty) return const SizedBox.shrink();
                      final d = l.fold(0, (a, x) => a + x.d);
                      final y = l.fold(0, (a, x) => a + x.y);
                      final so = l.fold(0, (a, x) => a + x.soru);
                      final net = (d - y / 4) / l.length;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DersCubugu(
                          ikon: Icons.analytics_outlined,
                          ad: t.ad,
                          oran: so == 0 ? 0 : d / so,
                          deger: '${_n(net)} net',
                          renk: t.renk,
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
        if (konuSirali.isNotEmpty) ...[
          const SectionTitle('En çok eksik olan konular'),
          Card(
            child: Column(
              children: [
                for (final e in konuSirali.take(12))
                  Builder(builder: (_) {
                    final p = e.key.split('|');
                    final test = osymTuru(p[0])?.test(p[1]);
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.warning_amber_rounded, color: test?.renk ?? Colors.orange),
                      title: Text(p.length > 2 ? p[2] : e.key,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${osymTuru(p[0])?.ad ?? p[0]} • ${test?.ad ?? ''}'),
                      trailing: Text('${e.value} hata',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w700)),
                    );
                  }),
              ],
            ),
          ),
        ],
        if (liste.isNotEmpty) SectionTitle('Sınavlar (${liste.length})'),
        for (final s in liste) _kart(s),
      ],
    );
  }

  Widget _kart(OsymSonuc s) {
    final tanim = s.tanim;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _ac(s),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(s.ad,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(s.resmi ? 'ÖSYM' : 'Deneme', style: const TextStyle(fontSize: 12)),
                    backgroundColor: s.resmi ? _mavi.withValues(alpha: 0.12) : null,
                  ),
                ],
              ),
              Text('${fmtDate(s.tarih)} • ${s.toplamD} D / ${s.toplamY} Y / ${s.toplamB} B',
                  style: const TextStyle(fontSize: 12.5)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _rozet('${_n(s.toplamNet)} net', _mavi),
                  for (final p in s.puanlar.entries) _rozet('${p.key}: ${_p(p.value)}', Colors.teal),
                ],
              ),
              const SizedBox(height: 8),
              for (final t in tanim?.testler ?? const <OsymTest>[])
                if (s.testler[t.id] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(t.ad,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5))),
                        Text(
                            '${s.testler[t.id]!.d}D ${s.testler[t.id]!.y}Y ${s.testler[t.id]!.b}B  '
                            '${_n(s.testler[t.id]!.net(s.bolen))} net',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700, color: t.renk)),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _rozet(String m, Color r) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: r.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(m, style: TextStyle(color: r, fontWeight: FontWeight.w800, fontSize: 12.5)),
    );

// ---------------------------------------------------------------------------
// ÖSYM'den aktarılanların önizlemesi
// ---------------------------------------------------------------------------
class _AktarimSheet extends StatefulWidget {
  const _AktarimSheet(
      {required this.sid, required this.me, required this.taslaklar, required this.mevcut});
  final String sid;
  final AppUser me;
  final List<OsymTaslak> taslaklar;
  final List<OsymSonuc> mevcut;

  @override
  State<_AktarimSheet> createState() => _AktarimSheetState();
}

class _AktarimSheetState extends State<_AktarimSheet> {
  late final _secili = List<bool>.filled(widget.taslaklar.length, true);
  bool _mesgul = false;

  OsymSonuc? _eslesen(OsymTaslak t) {
    for (final m in widget.mevcut) {
      if (m.tur == t.tur && m.resmi && m.tarih.year == t.yil) return m;
    }
    return null;
  }

  Future<void> _kaydet() async {
    setState(() => _mesgul = true);
    final nav = Navigator.of(context);
    final ok = await runSafe(context, () async {
      for (var i = 0; i < widget.taslaklar.length; i++) {
        if (!_secili[i]) continue;
        final t = widget.taslaklar[i];
        final e = _eslesen(t);
        await OsymDb.kaydet(
          widget.sid,
          widget.me,
          id: e?.id,
          tur: t.tur,
          ad: e?.ad ?? t.ad,
          tarih: e?.tarih ?? DateTime(t.yil ?? DateTime.now().year, 7, 1),
          resmi: true,
          kaynak: 'osym',
          testler: {...?e?.testler, ...t.testler},
          puanlar: {...?e?.puanlar, ...t.puanlar},
          konuHata: e?.konuHata,
        );
      }
    }, success: 'Sonuçlar kaydedildi.');
    if (ok) {
      nav.pop();
    } else if (mounted) {
      setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: 'ÖSYM\'den bulunanlar',
      children: [
        for (var i = 0; i < widget.taslaklar.length; i++)
          Builder(builder: (_) {
            final t = widget.taslaklar[i];
            final e = _eslesen(t);
            return CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _secili[i],
              onChanged: (v) => setState(() => _secili[i] = v ?? false),
              title: Text(t.ad, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                for (final x in t.testler.entries)
                  '${t.tanim.test(x.key)?.ad ?? x.key}: ${x.value.d}D ${x.value.y}Y ${x.value.b}B',
                for (final p in t.puanlar.entries) '${p.key} puanı: ${_p(p.value)}',
                if (e != null) '↻ Mevcut kayıt güncellenecek',
              ].join('\n')),
              isThreeLine: true,
            );
          }),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: _mavi, minimumSize: const Size.fromHeight(48)),
          onPressed: _mesgul || !_secili.contains(true) ? null : _kaydet,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Elle giriş / düzenleme
// ---------------------------------------------------------------------------
class OsymGirisEkrani extends StatefulWidget {
  const OsymGirisEkrani({super.key, required this.sid, required this.me, this.sonuc});
  final String sid;
  final AppUser me;
  final OsymSonuc? sonuc;

  @override
  State<OsymGirisEkrani> createState() => _OsymGirisEkraniState();
}

class _OsymGirisEkraniState extends State<OsymGirisEkrani> {
  late String _tur = widget.sonuc?.tur ?? 'TYT';
  late bool _resmi = widget.sonuc?.resmi ?? true;
  late DateTime _tarih = widget.sonuc?.tarih ?? today();
  late final _ad = TextEditingController(text: widget.sonuc?.ad ?? '');
  final _alanlar = <String, List<TextEditingController>>{}; // test -> [soru, d, y]
  final _puan = <String, TextEditingController>{};
  bool _mesgul = false;

  OsymSinavTuru get _tanim => osymTuru(_tur)!;

  @override
  void initState() {
    super.initState();
    _hazirla();
  }

  void _hazirla() {
    final s = widget.sonuc;
    for (final t in _tanim.testler) {
      _alanlar.putIfAbsent(t.id + _tur, () {
        final x = s != null && s.tur == _tur ? s.testler[t.id] : null;
        return [
          TextEditingController(text: '${x?.soru ?? t.soru}'),
          TextEditingController(text: x == null ? '' : '${x.d}'),
          TextEditingController(text: x == null ? '' : '${x.y}'),
        ];
      });
    }
    for (final p in _tanim.puanlar) {
      _puan.putIfAbsent(p + _tur, () {
        final v = s != null && s.tur == _tur ? s.puanlar[p] : null;
        return TextEditingController(text: v == null ? '' : _p(v));
      });
    }
  }

  @override
  void dispose() {
    for (final l in _alanlar.values) {
      for (final c in l) {
        c.dispose();
      }
    }
    for (final c in _puan.values) {
      c.dispose();
    }
    _ad.dispose();
    super.dispose();
  }

  int _sayi(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  Future<void> _kaydet() async {
    final testler = <String, TestSonucu>{};
    for (final t in _tanim.testler) {
      final l = _alanlar[t.id + _tur]!;
      final s = _sayi(l[0]), d = _sayi(l[1]), y = _sayi(l[2]);
      if (l[1].text.trim().isEmpty && l[2].text.trim().isEmpty) continue;
      if (d + y > s) {
        showInfo(context, '${t.ad}: doğru + yanlış, soru sayısından fazla olamaz.');
        return;
      }
      testler[t.id] = TestSonucu(soru: s, d: d, y: y);
    }
    if (testler.isEmpty) {
      showInfo(context, 'En az bir testin doğru / yanlış sayısını girin.');
      return;
    }
    final puanlar = <String, double>{};
    for (final p in _tanim.puanlar) {
      final v = double.tryParse(_puan[p + _tur]!.text.trim().replaceAll(',', '.'));
      if (v != null && v > 0) puanlar[p] = v;
    }
    final ad = _ad.text.trim().isEmpty
        ? '${_tarih.year} ${_tanim.ad}${_resmi ? '' : ' Denemesi'}'
        : _ad.text.trim();
    setState(() => _mesgul = true);
    final nav = Navigator.of(context);
    final ok = await runSafe(
      context,
      () => OsymDb.kaydet(widget.sid, widget.me,
          id: widget.sonuc?.id,
          tur: _tur,
          ad: ad,
          tarih: _tarih,
          resmi: _resmi,
          kaynak: widget.sonuc?.kaynak ?? 'elle',
          testler: testler,
          puanlar: puanlar,
          konuHata: widget.sonuc?.tur == _tur ? widget.sonuc?.konuHata : null),
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
    final tanim = _tanim;
    var toplamNet = 0.0;
    for (final t in tanim.testler) {
      final l = _alanlar[t.id + _tur]!;
      toplamNet += _sayi(l[1]) - _sayi(l[2]) / tanim.yanlisBolen;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sonuc == null ? 'Sınav sonucu ekle' : 'Sonucu düzenle'),
        backgroundColor: _mavi,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 32 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          DropdownButtonFormField<String>(
            value: _tur,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Sınav', border: OutlineInputBorder()),
            items: [
              for (final s in osymSinavlari)
                DropdownMenuItem(value: s.id, child: Text('${s.ad} — ${s.aciklama}')),
            ],
            onChanged: widget.sonuc != null
                ? null
                : (v) => setState(() {
                      _tur = v ?? _tur;
                      _hazirla();
                    }),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('ÖSYM sınavı'), icon: Icon(Icons.verified)),
              ButtonSegment(value: false, label: Text('Deneme'), icon: Icon(Icons.quiz_outlined)),
            ],
            selected: {_resmi},
            onSelectionChanged: (v) => setState(() => _resmi = v.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ad,
            decoration: InputDecoration(
              labelText: 'Ad (isteğe bağlı)',
              hintText: '${_tarih.year} ${tanim.ad}${_resmi ? '' : ' Denemesi'}',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text('Tarih: ${fmtDate(_tarih)}'),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _tarih,
                firstDate: DateTime(2010),
                lastDate: today().add(const Duration(days: 365)),
              );
              if (d != null) setState(() => _tarih = d);
            },
          ),
          const SizedBox(height: 4),
          Text('Testler (${tanim.yanlisBolen} yanlış 1 doğruyu götürür)',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final t in tanim.testler)
            Builder(builder: (_) {
              final l = _alanlar[t.id + _tur]!;
              final s = _sayi(l[0]), d = _sayi(l[1]), y = _sayi(l[2]);
              final net = d - y / tanim.yanlisBolen;
              Widget alan(TextEditingController c, String etiket) => Expanded(
                    child: TextField(
                      controller: c,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: etiket,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  );
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.ad,
                          style: TextStyle(fontWeight: FontWeight.w800, color: t.renk)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          alan(l[0], 'Soru'),
                          const SizedBox(width: 6),
                          alan(l[1], 'Doğru'),
                          const SizedBox(width: 6),
                          alan(l[2], 'Yanlış'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Boş: ${(s - d - y).clamp(0, 999)}  •  Net: ${_n(net)}',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: d + y > s ? Theme.of(context).colorScheme.error : null),
                      ),
                    ],
                  ),
                ),
              );
            }),
          Text('Toplam net: ${_n(toplamNet)}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 16),
          const Text('Puanlar (isteğe bağlı)', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in tanim.puanlar)
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _puan[p + _tur],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: '$p puanı', isDense: true, border: const OutlineInputBorder()),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: _mavi, minimumSize: const Size.fromHeight(50)),
            onPressed: _mesgul ? null : _kaydet,
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detay ve konu eksikleri
// ---------------------------------------------------------------------------
class OsymDetayEkrani extends StatefulWidget {
  const OsymDetayEkrani(
      {super.key, required this.sid, required this.me, required this.sonucId, required this.ilk});
  final String sid;
  final AppUser me;
  final String sonucId;
  final OsymSonuc ilk;

  @override
  State<OsymDetayEkrani> createState() => _OsymDetayEkraniState();
}

class _OsymDetayEkraniState extends State<OsymDetayEkrani> {
  late final _liste = LiveValue(OsymDb.sonuclar(widget.sid));

  @override
  void dispose() {
    _liste.dispose();
    super.dispose();
  }

  Future<void> _konular(OsymSonuc s, OsymTest t) async {
    await openSheet<void>(context, _KonuSheet(sid: widget.sid, sonuc: s, test: t));
  }

  Future<void> _sil(OsymSonuc s) async {
    final ok = await confirm(context,
        title: 'Silinsin mi?', message: s.ad, ok: 'Sil', destructive: true);
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    final done = await runSafe(context, () => OsymDb.sil(widget.sid, s.id));
    if (done) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _liste,
      builder: (context, _) {
        OsymSonuc s = widget.ilk;
        for (final x in _liste.value ?? const <OsymSonuc>[]) {
          if (x.id == widget.sonucId) s = x;
        }
        final tanim = s.tanim;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: _mavi,
            foregroundColor: Colors.white,
            title: Text(s.ad),
            actions: [
              IconButton(
                  tooltip: 'Düzenle',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => OsymGirisEkrani(sid: widget.sid, me: widget.me, sonuc: s))),
                  icon: const Icon(Icons.edit_outlined)),
              IconButton(
                  tooltip: 'Sil', onPressed: () => _sil(s), icon: const Icon(Icons.delete_outline)),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              VurguKart(
                renk: _mavi,
                child: Row(
                  children: [
                    YuzdeHalka(
                      oran: s.toplamSoru == 0 ? 0 : (s.toplamNet / s.toplamSoru).clamp(0, 1).toDouble(),
                      ust: _n(s.toplamNet),
                      alt: 'net',
                      renk: Colors.white,
                      boyut: 96,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${tanim?.ad ?? s.tur} • ${s.resmi ? 'ÖSYM' : 'Deneme'}',
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(fmtDate(s.tarih)),
                          const SizedBox(height: 6),
                          Text('${s.toplamD} doğru • ${s.toplamY} yanlış • ${s.toplamB} boş'),
                          for (final p in s.puanlar.entries)
                            Text('${p.key} puanı: ${_p(p.value)}',
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              for (final t in tanim?.testler ?? const <OsymTest>[])
                if (s.testler[t.id] != null)
                  Builder(builder: (_) {
                    final x = s.testler[t.id]!;
                    final eksik = s.konuHata.entries
                        .where((e) => e.key.startsWith('${t.id}|') && e.value > 0)
                        .toList()
                      ..sort((a, b) => b.value.compareTo(a.value));
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DersCubugu(
                              ikon: Icons.analytics_outlined,
                              ad: t.ad,
                              oran: x.basari,
                              deger: '${_n(x.net(s.bolen))} net',
                              renk: t.renk,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children: [
                                _rozet('${x.d} doğru', Colors.green),
                                _rozet('${x.y} yanlış', Colors.red),
                                _rozet('${x.b} boş', Colors.grey),
                                _rozet('${x.soru} soru', Colors.blueGrey),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (eksik.isEmpty)
                              Text(
                                x.y + x.b == 0
                                    ? 'Bu testte eksik yok 👏'
                                    : '${x.y + x.b} soruyu hangi konularda kaçırdığınızı işaretleyin.',
                                style: const TextStyle(fontSize: 12.5),
                              )
                            else
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final e in eksik)
                                    Chip(
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: Colors.red.withValues(alpha: 0.08),
                                      side: BorderSide.none,
                                      label: Text('${e.key.split('|').last} • ${e.value}',
                                          style: const TextStyle(fontSize: 12)),
                                    ),
                                ],
                              ),
                            if (x.y + x.b > 0)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () => _konular(s, t),
                                  icon: const Icon(Icons.checklist),
                                  label: Text(eksik.isEmpty ? 'Konu eksiklerini işaretle' : 'Düzenle'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
            ],
          ),
        );
      },
    );
  }
}

class _KonuSheet extends StatefulWidget {
  const _KonuSheet({required this.sid, required this.sonuc, required this.test});
  final String sid;
  final OsymSonuc sonuc;
  final OsymTest test;

  @override
  State<_KonuSheet> createState() => _KonuSheetState();
}

class _KonuSheetState extends State<_KonuSheet> {
  late final Map<String, int> _sayi = {
    for (final k in widget.test.konular) k: widget.sonuc.konuHata['${widget.test.id}|$k'] ?? 0,
  };

  int get _toplam => _sayi.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final x = widget.sonuc.testler[widget.test.id];
    final hedef = x == null ? 0 : x.y + x.b;
    return SheetFrame(
      title: '${widget.test.ad} • konu eksikleri',
      children: [
        Text('Yanlış ve boş: $hedef soru • işaretlenen: $_toplam',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _toplam > hedef ? Theme.of(context).colorScheme.error : null)),
        const SizedBox(height: 8),
        for (final k in widget.test.konular)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(k),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                    onPressed: _sayi[k]! == 0 ? null : () => setState(() => _sayi[k] = _sayi[k]! - 1),
                    icon: const Icon(Icons.remove_circle_outline)),
                SizedBox(
                    width: 26,
                    child: Text('${_sayi[k]}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                IconButton(
                    onPressed: () => setState(() => _sayi[k] = _sayi[k]! + 1),
                    icon: const Icon(Icons.add_circle_outline)),
              ],
            ),
          ),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _mavi, minimumSize: const Size.fromHeight(48)),
          onPressed: () async {
            final nav = Navigator.of(context);
            final yeni = Map<String, int>.from(widget.sonuc.konuHata)
              ..removeWhere((k, _) => k.startsWith('${widget.test.id}|'));
            _sayi.forEach((k, v) {
              if (v > 0) yeni['${widget.test.id}|$k'] = v;
            });
            final ok = await runSafe(
                context, () => OsymDb.konuHataKaydet(widget.sid, widget.sonuc.id, yeni),
                success: 'Kaydedildi.');
            if (ok) nav.pop();
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
