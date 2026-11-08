import 'package:flutter/material.dart';

import '../models.dart';
import '../services/db.dart';
import 'common.dart';

/// Sağ üstte hesap menüsü: hesap türünü değiştir, çıkış yap.
class HesapMenusu extends StatelessWidget {
  const HesapMenusu({super.key, required this.me});
  final AppUser me;

  Future<void> _turDegistir(BuildContext context) async {
    final yeni = await showDialog<UserRole>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Hesap türünü değiştir'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Şu an: ${me.role.label}. Bağlı olduğunuz öğrenciler ve kayıtlar silinmez.',
                style: const TextStyle(fontSize: 13)),
          ),
          for (final (r, aciklama) in [
            (UserRole.student, 'Kendimi takip edeceğim ya da davet koduyla bağlanacağım'),
            (UserRole.parent, 'Çocuklarımı ekleyip takip edeceğim'),
            (UserRole.teacher, 'Öğrencilerimi davet koduyla ekleyeceğim'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(roleIcon(r)),
                title: Text(r.label,
                    style: TextStyle(
                        fontWeight: r == me.role ? FontWeight.w800 : FontWeight.w500)),
                subtitle: Text(aciklama),
                trailing: r == me.role ? const Icon(Icons.check) : null,
              ),
            ),
        ],
      ),
    );
    if (yeni == null || yeni == me.role || !context.mounted) return;
    await runSafe(context, () => Db.updateRole(me.uid, yeni),
        success: 'Hesap türü "${yeni.label}" olarak değiştirildi.');
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Hesabım',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (v) async {
        if (v == 'tur') await _turDegistir(context);
        if (v == 'cikis' && context.mounted) await cikisYap(context);
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Text('${me.name} • ${me.role.label}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        const PopupMenuItem(
          value: 'tur',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.swap_horiz),
            title: Text('Hesap türünü değiştir'),
          ),
        ),
        const PopupMenuItem(
          value: 'cikis',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Çıkış yap'),
          ),
        ),
      ],
    );
  }
}
