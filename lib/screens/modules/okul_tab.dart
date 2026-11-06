import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../lgs.dart';
import '../../models.dart';
import '../../services/ekran_okuyucu.dart';
import '../../services/okul_db.dart';
import '../eokul_screen.dart';
import '../../widgets/common.dart';
import '../../widgets/grafik.dart';

const _lacivert = Color(0xFF283593);

/// Ders adı için ikon ve renk (LGS dersleri kendi renginde).
(IconData, Color) _dersGorunum(String ders) {
  final l = lgsDers(ders);
  if (l != null) return (l.ikon, l.renk);
  final k = ders.toLowerCase();
  if (k.contains('müzik')) return (Icons.music_note_outlined, Colors.pink);
  if (k.contains('beden')) return (Icons.sports_basketball_outlined, Colors.deepOrange);
  if (k.contains('görsel')) return (Icons.palette_outlined, Colors.purple);
  if (k.contains('teknoloji') || k.contains('bilişim')) {
    return (Icons.memory_outlined, Colors.blueGrey);
  }
  return (Icons.school_outlined, _lacivert);
}

const _okulDersleri = [
  'Türkçe',
  'Matematik',
  'Fen Bilimleri',
  'T.C. İnkılap Tarihi',
  'İngilizce',
  'Din Kültürü',
  'Beden Eğitimi ve Spor',
  'Teknoloji ve Tasarım',
  'Müzik',
  'Görsel Sanatlar',
  'Bilişim Teknolojileri',
  'Seçmeli Din',
  'Matematik Uygulamaları',
];

/// OKUL NOTLARI (e-Okul)
class OkulTab extends StatefulWidget {
  const OkulTab({super.key, required this.student, required this.me});

  final Student student;
  final AppUser me;

  @override
  State<OkulTab> createState() => _OkulTabState();
}

class _OkulTabState extends State<OkulTab> {
  String get sid => widget.student.id;
  late final LiveValue<List<OkulSinav>> _sinavlar = LiveValue(OkulDb.sinavlar(sid));
  late final LiveValue<List<YilSonu>> _yilSonlari = LiveValue(OkulDb.yilSonlari(sid));
  late int _donem = donemOf(DateTime.now());
  bool _okunuyor = false;

  @override
  void dispose() {
    _sinavlar.dispose();
    _yilSonlari.dispose();
    super.dispose();
  }

  bool _yetki(OkulSinav s) => widget.me.role.isAdult || s.createdBy == widget.me.uid;

