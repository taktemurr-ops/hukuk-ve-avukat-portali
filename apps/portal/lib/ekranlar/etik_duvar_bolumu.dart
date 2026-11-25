import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/tasarim.dart';
import '../servisler/veri_deposu.dart';
import '../tema/tema.dart';

/// Dosya detayında etik duvar yönetimi (yalnızca büro sahibi ve yönetici ortak).
/// Engellenen kullanıcı dosyanın varlığını bile göremez: listeler, arama, raporlar ve bildirimler dahil.
class EtikDuvarBolumu extends StatelessWidget {
  const EtikDuvarBolumu({super.key, required this.depo, required this.dosya});

  final BellekVeriDeposu depo;
  final Dosya dosya;

  @override
  Widget build(BuildContext context) {
    final gecmis = depo.etikDuvar.gecmis(dosya.id);
    void mesaj(String? h) {
      if (h != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(h)));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Etik duvar', style: Theme.of(context).textTheme.titleMedium)),
        TextButton.icon(
          key: const Key('etik-duvar-ekle'),
          onPressed: () => showDialog<void>(context: context, builder: (_) => _EtikDuvarDiyalogu(depo: depo, dosya: dosya)),
          icon: const Icon(Icons.block, size: 18),
          label: const Text('Kullanıcı engelle'),
        ),
      ]),
      Text('Engellenen kullanıcı bu dosyayı hiçbir listede, aramada, raporda veya bildirimde göremez.',
          style: Theme.of(context).textTheme.bodySmall),
      if (gecmis.isEmpty) const ListTile(contentPadding: EdgeInsets.zero, title: Text('Etik duvar yok.')),
      for (final k in gecmis)
        ListTile(
          key: Key('etik-duvar-${k.kullanici}'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(k.aktif ? Icons.block : Icons.history, color: k.aktif ? Renkler.kritik : Renkler.metinIkincil),
          title: Text(depo.kullaniciAdi(k.kullanici)),
          subtitle: Text('${k.gerekce} · ${depo.kullaniciAdi(k.kuran)}, ${k.tarih.turkceBicim}'
              '${k.aktif ? '' : '\nKaldırıldı: ${k.kaldirmaGerekcesi} · ${depo.kullaniciAdi(k.kaldiran!)}, ${k.kaldirmaTarihi!.turkceBicim}'}'),
          isThreeLine: !k.aktif,
          trailing: k.aktif
              ? TextButton(
                  key: Key('etik-duvar-kaldir-${k.kullanici}'),
                  onPressed: () async {
                    final g = await MetinGirisDiyalogu.goster(
                      context,
                      const MetinGirisDiyalogu(
                        baslik: 'Etik duvarı kaldır',
                        etiket: 'Kaldırma gerekçesi',
                        alanAnahtari: Key('etik-kaldir-gerekce'),
                        onayAnahtari: Key('etik-kaldir-onay'),
                      ),
                    );
                    if (g == null || !context.mounted) return;
                    final h = await depo.sunucudaVeyaYerelde(
                      sunucuda: (u) => u.etikDuvarKaldir(dosya.id, k.kullanici, g),
                      yerelde: () => depo.etikDuvarKaldir(dosya.id, k.kullanici, g),
                    );
                    if (context.mounted) mesaj(h);
                  },
                  child: const Text('Kaldır'),
                )
              : null,
        ),
    ]);
  }
}

class _EtikDuvarDiyalogu extends StatefulWidget {
  const _EtikDuvarDiyalogu({required this.depo, required this.dosya});

  final BellekVeriDeposu depo;
  final Dosya dosya;

  @override
  State<_EtikDuvarDiyalogu> createState() => _EtikDuvarDiyaloguState();
}

class _EtikDuvarDiyaloguState extends State<_EtikDuvarDiyalogu> {
  final _gerekce = TextEditingController();
  String? _kullanici;
  String? _hata;

  @override
  void dispose() {
    _gerekce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engelli = widget.depo.etikDuvar.engelliler(widget.dosya.id);
    final adaylar = widget.depo.kullanicilar.entries
        .where((e) => e.key != widget.depo.aktifKullanici && !engelli.contains(e.key))
        .toList();
    return AlertDialog(
      title: const Text('Etik duvar kur'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          DropdownMenu<String>(
            key: const Key('etik-kullanici'),
            label: const Text('Engellenecek kullanıcı'),
            expandedInsets: EdgeInsets.zero,
            onSelected: (v) => setState(() => _kullanici = v),
            dropdownMenuEntries: [
              for (final e in adaylar)
                DropdownMenuEntry(
                  value: e.key,
                  label: e.value,
                  labelWidget: Text(widget.dosya.tumEkip.contains(e.key) ? '${e.value} (dosya ekibinde)' : e.value),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('etik-gerekce'),
            controller: _gerekce,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Gerekçe (ör. karşı tarafı önceki büroda temsil etti)'),
          ),
          if (_hata != null) ...[
            const SizedBox(height: 8),
            Text(_hata!, key: const Key('etik-hata'), style: const TextStyle(color: Renkler.kritik)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          key: const Key('etik-kaydet'),
          onPressed: () async {
            final k = _kullanici;
            final gerekce = _gerekce.text;
            final h = k == null
                ? 'Kullanıcı seçin.'
                : await widget.depo.sunucudaVeyaYerelde(
                    sunucuda: (u) => u.etikDuvarKur(widget.dosya.id, k, gerekce),
                    yerelde: () => widget.depo.etikDuvarKur(widget.dosya.id, k, gerekce),
                  );
            if (!mounted) return;
            if (h == null) {
              Navigator.pop(context);
            } else {
              setState(() => _hata = h);
            }
          },
          child: const Text('Engelle'),
        ),
      ],
    );
  }
}
