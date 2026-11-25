import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../servisler/bildirim_servisi.dart';
import '../tema/tema.dart';

IconData bildirimIkonu(BildirimTuru t) => switch (t) {
      BildirimTuru.sure => Icons.timer_outlined,
      BildirimTuru.durusma => Icons.account_balance_outlined,
      BildirimTuru.tebligat => Icons.mail_outline,
      BildirimTuru.mesaj => Icons.chat_bubble_outline,
      BildirimTuru.talep => Icons.description_outlined,
      BildirimTuru.sozlesme => Icons.article_outlined,
      BildirimTuru.icra => Icons.gavel_outlined,
      BildirimTuru.sistem => Icons.info_outline,
    };

Color bildirimRengi(BildirimOnceligi o) => switch (o) {
      BildirimOnceligi.kritik => Renkler.kritik,
      BildirimOnceligi.uyari => Renkler.uyari,
      BildirimOnceligi.bilgi => Renkler.bilgi,
    };

class BildirimPaneli extends StatelessWidget {
  const BildirimPaneli({super.key, required this.servis, required this.ac});

  final BildirimServisi servis;
  final ValueChanged<HedefliBildirim> ac;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: Alignment.topRight,
      insetPadding: const EdgeInsets.only(top: 72, right: 16, left: 16, bottom: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 620),
        child: ListenableBuilder(
          listenable: servis,
          builder: (context, _) {
            final liste = servis.topla();
            final okunmamis = servis.kutu.okunmamis(liste.map((h) => h.bildirim));
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(children: [
                  Expanded(child: Text('Bildirimler', style: Theme.of(context).textTheme.titleLarge)),
                  if (okunmamis > 0)
                    TextButton(
                      key: const Key('bildirim-tumunu-oku'),
                      onPressed: servis.tumunuOku,
                      child: const Text('Tümünü okundu say'),
                    ),
                ]),
              ),
              const Divider(height: 1),
              if (liste.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Text('Yeni bildirim yok.'))
              else
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final h in liste)
                      ListTile(
                        key: Key('bildirim-${h.bildirim.id}'),
                        leading: Icon(bildirimIkonu(h.bildirim.tur), color: bildirimRengi(h.bildirim.oncelik)),
                        title: Text(
                          h.bildirim.baslik,
                          style: TextStyle(
                              fontWeight: servis.kutu.okunduMu(h.bildirim) ? FontWeight.w400 : FontWeight.w700),
                        ),
                        subtitle: Text('${h.bildirim.tur.ad} · ${h.bildirim.aciklama} · ${tarihSaat(h.bildirim.zaman)}'),
                        onTap: () {
                          servis.oku(h.bildirim.id);
                          Navigator.of(context).pop();
                          ac(h);
                        },
                      ),
                  ]),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Telefon bildirimleri içerik taşımaz; ayrıntıyı yalnızca uygulamada görürsünüz.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
