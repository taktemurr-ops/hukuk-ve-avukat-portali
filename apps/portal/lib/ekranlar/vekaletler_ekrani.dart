import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../servisler/kimlik_servisi.dart';
import '../servisler/veri_deposu.dart';
import 'formlar.dart';

/// Vekâletnameler ve işlem öncesi yetki kontrolü.
class VekaletlerEkrani extends StatefulWidget {
  const VekaletlerEkrani({super.key, required this.depo, required this.oturum});

  final BellekVeriDeposu depo;
  final Oturum oturum;

  @override
  State<VekaletlerEkrani> createState() => _VekaletlerEkraniState();
}

class _VekaletlerEkraniState extends State<VekaletlerEkrani> {
  OzelYetki? _islem;
  VekaletKontrolSonucu? _sonuc;
  String? _seciliId;

  void _kontrolEt(Vekaletname v, String dosyaId) {
    setState(() {
      _seciliId = v.id;
      _sonuc = VekaletKontrolu.kontrolEt(
        vekaletnameler: widget.depo.vekaletnameler,
        muvekkilId: v.muvekkilId,
        avukatId: widget.oturum.kullaniciId,
        dosyaId: dosyaId,
        tarih: Tarih.from(DateTime.now()),
        gerekenYetki: _islem,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final metin = Theme.of(context).textTheme;
    final renkler = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('vekalet-yeni'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<bool>(builder: (_) => VekaletnameFormu(depo: widget.depo, oturum: widget.oturum)),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Yeni vekâletname'),
      ),
      body: ListenableBuilder(listenable: widget.depo, builder: (context, _) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('İşlem öncesi yetki kontrolü', style: metin.titleMedium),
        const SizedBox(height: 4),
        const Text('Feragat, sulh, tahsilat gibi işlemlerden önce vekâletnamede özel yetki olup olmadığını kontrol edin.'),
        const SizedBox(height: 8),
        DropdownMenu<OzelYetki?>(
          key: const Key('vekalet-islem'),
          label: const Text('Yapılacak işlem'),
          expandedInsets: EdgeInsets.zero,
          initialSelection: _islem,
          onSelected: (y) => setState(() {
            _islem = y;
            _sonuc = null;
          }),
          dropdownMenuEntries: [
            const DropdownMenuEntry<OzelYetki?>(value: null, label: 'Olağan işlem (özel yetki gerekmez)'),
            for (final y in OzelYetki.values) DropdownMenuEntry<OzelYetki?>(value: y, label: y.ad),
          ],
        ),
        const SizedBox(height: 16),
        for (final v in widget.depo.vekaletnameler) _vekaletKarti(v, metin, renkler),
        const SizedBox(height: 72),
      ],
    )),
    );
  }

  Widget _vekaletKarti(Vekaletname v, TextTheme metin, ColorScheme renkler) {
    final muvekkil = widget.depo.kisi(v.muvekkilId);
    final dosyaId = v.genel
        ? widget.depo.dosyaKayitlari
                .where((d) => d.kisiId == v.muvekkilId)
                .map((d) => d.dosyaId)
                .firstOrNull ??
            '-'
        : v.dosyalar.first;
    final sonuc = _seciliId == v.id ? _sonuc : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(muvekkil?.ad ?? v.muvekkilId, style: metin.titleMedium),
            Text(
              '${v.genel ? 'Genel' : 'Özel'} vekâletname · ${v.noter ?? '-'} · '
              'Yevmiye ${v.yevmiyeNo ?? '-'} · ${v.duzenlemeTarihi.turkceBicim}',
            ),
            if (v.asilEvrakYeri != null) Text('Asıl evrak: ${v.asilEvrakYeri}', style: metin.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: v.ozelYetkiler.isEmpty
                  ? [const Chip(label: Text('Özel yetki yok'))]
                  : [for (final y in v.ozelYetkiler) Chip(label: Text(y.ad))],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Dosya: $dosyaId', style: metin.bodySmall),
                const Spacer(),
                OutlinedButton(
                  key: Key('vekalet-kontrol-${v.id}'),
                  onPressed: () => _kontrolEt(v, dosyaId),
                  child: const Text('Kontrol et'),
                ),
              ],
            ),
            if (sonuc != null)
              ListTile(
                key: Key('vekalet-sonuc-${v.id}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  sonuc.uygun ? Icons.check_circle : Icons.cancel,
                  color: sonuc.uygun ? renkler.primary : renkler.error,
                ),
                title: Text(sonuc.uygun ? 'Uygun' : 'Uygun değil'),
                subtitle: sonuc.neden == null ? null : Text(sonuc.neden!),
              ),
          ],
        ),
      ),
    );
  }
}