  Future<void> _sinavDuzenle([OkulSinav? s, bool notGir = false]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _SinavDialog(
        student: widget.student,
        me: widget.me,
        sinav: s,
        donem: _donem,
        notOdakli: notGir,
        mevcut: _sinavlar.value ?? const [],
      ),
    );
  }

  Future<void> _yilSonuEkle([YilSonu? y]) async {
    final yil = TextEditingController(text: y?.yil ?? '');
    final sinif = TextEditingController(text: y?.sinif ?? '');
    final not = TextEditingController(
        text: y == null ? '' : y.not.toString().replaceAll('.', ','));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yıl sonu notu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: yil,
                decoration: const InputDecoration(
                    labelText: 'Eğitim yılı (ör. 2025-2026)',
                    border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
                controller: sinif,
                decoration: const InputDecoration(
                    labelText: 'Sınıf (ör. 7. Sınıf)', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
                controller: not,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Yıl sonu notu', border: OutlineInputBorder())),
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
    final y2 = yil.text.trim(), s2 = sinif.text.trim();
    final n = double.tryParse(not.text.trim().replaceAll(',', '.'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      yil.dispose();
      sinif.dispose();
      not.dispose();
    });
    if (ok != true || !mounted) return;
    if (!RegExp(r'^20\d\d-20\d\d$').hasMatch(y2) || n == null || n < 0 || n > 100) {
      showInfo(context, 'Yılı 2025-2026 biçiminde, notu 0-100 arasında girin.');
      return;
    }
    await runSafe(context, () => OkulDb.yilSonuKaydet(sid, widget.me, y2, s2, n),
        success: 'Kaydedildi.');
  }

  // -------------------------------------------------------------------------
  // Ekran görüntüsünden aktarma
  // -------------------------------------------------------------------------
  Future<void> _ekrandanAktar() async {
    final secilen = await ImagePicker().pickMultiImage();
    if (secilen.isEmpty || !mounted) return;
    setState(() => _okunuyor = true);
    EkranSonucu sonuc;
    try {
      sonuc = await EkranOkuyucu.oku(secilen.map((e) => e.path).toList());
    } catch (e) {
      if (mounted) {
        setState(() => _okunuyor = false);
        showError(context, e);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _okunuyor = false);
    if (sonuc.bos) {
      showInfo(context,
          'Görüntüde sınav tarihi ya da not bulunamadı. e-Okul\'un "Sınav Tarihleri", '
          '"Not Bilgileri" ya da "Yıl Sonu Notları" ekranının görüntüsünü seçin.');
      return;
    }
    await _onizlemeGoster(sonuc);
  }

  Future<void> _eOkuldanEsitle() async {
    final sonuc = await Navigator.of(context).push<EkranSonucu>(
        MaterialPageRoute(builder: (_) => EOkulEkrani(ogrenciAdi: widget.student.name)));
    if (sonuc == null || sonuc.bos || !mounted) return;
    await _onizlemeGoster(sonuc);
  }

  Future<void> _onizlemeGoster(EkranSonucu sonuc) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AktarimOnizleme(
        student: widget.student,
        me: widget.me,
        sonuc: sonuc,
        mevcut: _sinavlar.value ?? const [],
        donem: _donem,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([_sinavlar, _yilSonlari]),
        builder: (context, _) {
          if (_sinavlar.error != null) {
            return EmptyState(icon: Icons.error_outline, text: errorText(_sinavlar.error!));
          }
          if (_sinavlar.loading) return const Loading();
          return _govde(context, _sinavlar.value!, _yilSonlari.value ?? const []);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_okul',
        backgroundColor: _lacivert,
        foregroundColor: Colors.white,
        onPressed: () => _sinavDuzenle(),
        icon: const Icon(Icons.add),
        label: const Text('Sınav / Not'),
      ),
    );
  }

  Widget _govde(BuildContext context, List<OkulSinav> tum, List<YilSonu> yillar) {
    final bugun = today();
    final yaklasan = tum
        .where((s) => s.not == null && s.tarih != null && !s.tarih!.isBefore(bugun))
        .toList();
    final gecmisNotsuz = tum
        .where((s) => s.not == null && s.tarih != null && s.tarih!.isBefore(bugun))
        .toList();
    final donemNotlar = tum.where((s) => s.donem == _donem && s.not != null).toList();

    // Ders -> notlar
    final dersler = <String, List<OkulSinav>>{};
    for (final s in donemNotlar) {
      dersler.putIfAbsent(s.ders, () => []).add(s);
    }
    double ort(List<OkulSinav> l) =>
        l.fold<double>(0, (a, b) => a + b.not!) / l.length;
    var agirlikToplam = 0.0, agirlikliNot = 0.0;
    for (final e in dersler.entries) {
      final w = dersAgirligi(e.key);
      agirlikToplam += w;
      agirlikliNot += ort(e.value) * w;
    }
    final donemOrt = agirlikToplam == 0 ? null : agirlikliNot / agirlikToplam;
    final belge = donemOrt == null
        ? null
        : (donemOrt >= 85 ? 'Takdir' : (donemOrt >= 70 ? 'Teşekkür' : null));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        VurguKart(
          renk: _lacivert,
          child: Row(
            children: [
              if (donemOrt != null)
                YuzdeHalka(
                  oran: donemOrt / 100,
                  ust: donemOrt.toStringAsFixed(1),
                  alt: '$_donem. dönem',
                  renk: Colors.white,
                  boyut: 96,
                )
              else
                const Icon(Icons.school, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Okul Notları',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(donemOrt == null
                        ? '$_donem. dönem henüz not yok.'
                        : 'Tahmini dönem ortalaması'
                            '${belge != null ? ' • $belge belgesi' : ''}'),
                    if (yaklasan.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Sıradaki: ${yaklasan.first.ders} — '
                        '${_kalan(yaklasan.first.tarih!)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: _lacivert, minimumSize: const Size.fromHeight(52)),
          onPressed: _eOkuldanEsitle,
          icon: const Icon(Icons.login),
          label: const Text('e-Okul\'a giriş yap ve eşitle'),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 6, 4, 10),
          child: Text(
            'e-Devlet ile giriş yapıp öğrenciyi seçin; uygulama sınav tarihlerini, notları '
            've yıl sonu notlarını kendisi okur. Giriş bilgileri uygulamada saklanmaz.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              foregroundColor: _lacivert, minimumSize: const Size.fromHeight(46)),
          onPressed: _okunuyor ? null : _ekrandanAktar,
          icon: _okunuyor
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _lacivert))
              : const Icon(Icons.document_scanner_outlined),
          label: Text(_okunuyor ? 'Okunuyor...' : 'e-Okul ekran görüntüsünden aktar'),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Text(
            'Alternatif: e-Okul VBS uygulamasındaki ekranların görüntüsünü seçin. '
            'Görüntü telefonda okunur, hiçbir yere gönderilmez.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        SectionTitle('Yaklaşan sınavlar (${yaklasan.length})'),
        if (yaklasan.isEmpty)
          const Card(
              child: Padding(
            padding: EdgeInsets.all(14),
            child: Text('Yaklaşan sınav yok.'),
          ))
        else
          for (final s in yaklasan) _sinavKarti(s, yaklasan: true),
        if (gecmisNotsuz.isNotEmpty) ...[
          const SectionTitle('Notu girilmeyen sınavlar'),
          for (final s in gecmisNotsuz) _sinavKarti(s, notBekliyor: true),
        ],
        SectionTitle('Notlar',
            trailing: SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 1, label: Text('1. Dönem')),
                ButtonSegment(value: 2, label: Text('2. Dönem')),
              ],
              selected: {_donem},
              onSelectionChanged: (v) => setState(() => _donem = v.first),
            )),
        if (dersler.isEmpty)
          const Card(
              child: Padding(
            padding: EdgeInsets.all(14),
            child: Text('Bu dönem için not girilmemiş.'),
          ))
        else
          for (final e in (dersler.entries.toList()
            ..sort((a, b) => dersAgirligi(b.key).compareTo(dersAgirligi(a.key)))))
            _dersKarti(e.key, e.value, ort(e.value)),
        SectionTitle('Yıl sonu notları',
            trailing: IconButton(
                tooltip: 'Ekle', onPressed: () => _yilSonuEkle(), icon: const Icon(Icons.add))),
        if (yillar.isEmpty)
          const Card(
              child: Padding(
            padding: EdgeInsets.all(14),
            child: Text('Yıl sonu notları için e-Okul\'daki "Yıl Sonu Notları" '
                'ekranının görüntüsünü aktarın.'),
          ))
        else ...[
          if (yillar.length >= 2)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                child: CizgiGrafik(
                  degerler: yillar.map((y) => y.not).toList(),
                  etiketler: yillar
                      .map((y) => y.sinif.isNotEmpty ? y.sinif.replaceAll(' Sınıf', '') : y.yil)
                      .toList(),
                  renk: _lacivert,
                  ondalik: 2,
                ),
              ),
            ),
          Card(
            child: Column(
              children: [
                for (final y in yillar.reversed)
                  ListTile(
                    leading: const Icon(Icons.workspace_premium_outlined, color: _lacivert),
                    title: Text(y.yil),
                    subtitle: y.sinif.isEmpty ? null : Text(y.sinif),
                    trailing: Text(
                      y.not.toStringAsFixed(4).replaceAll('.', ','),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800, color: _lacivert),
                    ),
                    onTap: () => _yilSonuEkle(y),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _kalan(DateTime t) {
    final g = DateUtils.dateOnly(t).difference(today()).inDays;
    if (g == 0) return 'bugün';
    if (g == 1) return 'yarın';
    return '$g gün sonra';
  }

  Widget _sinavKarti(OkulSinav s, {bool yaklasan = false, bool notBekliyor = false}) {
    final (ikon, renk) = _dersGorunum(s.ders);
    final g = s.tarih == null ? 99 : DateUtils.dateOnly(s.tarih!).difference(today()).inDays;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: renk.withValues(alpha: 0.14), child: Icon(ikon, color: renk)),
        title: Text(s.ders, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${s.baslik} • ${fmtDate(s.tarih)}'),
        trailing: yaklasan
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (g <= 2 ? Colors.red : renk).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_kalan(s.tarih!),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: g <= 2 ? Colors.red.shade700 : renk)),
              )
            : (notBekliyor
                ? FilledButton.tonal(
                    onPressed: () => _sinavDuzenle(s, true),
                    child: const Text('Not gir'))
                : null),
        onTap: _yetki(s) ? () => _sinavDuzenle(s, notBekliyor) : null,
      ),
    );
  }

  Widget _dersKarti(String ders, List<OkulSinav> notlar, double ortalama) {
    final (ikon, renk) = _dersGorunum(ders);
    final sirali = List.of(notlar)
      ..sort((a, b) {
        const t = {'yazili': 0, 'performans': 1, 'proje': 2};
        final c = t[a.tur]!.compareTo(t[b.tur]!);
        return c != 0 ? c : a.sira.compareTo(b.sira);
      });
    final dusuk = ortalama < 50;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                    radius: 18,
                    backgroundColor: renk.withValues(alpha: 0.14),
                    child: Icon(ikon, color: renk, size: 20)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(ders,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                Text(ortalama.toStringAsFixed(2),
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: dusuk ? Colors.red.shade700 : renk)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in sirali)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: renk.withValues(alpha: 0.10),
                    label: Text(
                        '${s.baslik}: ${s.not!.toStringAsFixed(s.not! % 1 == 0 ? 0 : 2)}',
                        style: TextStyle(color: renk, fontWeight: FontWeight.w600)),
                    onPressed: _yetki(s) ? () => _sinavDuzenle(s) : null,
                  ),
              ],
            ),
            if (dusuk)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Ortalama 50\'nin altında, bu derse ağırlık verilmeli.',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sınav / not ekleme-düzenleme
