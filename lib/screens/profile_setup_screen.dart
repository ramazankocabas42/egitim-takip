import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/db.dart';
import '../widgets/common.dart';
import 'ogrenci_profil.dart';

/// Kullanım şekilleri (ilk girişte seçilir).
enum _Kullanim { bireysel, davetli, veli, ogretmen }

/// Yeni hesap açıldıktan sonra ad ve kullanım şekli seçilir.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, required this.user});

  final User user;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _name = TextEditingController();
  _Kullanim _secim = _Kullanim.bireysel;
  final _ayar = OgrenciAyarlari.yeni();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  UserRole get _role => switch (_secim) {
        _Kullanim.bireysel || _Kullanim.davetli => UserRole.student,
        _Kullanim.veli => UserRole.parent,
        _Kullanim.ogretmen => UserRole.teacher,
      };

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showInfo(context, 'Lütfen adınızı yazın.');
      return;
    }
    setState(() => _busy = true);
    final email = widget.user.email ?? '';
    final bireysel = _secim == _Kullanim.bireysel;
    await runSafe(context, () async {
      await Db.createProfile(uid: widget.user.uid, name: name, email: email, role: _role);
      if (bireysel) {
        await Db.createOwnProfile(
          AppUser(uid: widget.user.uid, name: name, email: email, role: UserRole.student),
          name: name,
          grade: _ayar.sinif,
          ayarlar: _ayar.toMap(),
        );
      }
    });
    if (mounted) setState(() => _busy = false);
  }

  Widget _kart(_Kullanim k, IconData ikon, String baslik, String aciklama, {bool onerilen = false}) {
    final cs = Theme.of(context).colorScheme;
    final secili = _secim == k;
    return Card(
      color: secili ? cs.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: secili ? cs.primary : Colors.transparent, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _secim = k),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: secili ? cs.primary : cs.surfaceContainerHighest,
                child: Icon(ikon, color: secili ? cs.onPrimary : cs.onSurfaceVariant),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(baslik,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                        if (onerilen) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.amber, borderRadius: BorderRadius.circular(10)),
                            child: const Text('Yeni',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(aciklama, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              Icon(secili ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: secili ? cs.primary : null),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hoş geldiniz'),
        actions: const [LogoutButton()],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 32 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Adınız Soyadınız',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 20),
          Text('Uygulamayı nasıl kullanacaksınız?',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _kart(_Kullanim.bireysel, Icons.self_improvement, 'Kendimi takip edeceğim',
              'Bireysel öğrenci: LGS, YKS, KPSS ya da AGS hazırlığımı, denemelerimi, ÖSYM '
                  'sonuçlarımı ve eksik konularımı kendim takip ederim.',
              onerilen: true),
          _kart(_Kullanim.davetli, Icons.vpn_key_outlined, 'Öğrenciyim, davet kodum var',
              'Velim ya da öğretmenim beni ekledi; 6 haneli kodla bağlanacağım.'),
          _kart(_Kullanim.veli, Icons.family_restroom, 'Veliyim',
              'Çocuklarımı ekler; ödevlerini, sınavlarını ve çalışmalarını takip ederim.'),
          _kart(_Kullanim.ogretmen, Icons.co_present_outlined, 'Öğretmen / eğitim koçuyum',
              'Velilerin ya da öğrencilerin paylaştığı davet koduyla öğrencilerimi eklerim.'),
          if (_secim == _Kullanim.bireysel) ...[
            const SizedBox(height: 16),
            Text('Seni tanıyalım', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            OgrenciAyarFormu(ayarlar: _ayar, sekmeler: false),
          ],
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : _save,
            child: Text(_secim == _Kullanim.bireysel ? 'Başla' : 'Devam Et'),
          ),
        ],
      ),
    );
  }
}
