import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

/// Kayıt sırasında seçilecek üç hesap türünü ve açılan modülleri gösterir.
class HesapTurleriEkrani extends StatelessWidget {
  const HesapTurleriEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: const [HesapTurleriIcerigi()]);
  }
}

/// Kaydırma içermeyen içerik; başka sayfalara gömülebilir.
class HesapTurleriIcerigi extends StatelessWidget {
  const HesapTurleriIcerigi({super.key});

  @override
  Widget build(BuildContext context) {
    final metin = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Kim olarak kullanacaksınız?', style: metin.titleMedium),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Text('Seçtiğiniz tür; açılan modülleri, hazır rolleri ve fiyatı belirler.'),
        ),
        for (final tur in HesapTuru.values) _HesapTuruKarti(profil: LisansProfili.varsayilan(tur)),
      ],
    );
  }
}

class _HesapTuruKarti extends StatelessWidget {
  const _HesapTuruKarti({required this.profil});

  final LisansProfili profil;

  @override
  Widget build(BuildContext context) {
    final metin = Theme.of(context).textTheme;
    return ExpansionTile(
      title: Text(profil.hesapTuru.ad, style: metin.titleMedium),
      subtitle: Text(profil.hesapTuru.aciklama),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Modüller (${profil.moduller.length})', style: metin.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final m in profil.moduller) Chip(label: Text(m.ad))],
        ),
        const SizedBox(height: 16),
        Text('Hazır roller', style: metin.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final r in profil.roller) Chip(label: Text(r.ad))],
        ),
      ],
    );
  }
}
