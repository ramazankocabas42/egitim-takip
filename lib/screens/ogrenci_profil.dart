import 'package:flutter/material.dart';

import '../models.dart';
import '../services/db.dart';
import '../widgets/common.dart';

/// Hedef sınavlar.
const hedefSinavlar = <(String, String, IconData)>[
  ('okul', 'Okul dersleri', Icons.school_outlined),
  ('LGS', 'LGS', Icons.flag_outlined),
  ('YKS', 'YKS (Üniversite)', Icons.account_balance_outlined),
  ('KPSS', 'KPSS', Icons.work_outline),
  ('AGS', 'AGS / ÖABT (Öğretmenlik)', Icons.co_present_outlined),
];

const yksAlanlari = ['SAY', 'EA', 'SÖZ', 'DİL'];
const kpssDuzeyleri = ['Lisans', 'Önlisans', 'Ortaöğretim'];

/// Gizlenebilen sekmeler: kimlik, ad.
const secilebilirSekmeler = <(String, String)>[
  ('oneriler', 'Önerilerim'),
  ('odevler', 'Ödevler'),
  ('plan', 'Plan'),
  ('program', 'Program'),
  ('soru', 'Soru Takibi'),
  ('okul', 'Okul'),
  ('kitaplar', 'Kitaplar'),
  ('testkitaplari', 'Test Kitapları'),
  ('testler', 'Testler'),
];

/// Sınıfa göre önerilen hedef.
String hedefOnerisi(String sinif) {
  if (sinif == '8. Sınıf') return 'LGS';
  if (ortaokulVeAlti(sinif)) return 'okul';
  if (sinif == '11. Sınıf' || sinif == '12. Sınıf' || sinif == 'Mezun') return 'YKS';
  if (sinif.startsWith('Üniversite')) return 'KPSS';
  return 'okul';
}

/// Sınıf, hedef sınav ve alana göre önerilen dersler.
List<String> dersOnerisi(String sinif, String hedef, String alan) {
  switch (hedef) {
    case 'LGS':
      return ['Türkçe', 'Matematik', 'Fen Bilimleri', 'T.C. İnkılap Tarihi', 'İngilizce', 'Din Kültürü'];
    case 'YKS':
      final tyt = ['Türkçe', 'Matematik', 'Geometri'];
      return switch (alan) {
        'EA' => [...tyt, 'Edebiyat', 'Tarih', 'Coğrafya', 'Felsefe', 'Din Kültürü', 'Fizik', 'Kimya', 'Biyoloji'],
        'SÖZ' => [...tyt, 'Edebiyat', 'Tarih', 'Coğrafya', 'Felsefe', 'Din Kültürü', 'Fizik', 'Kimya', 'Biyoloji'],
        'DİL' => [...tyt, 'İngilizce', 'Tarih', 'Coğrafya', 'Felsefe', 'Din Kültürü', 'Fizik', 'Kimya', 'Biyoloji'],
        _ => [...tyt, 'Fizik', 'Kimya', 'Biyoloji', 'Tarih', 'Coğrafya', 'Felsefe', 'Din Kültürü'],
      };
    case 'KPSS':
      return ['Türkçe', 'Matematik', 'Geometri', 'Tarih', 'Coğrafya', 'Vatandaşlık', 'Güncel Bilgiler'];
    case 'AGS':
      return ['Sözel Yetenek', 'Sayısal Yetenek', 'Tarih', 'Türkiye Coğrafyası', 'Eğitim Bilimleri',
        'Mevzuat', 'Alan Bilgisi (ÖABT)'];
  }
  // Okul dersleri
  final i = grades.indexOf(sinif);
  if (i <= grades.indexOf('4. Sınıf')) {
    return ['Türkçe', 'Matematik', 'Hayat Bilgisi', 'Fen Bilimleri', 'Sosyal Bilgiler', 'İngilizce'];
  }
  if (ortaokulVeAlti(sinif)) {
    return ['Türkçe', 'Matematik', 'Fen Bilimleri', 'Sosyal Bilgiler', 'İngilizce', 'Din Kültürü'];
  }
  return ['Edebiyat', 'Matematik', 'Fizik', 'Kimya', 'Biyoloji', 'Tarih', 'Coğrafya', 'Felsefe',
    'Din Kültürü', 'İngilizce'];
}

