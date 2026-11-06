import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Basit çizgi grafik: değerler, alt etiketler ve isteğe bağlı hedef çizgisi.
class CizgiGrafik extends StatelessWidget {
  const CizgiGrafik({
    super.key,
    required this.degerler,
    required this.etiketler,
    this.hedef,
    this.renk,
    this.yukseklik = 180,
    this.ondalik = 0,
  });

  final List<double> degerler;
  final List<String> etiketler;
  final double? hedef;
  final Color? renk;
  final double yukseklik;
  final int ondalik;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: yukseklik,
      child: CustomPaint(
        size: Size.infinite,
        painter: _CizgiBoyayici(
          degerler: degerler,
          etiketler: etiketler,
          hedef: hedef,
          renk: renk ?? cs.primary,
          izgara: cs.outlineVariant,
          yazi: cs.onSurfaceVariant,
          hedefRenk: Colors.orange.shade700,
          ondalik: ondalik,
        ),
      ),
    );
  }
}

class _CizgiBoyayici extends CustomPainter {
  _CizgiBoyayici({
    required this.degerler,
    required this.etiketler,
    required this.hedef,
    required this.renk,
    required this.izgara,
    required this.yazi,
    required this.hedefRenk,
    required this.ondalik,
  });

  final List<double> degerler;
  final List<String> etiketler;
  final double? hedef;
  final Color renk;
  final Color izgara;
  final Color yazi;
  final Color hedefRenk;
  final int ondalik;

