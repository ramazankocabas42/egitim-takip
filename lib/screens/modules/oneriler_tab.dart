import 'package:flutter/material.dart';

import '../../lgs.dart';
import '../../models.dart';
import '../../services/db.dart';
import '../../services/okul_db.dart';
import '../../services/oneri_motoru.dart';
import '../../services/osym_db.dart';
import '../../services/program_db.dart';
import '../../services/takip_db.dart';
import '../../widgets/common.dart';
import '../../widgets/grafik.dart';
import '../ogrenci_profil.dart' show dersOnerisi, hedefOnerisi;

Color _onemRenk(Onem o) => switch (o) {
      Onem.kritik => const Color(0xFFC62828),
      Onem.onemli => const Color(0xFFEF6C00),
      Onem.bilgi => const Color(0xFF1565C0),
      Onem.iyi => const Color(0xFF2E7D32),
    };

String _onemAd(Onem o) => switch (o) {
      Onem.kritik => 'Acil',
      Onem.onemli => 'Önemli',
      Onem.bilgi => 'Bilgi',
      Onem.iyi => 'Tebrikler',
    };

/// ÖNERİLERİM: genel durum (iyi/orta/kötü), eksik konular, ağırlık
/// verilecek dersler ve kişisel öneriler.
class OnerilerTab extends StatefulWidget {
  const OnerilerTab({super.key, required this.student, required this.me});

  final Student student;
  final AppUser me;

  @override
  State<OnerilerTab> createState() => _OnerilerTabState();
}

class _OnerilerTabState extends State<OnerilerTab> {
  String get sid => widget.student.id;
  late final _sorular = LiveValue(TakipDb.sorular(sid));
  late final _denemeler = LiveValue(TakipDb.denemeler(sid));
  late final _hedef = LiveValue(TakipDb.hedef(sid));
  late final _okul = LiveValue(OkulDb.sinavlar(sid));
  late final _odevler = LiveValue(Db.homeworks(sid));
  late final _plan = LiveValue(TakipDb.plan(sid, haftaAnahtari(DateTime.now())));
  late final _etkinlikler = LiveValue(ProgramDb.etkinlikler(sid));
  late final _duzen = LiveValue(ProgramDb.duzen(sid));
  late final _osym = LiveValue(OsymDb.sonuclar(sid));
  bool _tumKonular = false;

  List<LiveValue<Object?>> get _hepsi =>
      [_sorular, _denemeler, _hedef, _okul, _odevler, _plan, _etkinlikler, _duzen, _osym];

  Student get s => widget.student;
  String get _profil => s.hedefSinav.isNotEmpty ? s.hedefSinav : hedefOnerisi(s.grade);

  @override
  void dispose() {
    for (final l in _hepsi) {
      l.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(_hepsi),
      builder: (context, _) {
        if (_sorular.error != null) {
          return EmptyState(icon: Icons.error_outline, text: errorText(_sorular.error!));
        }
        if (_sorular.loading || _denemeler.loading || _okul.loading) {
          return const Loading();
        }
        final etk = _etkinlikler.value ?? const <ProgramEtkinligi>[];
        final rapor = OneriMotoru(
          sorular: _sorular.value!,
          denemeler: _denemeler.value!,
          hedef: _hedef.value,
          okulNotlari: _okul.value!,
          odevler: _odevler.value ?? const [],
          plan: _plan.value,
          programHaftasi: etk.isEmpty
              ? null
              : ZamanMotoru(etk, _duzen.value ?? const GunDuzeni())
                  .hafta(plan: _plan.value),
          duzen: _duzen.value,
          profil: _profil,
          dersAdlari: s.dersler.isNotEmpty ? s.dersler : dersOnerisi(s.grade, _profil, s.alan),
          osym: _osym.value ?? const [],
          okulVar: !okulDisi(s.grade),
        ).rapor();
        return _govde(context, rapor);
      },
    );
  }

