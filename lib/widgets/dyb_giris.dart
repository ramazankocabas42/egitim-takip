import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../lgs.dart';

/// Bir dersin doğru / yanlış / boş alanlarını tutar.
class DybDenetleyici extends ChangeNotifier {
  DybDenetleyici([Dyb ilk = Dyb.bos]) {
    ayarla(ilk);
    for (final c in [d, y, b]) {
      c.addListener(notifyListeners);
    }
  }

  final d = TextEditingController();
  final y = TextEditingController();
  final b = TextEditingController();

  static int _n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  Dyb get deger => Dyb(_n(d), _n(y), _n(b));

  void ayarla(Dyb v) {
    d.text = v.d == 0 ? '' : '${v.d}';
    y.text = v.y == 0 ? '' : '${v.y}';
    b.text = v.b == 0 ? '' : '${v.b}';
  }

  @override
  void dispose() {
    d.dispose();
    y.dispose();
    b.dispose();
    super.dispose();
  }
}

/// Üç yan yana sayı kutusu.
class DybAlanlari extends StatelessWidget {
  const DybAlanlari({super.key, required this.denetleyici});

  final DybDenetleyici denetleyici;

  @override
  Widget build(BuildContext context) {
    Widget alan(TextEditingController c, String etiket, Color renk) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, color: renk, fontSize: 18),
            decoration: InputDecoration(
              labelText: etiket,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );
    return Row(
      children: [
        alan(denetleyici.d, 'Doğru', Colors.green.shade700),
        const SizedBox(width: 8),
        alan(denetleyici.y, 'Yanlış', Colors.red.shade700),
        const SizedBox(width: 8),
        alan(denetleyici.b, 'Boş', Colors.grey.shade700),
      ],
    );
  }
}

/// Ders başlığı, anlık net ve D/Y/B alanları olan kart.
class DersDybKart extends StatelessWidget {
  const DersDybKart({
    super.key,
    required this.ders,
    required this.denetleyici,
    this.azami,
  });

  final LgsDers ders;
  final DybDenetleyici denetleyici;

  /// Dersin soru sayısı (denemede); verilirse aşım uyarısı gösterilir.
  final int? azami;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: ListenableBuilder(
          listenable: denetleyici,
          builder: (context, _) {
            final v = denetleyici.deger;
            final asim = azami != null && v.toplam > azami!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: ders.renk.withValues(alpha: 0.14),
                      child: Icon(ders.ikon, color: ders.renk, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(ders.ad,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    Text('${v.net.toStringAsFixed(2)} Net',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: ders.renk)),
                  ],
                ),
                const SizedBox(height: 12),
                DybAlanlari(denetleyici: denetleyici),
                if (azami != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    asim
                        ? 'Toplam ${v.toplam} — bu derste $azami soru var!'
                        : 'Toplam soru: $azami  •  girilen: ${v.toplam}',
                    style: TextStyle(
                        fontSize: 12,
                        color: asim
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