  void _metin(Canvas c, String s, Offset o,
      {double boyut = 10, Color? r, bool ortala = true, FontWeight? kalinlik}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(fontSize: boyut, color: r ?? yazi, fontWeight: kalinlik)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, o - Offset(ortala ? tp.width / 2 : 0, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (degerler.isEmpty) return;
    const sol = 34.0, sag = 12.0, ust = 18.0, alt = 22.0;
    final w = size.width - sol - sag;
    final h = size.height - ust - alt;

    var enAz = degerler.reduce(math.min);
    var enCok = degerler.reduce(math.max);
    if (hedef != null) {
      enAz = math.min(enAz, hedef!);
      enCok = math.max(enCok, hedef!);
    }
    final pay = (enCok - enAz).abs() < 1e-6 ? 10.0 : (enCok - enAz) * 0.15;
    enAz -= pay;
    enCok += pay;
    double y(double v) => ust + h - (v - enAz) / (enCok - enAz) * h;
    double x(int i) =>
        degerler.length == 1 ? sol + w / 2 : sol + w * i / (degerler.length - 1);

    final cizgi = Paint()
      ..color = izgara
      ..strokeWidth = 1;
    for (var k = 0; k <= 3; k++) {
      final v = enAz + (enCok - enAz) * k / 3;
      final yy = y(v);
      canvas.drawLine(Offset(sol, yy), Offset(sol + w, yy), cizgi);
      _metin(canvas, v.toStringAsFixed(0), Offset(sol - 16, yy));
    }

    if (hedef != null) {
      final yy = y(hedef!);
      final p = Paint()
        ..color = hedefRenk
        ..strokeWidth = 1.5;
      for (var xx = sol; xx < sol + w; xx += 8) {
        canvas.drawLine(Offset(xx, yy), Offset(math.min(xx + 4, sol + w), yy), p);
      }
      _metin(canvas, 'Hedef', Offset(sol + w - 18, yy - 9),
          r: hedefRenk, kalinlik: FontWeight.w600);
    }

    final yol = Path();
    final alan = Path();
    for (var i = 0; i < degerler.length; i++) {
      final o = Offset(x(i), y(degerler[i]));
      if (i == 0) {
        yol.moveTo(o.dx, o.dy);
        alan.moveTo(o.dx, ust + h);
        alan.lineTo(o.dx, o.dy);
      } else {
        yol.lineTo(o.dx, o.dy);
        alan.lineTo(o.dx, o.dy);
      }
    }
    alan.lineTo(x(degerler.length - 1), ust + h);
    alan.close();
    canvas.drawPath(
        alan,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [renk.withValues(alpha: 0.30), renk.withValues(alpha: 0.02)],
          ).createShader(Rect.fromLTWH(sol, ust, w, h)));
    canvas.drawPath(
        yol,
        Paint()
          ..color = renk
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);

    final adim = math.max(1, (degerler.length / 6).ceil());
    for (var i = 0; i < degerler.length; i++) {
      final o = Offset(x(i), y(degerler[i]));
      canvas.drawCircle(o, 5, Paint()..color = Colors.white);
      canvas.drawCircle(o, 3.5, Paint()..color = renk);
      if (i == degerler.length - 1 || degerler.length <= 8) {
        _metin(canvas, degerler[i].toStringAsFixed(ondalik), o - const Offset(0, 12),
            r: renk, kalinlik: FontWeight.w700);
      }
      if (i < etiketler.length && (i % adim == 0 || i == degerler.length - 1)) {
        _metin(canvas, etiketler[i], Offset(o.dx, size.height - 8));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CizgiBoyayici old) =>
      old.degerler != degerler || old.hedef != hedef || old.renk != renk;
}

/// Ortasında yazı olan yüzde halkası.
class YuzdeHalka extends StatelessWidget {
  const YuzdeHalka({
    super.key,
    required this.oran,
    required this.ust,
    this.alt,
    this.renk,
    this.boyut = 96,
  });

  final double oran; // 0-1
  final String ust;
  final String? alt;
  final Color? renk;
  final double boyut;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = renk ?? cs.primary;
    return SizedBox(
      width: boyut,
      height: boyut,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: boyut,
            height: boyut,
            child: CircularProgressIndicator(
              value: oran.clamp(0, 1).toDouble(),
              strokeWidth: 9,
              strokeCap: StrokeCap.round,
              backgroundColor: r.withValues(alpha: 0.15),
              color: r,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ust,
                  style: TextStyle(
                      fontSize: boyut * 0.2,
                      fontWeight: FontWeight.w800,
                      color: r)),
              if (alt != null)
                Text(alt!,
                    style: TextStyle(fontSize: boyut * 0.11, color: cs.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ders adı + yatay ilerleme çubuğu + sağda değer.
class DersCubugu extends StatelessWidget {
  const DersCubugu({
    super.key,
    required this.ikon,
    required this.ad,
    required this.oran,
    required this.deger,
    required this.renk,
    this.alt,
  });

  final IconData ikon;
  final String ad;
  final double oran;
  final String deger;
  final Color renk;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: renk.withValues(alpha: 0.14),
            child: Icon(ikon, size: 18, color: renk),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(ad,
                            style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text(deger,
                        style: TextStyle(fontWeight: FontWeight.w700, color: renk)),
                  ],
                ),
                const SizedBox(height: 5),
                LinearProgressIndicator(
                  value: oran.clamp(0, 1).toDouble(),
                  minHeight: 8,
                  color: renk,
                  backgroundColor: renk.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                if (alt != null) ...[
                  const SizedBox(height: 3),
                  Text(alt!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Renkli başlık kartı (gradyan arka plan).
class VurguKart extends StatelessWidget {
  const VurguKart({super.key, required this.renk, required this.child});

  final Color renk;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(renk);
    final koyu = hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [renk, koyu],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
              color: renk.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: IconTheme.merge(
            data: const IconThemeData(color: Colors.white), child: child),
      ),
    );
  }
}

/// Doğru / yanlış / boş / net özet satırı (renkli kart içinde kullanılır).
class DybOzet extends StatelessWidget {
  const DybOzet({
    super.key,
    required this.d,
    required this.y,
    required this.b,
    required this.net,
  });

  final int d;
  final int y;
  final int b;
  final double net;

  @override
  Widget build(BuildContext context) {
    Widget kutu(String deger, String etiket) => Expanded(
          child: Column(
            children: [
              Text(deger,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
              Text(etiket,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
            ],
          ),
        );
    return Row(
      children: [
        kutu('$d', 'Doğru'),
        kutu('$y', 'Yanlış'),
        kutu('$b', 'Boş'),
        kutu(net.toStringAsFixed(2), 'Net'),
      ],
    );
  }
}