/// Formun ürettiği ayarlar.
class OgrenciAyarlari {
  OgrenciAyarlari({
    required this.sinif,
    required this.hedef,
    this.alan = '',
    this.dogumYili,
    required this.dersler,
    this.gizli = const [],
  });

  String sinif;
  String hedef;
  String alan;
  int? dogumYili;
  List<String> dersler;
  List<String> gizli;

  factory OgrenciAyarlari.ogrenciden(Student s) {
    final hedef = s.hedefSinav.isNotEmpty ? s.hedefSinav : hedefOnerisi(s.grade);
    return OgrenciAyarlari(
      sinif: s.grade,
      hedef: hedef,
      alan: s.alan,
      dogumYili: s.dogumYili,
      dersler: s.dersler.isNotEmpty ? [...s.dersler] : dersOnerisi(s.grade, hedef, s.alan),
      gizli: [...s.gizliSekmeler],
    );
  }

  factory OgrenciAyarlari.yeni([String sinif = '12. Sınıf']) {
    final h = hedefOnerisi(sinif);
    final a = h == 'YKS' ? 'SAY' : (h == 'KPSS' ? 'Lisans' : '');
    return OgrenciAyarlari(sinif: sinif, hedef: h, alan: a, dersler: dersOnerisi(sinif, h, a));
  }

  Map<String, Object?> toMap() => {
        'hedefSinav': hedef,
        'alan': alan,
        'dogumYili': dogumYili,
        'dersler': dersler,
        'gizliSekmeler': gizli,
      };
}

/// Sınıf / durum, hedef sınav, alan, doğum yılı, dersler ve sekmeler.
class OgrenciAyarFormu extends StatefulWidget {
  const OgrenciAyarFormu({super.key, required this.ayarlar, this.sekmeler = true});

  final OgrenciAyarlari ayarlar;
  final bool sekmeler;

  @override
  State<OgrenciAyarFormu> createState() => _OgrenciAyarFormuState();
}

class _OgrenciAyarFormuState extends State<OgrenciAyarFormu> {
  OgrenciAyarlari get a => widget.ayarlar;

  void _dersleriYenile() => a.dersler = dersOnerisi(a.sinif, a.hedef, a.alan);

