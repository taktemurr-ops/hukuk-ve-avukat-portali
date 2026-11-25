import 'package:flutter/material.dart';

import '../tema/tema.dart';

enum RozetTuru { kritik, uyari, onay, devam, notr }

/// "Kritik", "Teyit bekliyor" gibi renkli durum rozeti.
class DurumRozeti extends StatelessWidget {
  const DurumRozeti(this.metin, this.tur, {super.key});

  final String metin;
  final RozetTuru tur;

  @override
  Widget build(BuildContext context) {
    final (zemin, yazi) = switch (tur) {
      RozetTuru.kritik => (Renkler.kritikZemin, Renkler.kritik),
      RozetTuru.uyari => (Renkler.uyariZemin, Renkler.uyari),
      RozetTuru.onay => (Renkler.yesilZemin, Renkler.yesil),
      RozetTuru.devam => (Renkler.bilgiZemin, Renkler.bilgi),
      RozetTuru.notr => (Renkler.notrZemin, Renkler.notr),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: zemin, borderRadius: BorderRadius.circular(8)),
      child: Text(metin, style: TextStyle(color: yazi, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}

/// Logo: altın "H" işareti, ince ayraç ve iki satır ürün adı.
class Logo extends StatelessWidget {
  const Logo({super.key, this.acikZemin = false});

  /// Açık zeminde (giriş ekranı) yazı lacivert olur.
  final bool acikZemin;

  @override
  Widget build(BuildContext context) {
    final yazi = acikZemin ? Renkler.metin : Colors.white;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 34, height: 34, child: CustomPaint(painter: _LogoIsareti())),
        const SizedBox(width: 12),
        Container(width: 1, height: 34, color: yazi.withValues(alpha: 0.35)),
        const SizedBox(width: 12),
        Text(
          'Hukuk ve Avukat\nPortalı',
          style: TextStyle(
            fontFamily: 'SourceSerif4',
            fontWeight: FontWeight.w700,
            fontSize: 17,
            height: 1.1,
            color: yazi,
          ),
        ),
      ],
    );
  }
}

class _LogoIsareti extends CustomPainter {
  const _LogoIsareti();

  @override
  void paint(Canvas canvas, Size s) {
    final boya = Paint()..color = Renkler.altin;
    final w = s.width;
    final h = s.height;
    final ayak = w * 0.26;
    // Sol ve sağ dikmeler
    canvas.drawRRect(RRect.fromLTRBR(0, 0, ayak, h, const Radius.circular(2)), boya);
    canvas.drawRRect(RRect.fromLTRBR(w - ayak, 0, w, h, const Radius.circular(2)), boya);
    // Eğik köprü
    final kopru = Path()
      ..moveTo(ayak, h * 0.62)
      ..lineTo(w - ayak, h * 0.30)
      ..lineTo(w - ayak, h * 0.50)
      ..lineTo(ayak, h * 0.82)
      ..close();
    canvas.drawPath(kopru, boya);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Beyaz, ince kenarlı, başlıklı kart.
class Panel extends StatelessWidget {
  const Panel({super.key, this.baslik, this.sag, required this.child, this.dolgu = const EdgeInsets.all(20)});

  final String? baslik;
  final Widget? sag;
  final Widget child;
  final EdgeInsets dolgu;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: dolgu,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (baslik != null) ...[
              Row(
                children: [
                  Expanded(child: Text(baslik!, style: Theme.of(context).textTheme.titleLarge)),
                  if (sag != null) sag!,
                ],
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Henüz geliştirilmemiş modül için dürüst bilgilendirme sayfası.
class YakindaSayfasi extends StatelessWidget {
  const YakindaSayfasi({super.key, required this.baslik, required this.faz, required this.aciklama, required this.ikon});

  final String baslik;
  final String faz;
  final String aciklama;
  final IconData ikon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Panel(
            child: Column(
              children: [
                Icon(ikon, size: 48, color: Renkler.yesil),
                const SizedBox(height: 12),
                Text(baslik, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                DurumRozeti('Yol haritası: $faz', RozetTuru.devam),
                const SizedBox(height: 12),
                Text(aciklama, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
