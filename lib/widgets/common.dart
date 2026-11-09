import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';

// ---------------------------------------------------------------------------
// Sabitler
// ---------------------------------------------------------------------------
/// Açık öğrencinin kendi seçtiği dersler (boşsa genel liste kullanılır).
class DersAyari {
  DersAyari._();
  static List<String> aktif = const [];

  /// Açık olan öğrencinin sınıfı ve hedef sınavı (hazır kitap listeleri buna göre süzülür).
  static String sinif = '';
  static String hedef = '';
  static List<String> secenekler([String? mevcut]) {
    final l = aktif.isEmpty ? subjects : [...aktif, 'Genel / Karma', 'Diğer'];
    return [
      ...{...l, if (mevcut != null && mevcut.isNotEmpty) mevcut},
    ];
  }
}

const subjects = <String>[
  'Türkçe',
  'Matematik',
  'Fen Bilimleri',
  'Sosyal Bilgiler',
  'T.C. İnkılap Tarihi',
  'Din Kültürü',
  'İngilizce',
  'Edebiyat',
  'Fizik',
  'Kimya',
  'Biyoloji',
  'Tarih',
  'Coğrafya',
  'Felsefe',
  'Hayat Bilgisi',
  'Genel / Karma',
  'Diğer',
];

const grades = <String>[
  'Okul Öncesi',
  '1. Sınıf',
  '2. Sınıf',
  '3. Sınıf',
  '4. Sınıf',
  '5. Sınıf',
  '6. Sınıf',
  '7. Sınıf',
  '8. Sınıf',
  '9. Sınıf',
  '10. Sınıf',
  '11. Sınıf',
  '12. Sınıf',
  'Mezun',
  'Üniversite Öğrencisi',
  'Üniversite Mezunu',
];

/// 8. sınıf ve altı mı (LGS dönemi)?
bool ortaokulVeAlti(String g) {
  final i = grades.indexOf(g);
  return i >= 0 && i <= grades.indexOf('8. Sınıf');
}

/// Okula gitmeyen (mezun / üniversite) mi?
bool okulDisi(String g) => g == 'Mezun' || g.startsWith('Üniversite');

IconData roleIcon(UserRole r) => switch (r) {
      UserRole.parent => Icons.family_restroom,
      UserRole.student => Icons.backpack_outlined,
      UserRole.teacher => Icons.school_outlined,
    };

// ---------------------------------------------------------------------------
// Tarih biçimleri
// ---------------------------------------------------------------------------
String fmtDate(DateTime? d) =>
    d == null ? '-' : DateFormat('d MMMM y', 'tr_TR').format(d);
String fmtShort(DateTime? d) =>
    d == null ? '-' : DateFormat('d MMM', 'tr_TR').format(d);
String fmtDateTime(DateTime? d) =>
    d == null ? '-' : DateFormat('d MMM HH:mm', 'tr_TR').format(d);

DateTime today() => DateUtils.dateOnly(DateTime.now());

// ---------------------------------------------------------------------------
// Hata ve bilgi mesajları
// ---------------------------------------------------------------------------
String errorText(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-email':
        return 'E-posta adresi geçersiz.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'E-posta veya şifre hatalı.';
      case 'email-already-in-use':
        return 'Bu e-posta ile zaten bir hesap var. Giriş yapmayı deneyin.';
      case 'weak-password':
        return 'Şifre en az 6 karakter olmalı.';
      case 'too-many-requests':
        return 'Çok fazla deneme yapıldı. Biraz sonra tekrar deneyin.';
      case 'network-request-failed':
        return 'İnternet bağlantısı yok.';
    }
    return e.message ?? e.code;
  }
  if (e is FirebaseException) {
    switch (e.code) {
      case 'permission-denied':
        return 'Bu işlem için yetkiniz yok.';
      case 'unavailable':
        return 'Sunucuya ulaşılamıyor. İnternet bağlantınızı kontrol edin.';
    }
    return e.message ?? e.code;
  }
  return e.toString().replaceFirst('Exception: ', '');
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(errorText(e)),
    backgroundColor: Theme.of(context).colorScheme.error,
  ));
}

void showInfo(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// Bir işlemi çalıştırır; hata olursa kullanıcıya gösterir.
Future<bool> runSafe(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final errorColor = Theme.of(context).colorScheme.error;
  try {
    await action();
    if (success != null) {
      messenger.showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (e) {
    messenger.showSnackBar(
        SnackBar(content: Text(errorText(e)), backgroundColor: errorColor));
    return false;
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String ok = 'Evet',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

int? parseInt(String s) => int.tryParse(s.trim());

// ---------------------------------------------------------------------------
// Canlı veri yardımcısı
// ---------------------------------------------------------------------------
/// Bir Firestore akışını dinleyip son değeri saklar.
/// Sekmeler arası geçişte ve kaydırmada veri kaybolmasın diye kullanılır.
class LiveValue<T> extends ChangeNotifier {
  LiveValue(Stream<T> stream) {
    _sub = stream.listen(
      (v) {
        value = v;
        error = null;
        notifyListeners();
      },
      onError: (Object e) {
        error = e;
        notifyListeners();
      },
    );
  }

  T? value;
  Object? error;
  late final StreamSubscription<T> _sub;

  bool get loading => value == null && error == null;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Ortak görsel parçalar
// ---------------------------------------------------------------------------
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: cs.outline),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: c),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Basit sütun grafik (harici paket gerektirmez).
class MiniBars extends StatelessWidget {
  const MiniBars({
    super.key,
    required this.values,
    required this.labels,
    this.height = 90,
    this.decimals = 0,
  });

  final List<double> values;
  final List<String> labels;
  final double height;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxV = values.fold<double>(0, (a, b) => b > a ? b : a);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(values.length, (i) {
            final v = values[i];
            final h = maxV <= 0 ? 2.0 : (v / maxV * height).clamp(2.0, height);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(v == 0 ? '' : v.toStringAsFixed(decimals),
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 2),
                    Container(
                      height: h.toDouble(),
                      decoration: BoxDecoration(
                        color: v == 0 ? cs.surfaceContainerHighest : cs.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Alttan açılan form sayfalarının ortak iskeleti.
class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, 24 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

Future<T?> openSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => child,
    );

class SubjectDropdown extends StatelessWidget {
  const SubjectDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Ders',
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: DersAyari.secenekler(value)
          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Çıkış yap',
      icon: const Icon(Icons.logout),
      onPressed: () => cikisYap(context),
    );
  }
}

Future<void> cikisYap(BuildContext context) async {
  final ok = await confirm(context,
      title: 'Çıkış yap', message: 'Hesabınızdan çıkmak istiyor musunuz?', ok: 'Çıkış yap');
  if (!ok || !context.mounted) return;
  Navigator.of(context).popUntil((r) => r.isFirst);
  await FirebaseAuth.instance.signOut();
}