  Future<void> _dersEkle() async {
    final c = TextEditingController();
    final ad = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ders ekle'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Ör. Geometri, Almanca'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Ekle')),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    if (ad != null && ad.isNotEmpty && !a.dersler.contains(ad)) {
      setState(() => a.dersler = [...a.dersler, ad]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final yil = DateTime.now().year;
    final tumDersler = {
      ...a.dersler,
      ...dersOnerisi(a.sinif, a.hedef, a.alan),
    }.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: grades.contains(a.sinif) ? a.sinif : null,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Sınıfın / durumun', border: OutlineInputBorder()),
          items: grades.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
          onChanged: (v) => setState(() {
            a.sinif = v ?? a.sinif;
            a.hedef = hedefOnerisi(a.sinif);
            a.alan = a.hedef == 'YKS' ? 'SAY' : (a.hedef == 'KPSS' ? 'Lisans' : '');
            _dersleriYenile();
          }),
        ),
        const SizedBox(height: 16),
        const Text('Hangi sınava hazırlanıyorsun?', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final h in hedefSinavlar)
              ChoiceChip(
                avatar: Icon(h.$3, size: 18),
                label: Text(h.$2),
                selected: a.hedef == h.$1,
                onSelected: (_) => setState(() {
                  a.hedef = h.$1;
                  a.alan = h.$1 == 'YKS' ? 'SAY' : (h.$1 == 'KPSS' ? 'Lisans' : '');
                  _dersleriYenile();
                }),
              ),
          ],
        ),
        if (a.hedef == 'YKS' || a.hedef == 'KPSS') ...[
          const SizedBox(height: 12),
          Text(a.hedef == 'YKS' ? 'Puan türün (alan)' : 'KPSS düzeyi',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final x in a.hedef == 'YKS' ? yksAlanlari : kpssDuzeyleri)
                ChoiceChip(
                  label: Text(x),
                  selected: a.alan == x,
                  onSelected: (_) => setState(() {
                    a.alan = x;
                    _dersleriYenile();
                  }),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        DropdownButtonFormField<int?>(
          value: a.dogumYili,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Doğum yılın (isteğe bağlı)', border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Belirtmek istemiyorum')),
            for (var y = yil - 5; y >= yil - 50; y--)
              DropdownMenuItem<int?>(value: y, child: Text('$y  (${yil - y} yaş)')),
          ],
          onChanged: (v) => setState(() => a.dogumYili = v),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(
              child: Text('Derslerin', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => setState(_dersleriYenile),
              child: const Text('Önerilene dön'),
            ),
          ],
        ),
        const Text('Seçtiğin dersler ödev, kitap ve plan ekranlarında listelenir.',
            style: TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final d in tumDersler)
              FilterChip(
                label: Text(d),
                selected: a.dersler.contains(d),
                onSelected: (v) => setState(() {
                  a.dersler = v
                      ? [...a.dersler, d]
                      : a.dersler.where((x) => x != d).toList();
                }),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Ders ekle'),
              onPressed: _dersEkle,
            ),
          ],
        ),
        if (widget.sekmeler) ...[
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Görünecek bölümler', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(a.gizli.isEmpty ? 'Hepsi açık' : '${a.gizli.length} bölüm gizli'),
            children: [
              for (final s in secilebilirSekmeler)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.$2),
                  value: !a.gizli.contains(s.$1),
                  onChanged: (v) => setState(() {
                    a.gizli = v
                        ? a.gizli.where((x) => x != s.$1).toList()
                        : [...a.gizli, s.$1];
                  }),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Öğrencinin kendi profilini oluşturduğu tam ekran (ana sayfadan).
class OgrenciProfilOlusturEkrani extends StatefulWidget {
  const OgrenciProfilOlusturEkrani({super.key, required this.me});
  final AppUser me;

  @override
  State<OgrenciProfilOlusturEkrani> createState() => _OgrenciProfilOlusturEkraniState();
}

class _OgrenciProfilOlusturEkraniState extends State<OgrenciProfilOlusturEkrani> {
  late final _ad = TextEditingController(text: widget.me.name);
  final _ayar = OgrenciAyarlari.yeni();
  bool _mesgul = false;

  @override
  void dispose() {
    _ad.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final ad = _ad.text.trim();
    if (ad.isEmpty) {
      showInfo(context, 'Adını yaz.');
      return;
    }
    setState(() => _mesgul = true);
    final nav = Navigator.of(context);
    final ok = await runSafe(
      context,
      () => Db.createOwnProfile(widget.me, name: ad, grade: _ayar.sinif, ayarlar: _ayar.toMap()),
      success: 'Profilin hazır.',
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
      appBar: AppBar(title: const Text('Profilini oluştur')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 32 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          TextField(
            controller: _ad,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Adın Soyadın', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          OgrenciAyarFormu(ayarlar: _ayar),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _mesgul ? null : _kaydet,
            child: const Text('Başla'),
          ),
        ],
      ),
    );
  }
}

/// Sonradan düzenleme (öğrenci ekranından).
class OgrenciAyarSheet extends StatefulWidget {
  const OgrenciAyarSheet({super.key, required this.student});
  final Student student;

  @override
  State<OgrenciAyarSheet> createState() => _OgrenciAyarSheetState();
}

class _OgrenciAyarSheetState extends State<OgrenciAyarSheet> {
  late final _ayar = OgrenciAyarlari.ogrenciden(widget.student);
  bool _mesgul = false;

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: 'Sınav, dersler ve bölümler',
      children: [
        OgrenciAyarFormu(ayarlar: _ayar),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _mesgul
              ? null
              : () async {
                  setState(() => _mesgul = true);
                  final nav = Navigator.of(context);
                  final ok = await runSafe(context, () async {
                    await Db.updateStudent(widget.student.id,
                        name: widget.student.name, grade: _ayar.sinif);
                    await Db.updateStudentAyarlar(widget.student.id, _ayar.toMap());
                  }, success: 'Kaydedildi.');
                  if (ok) {
                    nav.pop();
                  } else if (mounted) {
                    setState(() => _mesgul = false);
                  }
                },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