// ---------------------------------------------------------------------------
class _SinavDialog extends StatefulWidget {
  const _SinavDialog({
    required this.student,
    required this.me,
    required this.sinav,
    required this.donem,
    required this.notOdakli,
    required this.mevcut,
  });

  final Student student;
  final AppUser me;
  final OkulSinav? sinav;
  final int donem;
  final bool notOdakli;
  final List<OkulSinav> mevcut;

  @override
  State<_SinavDialog> createState() => _SinavDialogState();
}

class _SinavDialogState extends State<_SinavDialog> {
  late String _ders = widget.sinav?.ders ?? 'Türkçe';
  late String _tur = widget.sinav?.tur ?? 'yazili';
  late int _sira = widget.sinav?.sira ?? 1;
  late int _donem = widget.sinav?.donem ?? widget.donem;
  late DateTime? _tarih = widget.sinav?.tarih;
  late final _not = TextEditingController(
      text: widget.sinav?.not == null
          ? ''
          : widget.sinav!.not!.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), ''));
  bool _mesgul = false;

  @override
  void dispose() {
    _not.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    double? not;
    if (_not.text.trim().isNotEmpty) {
      not = double.tryParse(_not.text.trim().replaceAll(',', '.'));
      if (not == null || not < 0 || not > 100) {
        showInfo(context, 'Not 0 ile 100 arasında olmalı.');
        return;
      }
    }
    if (not == null && _tarih == null) {
      showInfo(context, 'Sınav tarihi ya da not girin.');
      return;
    }
    setState(() => _mesgul = true);
    final nav = Navigator.of(context);
    final ok = await runSafe(
      context,
      () => OkulDb.sinavKaydet(
        widget.student.id,
        widget.me,
        id: widget.sinav?.id,
        ders: _ders,
        tur: _tur,
        sira: _sira,
        donem: _donem,
        tarih: _tarih,
        not: not,
      ),
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
    final dersler = {..._okulDersleri, _ders}.toList();
    return AlertDialog(
      title: Text(widget.sinav == null ? 'Sınav / not ekle' : 'Düzenle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _ders,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Ders', border: OutlineInputBorder()),
              items: [
                for (final d in dersler) DropdownMenuItem(value: d, child: Text(d)),
              ],
              onChanged: (v) => setState(() => _ders = v ?? _ders),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    value: _tur,
                    decoration: const InputDecoration(
                        labelText: 'Tür', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'yazili', child: Text('Yazılı')),
                      DropdownMenuItem(value: 'performans', child: Text('Performans')),
                      DropdownMenuItem(value: 'proje', child: Text('Proje')),
                    ],
                    onChanged: (v) => setState(() => _tur = v ?? _tur),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    value: _sira,
                    decoration: const InputDecoration(
                        labelText: 'Sıra', border: OutlineInputBorder()),
                    items: [
                      for (var i = 1; i <= 4; i++)
                        DropdownMenuItem(value: i, child: Text('$i.')),
                    ],
                    onChanged: (v) => setState(() => _sira = v ?? _sira),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1. Dönem')),
                ButtonSegment(value: 2, label: Text('2. Dönem')),
              ],
              selected: {_donem},
              onSelectionChanged: (v) => setState(() => _donem = v.first),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              onPressed: () async {
                final t = await showDatePicker(
                  context: context,
                  initialDate: _tarih ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                );
                if (t != null) setState(() => _tarih = t);
              },
              icon: const Icon(Icons.event),
              label: Text(_tarih == null ? 'Sınav tarihi (isteğe bağlı)' : fmtDate(_tarih)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _not,
              autofocus: widget.notOdakli,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(
                labelText: 'Not (sınav yapılmadıysa boş bırakın)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.sinav != null)
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              final ok = await runSafe(context,
                  () => OkulDb.sil(widget.student.id, 'okulSinavlari', widget.sinav!.id));
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
// Ekran görüntüsünden okunanların önizlemesi
// ---------------------------------------------------------------------------
class _AktarimOnizleme extends StatefulWidget {
  const _AktarimOnizleme({
    required this.student,
    required this.me,
    required this.sonuc,
    required this.mevcut,
    required this.donem,
  });

  final Student student;
  final AppUser me;
  final EkranSonucu sonuc;
  final List<OkulSinav> mevcut;
  final int donem;

  @override
  State<_AktarimOnizleme> createState() => _AktarimOnizlemeState();
}

class _AktarimOnizlemeState extends State<_AktarimOnizleme> {
  late final List<bool> _sinavSec = List.filled(widget.sonuc.sinavlar.length, true);
  late final List<bool> _yilSec = List.filled(widget.sonuc.yilSonlari.length, true);
  late final List<bool> _notSec = List.filled(widget.sonuc.notlar.length, true);
  late int _donem = widget.donem;
  bool _mesgul = false;

  Future<void> _aktar() async {
    setState(() => _mesgul = true);
    final sid = widget.student.id;
    final me = widget.me;
    var adet = 0;
    final ok = await runSafe(context, () async {
      final s = widget.sonuc;
      for (var i = 0; i < s.sinavlar.length; i++) {
        if (!_sinavSec[i]) continue;
        final x = s.sinavlar[i];
        final varMi = widget.mevcut.any(
            (m) => m.ders == x.ders && m.tarih != null && DateUtils.isSameDay(m.tarih, x.tarih));
        if (varMi) continue;
        final ayni = widget.mevcut
            .where((m) => m.ders == x.ders && m.tur == 'yazili' && m.donem == donemOf(x.tarih))
            .length;
        await OkulDb.sinavKaydet(sid, me,
            ders: x.ders,
            tur: 'yazili',
            sira: ayni + 1,
            donem: donemOf(x.tarih),
            tarih: x.tarih,
            not: null);
        adet++;
      }
      for (var i = 0; i < s.yilSonlari.length; i++) {
        if (!_yilSec[i]) continue;
        final y = s.yilSonlari[i];
        await OkulDb.yilSonuKaydet(sid, me, y.yil, y.sinif, y.not);
        adet++;
      }
      for (var i = 0; i < s.notlar.length; i++) {
        if (!_notSec[i]) continue;
        final n = s.notlar[i];
        final donem = n.donem ?? _donem;
        // Aynı ders/tür/sıra/dönem varsa notunu güncelle
        OkulSinav? eslesen;
        for (final m in widget.mevcut) {
          if (m.ders == n.ders && m.tur == n.tur && m.sira == n.sira && m.donem == donem) {
            eslesen = m;
          }
        }
        if (eslesen != null && eslesen.not == n.not) continue; // değişmemiş
        await OkulDb.sinavKaydet(sid, me,
            id: eslesen?.id,
            ders: n.ders,
            tur: n.tur,
            sira: n.sira,
            donem: donem,
            tarih: eslesen?.tarih,
            not: n.not);
        adet++;
      }
    });
    if (!mounted) return;
    final mesaj = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    if (ok) mesaj.showSnackBar(SnackBar(content: Text('$adet kayıt aktarıldı.')));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sonuc;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Okunan bilgiler',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('Yanlış okunanların işaretini kaldırın, sonra Aktar\'a basın.'),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (s.sinavlar.isNotEmpty) const _Baslik('Sınav tarihleri'),
                  for (var i = 0; i < s.sinavlar.length; i++)
                    CheckboxListTile(
                      value: _sinavSec[i],
                      onChanged: (v) => setState(() => _sinavSec[i] = v ?? false),
                      title: Text(s.sinavlar[i].ders),
                      subtitle: Text(fmtDate(s.sinavlar[i].tarih)),
                    ),
                  if (s.yilSonlari.isNotEmpty) const _Baslik('Yıl sonu notları'),
                  for (var i = 0; i < s.yilSonlari.length; i++)
                    CheckboxListTile(
                      value: _yilSec[i],
                      onChanged: (v) => setState(() => _yilSec[i] = v ?? false),
                      title: Text('${s.yilSonlari[i].yil}  ${s.yilSonlari[i].sinif}'),
                      subtitle: Text(s.yilSonlari[i].not.toString().replaceAll('.', ',')),
                    ),
                  if (s.notlar.isNotEmpty) ...[
                    _Baslik('Notlar',
                        trailing: s.notlar.every((n) => n.donem != null)
                            ? null
                            : SegmentedButton<int>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: const [
                            ButtonSegment(value: 1, label: Text('1. Dönem')),
                            ButtonSegment(value: 2, label: Text('2. Dönem')),
                          ],
                          selected: {_donem},
                          onSelectionChanged: (v) => setState(() => _donem = v.first),
                        )),
                    for (var i = 0; i < s.notlar.length; i++)
                      CheckboxListTile(
                        value: _notSec[i],
                        onChanged: (v) => setState(() => _notSec[i] = v ?? false),
                        title: Text(s.notlar[i].ders),
                        subtitle: Text(
                            '${s.notlar[i].donem != null ? '${s.notlar[i].donem}. dönem • ' : ''}'
                            '${s.notlar[i].sira}. ${switch (s.notlar[i].tur) {
                          'performans' => 'Performans',
                          'proje' => 'Proje',
                          _ => 'Yazılı'
                        }}: ${s.notlar[i].not.toStringAsFixed(s.notlar[i].not % 1 == 0 ? 0 : 2)}'),
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: _lacivert, minimumSize: const Size.fromHeight(50)),
                onPressed: _mesgul ? null : _aktar,
                icon: const Icon(Icons.download_done),
                label: const Text('Aktar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Baslik extends StatelessWidget {
  const _Baslik(this.metin, {this.trailing});

  final String metin;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(metin,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
