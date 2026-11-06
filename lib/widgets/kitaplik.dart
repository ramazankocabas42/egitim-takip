import 'package:flutter/material.dart';

/// Kitaplık durum seçici: Almayı düşündüklerim / Devam edenler / Tamamlananlar.
class DurumSecici extends StatelessWidget {
  const DurumSecici({
    super.key,
    required this.secili,
    required this.sayilar,
    required this.degisti,
  });

  final String secili;
  final Map<String, int> sayilar;
  final ValueChanged<String> degisti;

  @override
  Widget build(BuildContext context) {
    ButtonSegment<String> seg(String k, String ad, IconData ikon) => ButtonSegment(
          value: k,
          icon: Icon(ikon, size: 18),
          label: Text('$ad (${sayilar[k] ?? 0})',
              maxLines: 1, overflow: TextOverflow.ellipsis),
        );
    return SegmentedButton<String>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        seg('istek', 'Alınacak', Icons.bookmark_add_outlined),
        seg('devam', 'Devam', Icons.auto_stories_outlined),
        seg('bitti', 'Biten', Icons.emoji_events_outlined),
      ],
      selected: {secili},
      onSelectionChanged: (s) => degisti(s.first),
    );
  }
}

/// Menü öğeleri: kitabı diğer durumlara taşı.
List<PopupMenuEntry<String>> durumMenuOgeleri(String mevcut) => [
      if (mevcut != 'istek')
        const PopupMenuItem(
            value: 'durum:istek', child: Text('Almayı düşündüklerime taşı')),
      if (mevcut != 'devam')
        const PopupMenuItem(value: 'durum:devam', child: Text('Devam edenlere taşı')),
      if (mevcut != 'bitti')
        const PopupMenuItem(value: 'durum:bitti', child: Text('Tamamlandı olarak işaretle')),
    ];
