import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/db.dart';
import '../widgets/common.dart';
import 'ogrenci_profil.dart';

/// Yeni hesap açıldıktan sonra ad ve rol seçilir.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, required this.user});

  final User user;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _name = TextEditingController();
  UserRole _role = UserRole.parent;
  bool _busy = false;
  bool _kendiBasina = true;
  final _ayar = OgrenciAyarlari.yeni();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _roleInfo => switch (_role) {
        UserRole.parent =>
          'Çocuklarınızı ekler, ödevlerini ve çalışmalarını takip edersiniz. '
              'Her çocuk için oluşan davet kodunu öğretmenlerle ve çocuğunuzla paylaşırsınız.',
        UserRole.student =>
          'Hedef sınavına (LGS, YKS, KPSS, AGS) göre çalışmanı, deneme ve ÖSYM sonuçlarını, '
              'konu eksiklerini kendin takip edersin. İstersen velin ya da öğretmenin de bağlanır.',
        UserRole.teacher =>
          'Velilerin paylaştığı davet kodlarıyla öğrencilerinizi eklersiniz. '
              'Ödev verebilir, kontrol edebilir ve ilerlemeyi izleyebilirsiniz.',
      };

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showInfo(context, 'Lütfen adınızı yazın.');
      return;
    }
    setState(() => _busy = true);
    final email = widget.user.email ?? '';
    final ogrenci = _role == UserRole.student && _kendiBasina;
    await runSafe(
      context,
      () async {
        await Db.createProfile(
          uid: widget.user.uid,
          name: name,
          email: email,
          role: _role,
        );
        if (ogrenci) {
          await Db.createOwnProfile(
            AppUser(uid: widget.user.uid, name: name, email: email, role: UserRole.student),
            name: name,
            grade: _ayar.sinif,
            ayarlar: _ayar.toMap(),
          );
        }
      },
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil Bilgileri'),
        actions: const [LogoutButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Hoş geldiniz! Birkaç bilgiyle başlayalım.',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Adınız Soyadınız',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Bu uygulamayı kim olarak kullanacaksınız?'),
          const SizedBox(height: 8),
          SegmentedButton<UserRole>(
            segments: UserRole.values
                .map((r) => ButtonSegment<UserRole>(
                      value: r,
                      label: Text(r.label),
                      icon: Icon(roleIcon(r)),
                    ))
                .toList(),
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_roleInfo),
            ),
          ),
          if (_role == UserRole.student) ...[
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: true, label: Text('Kendi başıma'), icon: Icon(Icons.person_outline)),
                ButtonSegment(
                    value: false, label: Text('Davet kodum var'), icon: Icon(Icons.vpn_key_outlined)),
              ],
              selected: {_kendiBasina},
              onSelectionChanged: (v) => setState(() => _kendiBasina = v.first),
            ),
            const SizedBox(height: 16),
            if (_kendiBasina)
              OgrenciAyarFormu(ayarlar: _ayar, sekmeler: false)
            else
              const Text('Devam ettikten sonra velinden ya da öğretmeninden aldığın 6 haneli '
                  'kodu "Kodla katıl" ile yazacaksın.'),
          ],
          const SizedBox(height: 24),
          FilledButton(
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _busy ? null : _save,
            child: const Text('Devam Et'),
          ),
        ],
      ),
    );
  }
}