  Widget _govde(BuildContext context, OneriRaporu r) {
    final genel = r.genel;
    final skor = r.genelSkor;
    final zayif = r.eksikKonular.where((k) => k.zayif).toList();
    final calisilmamis = r.eksikKonular.where((k) => !k.zayif).toList();
    final dersRenk = {for (final d in r.dersler) d.ders.ad: d.ders};
    final kaynakMetni = switch (_profil) {
      'LGS' => 'son 3 LGS denemesi, ',
      'YKS' || 'KPSS' || 'AGS' => 'son $_profil sınav ve deneme sonuçları (konu eksikleriyle), ',
      _ => '',
    };
    final profil = _profil;
    final baslik = switch (profil) {
      'LGS' => 'LGS hazırlığı',
      'YKS' => 'YKS hazırlığı${s.alan.isEmpty ? '' : ' (${s.alan})'}',
      'KPSS' => 'KPSS hazırlığı',
      'AGS' => 'AGS / ÖABT hazırlığı',
      _ => '${s.grade} okul dersleri',
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        VurguKart(
          renk: genel == Seviye.yok ? Colors.blueGrey : genel.renk,
          child: Row(
            children: [
              YuzdeHalka(
                oran: (skor ?? 0) / 100,
                ust: skor == null ? '—' : skor.round().toString(),
                alt: '/ 100',
                renk: Colors.white,
                boyut: 96,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Genel durum • $baslik', style: const TextStyle(fontSize: 14)),
                    Row(
                      children: [
                        Icon(genel.ikon, size: 28),
                        const SizedBox(width: 6),
                        Text(genel.ad,
                            style: const TextStyle(
                                fontSize: 26, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      switch (genel) {
                        Seviye.iyi => 'Gidişat iyi. Zayıf konuları kapatmaya devam.',
                        Seviye.orta => 'Fena değil, ama aşağıdaki derslere ağırlık verilmeli.',
                        Seviye.kotu => 'Destek gerekiyor. Önerileri sırayla uygulayın.',
                        Seviye.yok => 'Değerlendirme için soru, deneme ya da not girin.',
                      },
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Alanlar
        Card(
          child: Column(
            children: [
              for (final a in r.alanlar)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: a.seviye.renk.withValues(alpha: 0.14),
                    child: Icon(a.ikon, color: a.seviye.renk),
                  ),
                  title: Text(a.ad, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(a.aciklama, style: const TextStyle(fontSize: 12.5)),
                  trailing: _SeviyeRozeti(a.seviye, a.deger),
                ),
            ],
          ),
        ),
        SectionTitle('Önerilerim (${r.oneriler.length})'),
        for (final o in r.oneriler) _oneriKarti(o),
        const SectionTitle('Ağırlık verilecek dersler'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                for (var i = 0; i < r.dersler.length; i++) ...[
                  if (i > 0) const Divider(height: 14),
                  _dersSatiri(i + 1, r.dersler[i]),
                ],
              ],
            ),
          ),
        ),
        if (r.okulZayif.isNotEmpty) ...[
          const SectionTitle('Okulda desteklenmesi gereken dersler'),
          Card(
            child: Column(
              children: [
                for (final z in r.okulZayif)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.school_outlined,
                        color: seviyeOf(z.$2).renk),
                    title: Text(z.$1),
                    trailing: _SeviyeRozeti(seviyeOf(z.$2), z.$2.toStringAsFixed(1)),
                  ),
              ],
            ),
          ),
        ],
        SectionTitle('Eksik konular (${zayif.length})'),
        if (zayif.isEmpty)
          const Card(
              child: Padding(
            padding: EdgeInsets.all(14),
            child: Text('Soru Takibi\'nde konu bazlı giriş yapıldıkça ve ÖSYM / deneme '
                'sonuçlarında yanlış yapılan konular işlendikçe eksik konular burada listelenir.'),
          ))
        else
          Card(
            child: Column(
              children: [
                for (final k in zayif.take(_tumKonular ? zayif.length : 8))
                  _konuSatiri(k, dersRenk[k.ders]),
                if (zayif.length > 8)
                  TextButton(
                    onPressed: () => setState(() => _tumKonular = !_tumKonular),
                    child: Text(_tumKonular ? 'Daha az göster' : 'Tümünü göster (${zayif.length})'),
                  ),
              ],
            ),
          ),
        if (calisilmamis.isNotEmpty) ...[
          SectionTitle('Hiç çalışılmamış konular (${calisilmamis.length})'),
          Card(
            child: Column(
              children: [
                for (final d in lgsDersler)
                  if (calisilmamis.any((k) => k.ders == d.ad))
                    ExpansionTile(
                      leading: Icon(d.ikon, color: d.renk),
                      title: Text(d.ad),
                      trailing: Text('${calisilmamis.where((k) => k.ders == d.ad).length} konu',
                          style: TextStyle(color: d.renk, fontWeight: FontWeight.w700)),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final k in calisilmamis.where((k) => k.ders == d.ad))
                                Chip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(k.konu, style: const TextStyle(fontSize: 12)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
          child: Text(
            'Değerlendirme öğrencinin kayıtlı sınıfına (${s.grade}) ve hedefine ($baslik) göre; '
            'profildeki dersler, son 14 günün soru girişleri, '
            '$kaynakMetni'
            '${okulDisi(s.grade) ? '' : 'bu dönemin okul notları, '}'
            'son 30 günün ödevleri, bu haftanın planı ve haftalık programdaki boş zamana göre '
            'otomatik hesaplanır. 75 ve üzeri İyi, 55-75 Orta, 55 altı Kötü sayılır. Sınıf veya '
            'hedef değişirse öğrenci ayarlarından güncelleyin.',
            style: const TextStyle(fontSize: 11.5, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _oneriKarti(Oneri o) {
    final r = _onemRenk(o.onem);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: r),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(o.ikon, color: r),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_onemAd(o.onem),
                              style: TextStyle(
                                  color: r, fontSize: 11.5, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(o.metin),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dersSatiri(int sira, DersOnerisi d) {
    final sv = d.seviye;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: sira <= 2 ? d.ders.renk : d.ders.renk.withValues(alpha: 0.18),
              child: Text('$sira',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: sira <= 2 ? Colors.white : d.ders.renk)),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: DersCubugu(
                ikon: d.ders.ikon,
                ad: d.ders.ad,
                oran: d.basari ?? 0,
                deger: d.basari == null ? 'veri yok' : '%${(d.basari! * 100).round()}',
                renk: d.ders.renk,
                alt: d.neden,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 30),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _SeviyeRozeti(sv, sv.ad),
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.timer_outlined, size: 16),
                label: Text('Haftada ${d.haftalikBlok} blok',
                    style: const TextStyle(fontSize: 12)),
              ),
              for (final k in d.konular)
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: d.ders.renk.withValues(alpha: 0.10),
                  side: BorderSide.none,
                  label: Text(k, style: TextStyle(fontSize: 12, color: d.ders.renk)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _konuSatiri(EksikKonu k, LgsDers? pd) {
    final d = lgsDers(k.ders) ?? pd;
    final renk = d?.renk ?? Colors.blueGrey;
    final osymdan = k.basari == null;
    final sv = osymdan
        ? (k.hata >= 3 ? Seviye.kotu : Seviye.orta)
        : seviyeOf(k.basari! * 100);
    return ListTile(
      dense: true,
      leading: Icon(d?.ikon ?? Icons.book_outlined, color: renk),
      title: Text(k.konu, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(osymdan
          ? '${k.ders} • sınav / deneme sonuçlarında ${k.hata} yanlış-boş'
          : '${k.ders} • ${k.soru} soru'),
      trailing: _SeviyeRozeti(sv, osymdan ? '${k.hata} hata' : '%${(k.basari! * 100).round()}'),
    );
  }
}

class _SeviyeRozeti extends StatelessWidget {
  const _SeviyeRozeti(this.seviye, this.metin);
  final Seviye seviye;
  final String metin;

  @override
  Widget build(BuildContext context) {
    final r = seviye.renk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: r.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        metin == seviye.ad || seviye == Seviye.yok ? metin : '$metin • ${seviye.ad}',
        style: TextStyle(color: r, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}
