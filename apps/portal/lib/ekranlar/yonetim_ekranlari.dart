import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/veri_deposu.dart';
import '../tema/tema.dart';

// ============================================================================= Veri aktarımı

/// Excel'den "CSV (noktalı virgülle ayrılmış)" olarak kaydedilen veya kopyalanan
/// müvekkil listesini önizleyip aktarır.
class VeriAktarimEkrani extends StatefulWidget {
  const VeriAktarimEkrani({super.key, required this.depo});

  final BellekVeriDeposu depo;

  @override
  State<VeriAktarimEkrani> createState() => _VeriAktarimEkraniState();
}

class _VeriAktarimEkraniState extends State<VeriAktarimEkrani> {
  final _metin = TextEditingController();
  AktarimOnizlemesi? _onizleme;

  static const _ornek = 'Adı Soyadı;TCKN/VKN;E-posta;Telefon;Adres\n'
      'Zeynep Aydın;;zeynep@ornek.com;0532 000 00 00;Kadıköy İstanbul\n'
      'Yeni Şirket A.Ş.;1234567890;hukuk@yenisirket.com.tr;;Ankara';

  @override
  void dispose() {
    _metin.dispose();
    super.dispose();
  }

  void _onizle() {
    setState(() => _onizleme = KisiAktarimi.onizle(csv: _metin.text, mevcut: widget.depo.kisiler));
  }

  void _aktar() {
    final o = _onizleme!;
    final n = widget.depo.kisileriAktar(o);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$n kişi aktarıldı. Okunan ${o.satirlar.length}, mükerrer ${o.sayi(SatirDurumu.mukerrer)}, '
          'hatalı ${o.sayi(SatirDurumu.hatali)}.'),
    ));
    setState(() {
      _onizleme = null;
      _metin.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final o = _onizleme;
    return Scaffold(
      appBar: AppBar(title: const Text('Veri aktarımı · Müvekkil ve taraflar')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Excel\'de listeyi "CSV (noktalı virgülle ayrılmış)" olarak kaydedip içeriğini buraya yapıştırın '
            'veya hücreleri doğrudan kopyalayın. İlk satır başlık olmalıdır. Hiçbir kayıt önizlemeden önce eklenmez.',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _metin.text = _ornek),
              child: const Text('Örnek veriyle doldur'),
            ),
          ),
          TextField(
            key: const Key('aktarim-metin'),
            controller: _metin,
            minLines: 6,
            maxLines: 14,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Adı Soyadı;TCKN/VKN;E-posta;Telefon;Adres'),
            onChanged: (_) {
              if (_onizleme != null) setState(() => _onizleme = null);
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('aktarim-onizle'),
              onPressed: _onizle,
              icon: const Icon(Icons.preview_outlined),
              label: const Text('Önizle'),
            ),
          ),
          if (o != null) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                DurumRozeti('Okunan ${o.satirlar.length}', RozetTuru.notr),
                DurumRozeti('Aktarılacak ${o.sayi(SatirDurumu.aktarilacak)}', RozetTuru.onay),
                DurumRozeti('Mükerrer ${o.sayi(SatirDurumu.mukerrer)}', RozetTuru.uyari),
                DurumRozeti('Hatalı ${o.sayi(SatirDurumu.hatali)}', RozetTuru.kritik),
                DurumRozeti(o.mutabik ? 'Sayım mutabık' : 'Sayım tutmuyor', o.mutabik ? RozetTuru.onay : RozetTuru.kritik),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Eşlenen sütunlar: ${o.esleme.entries.map((e) => '${e.key.ad} ← "${o.basliklar[e.value]}"').join(', ')}',
              style: const TextStyle(color: Renkler.metinIkincil),
            ),
            const SizedBox(height: 12),
            for (final s in o.satirlar)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  key: Key('aktarim-satir-${s.satirNo}'),
                  leading: Text('${s.satirNo}', style: const TextStyle(color: Renkler.metinIkincil)),
                  title: Text(s.deger(KisiAlani.ad).isEmpty ? '(ad yok)' : s.deger(KisiAlani.ad)),
                  subtitle: Text([
                    s.tur == KisiTuru.gercek ? 'Gerçek kişi' : 'Tüzel kişi',
                    if (s.deger(KisiAlani.kimlikNo).isNotEmpty) s.deger(KisiAlani.kimlikNo),
                    ...s.hatalar,
                    if (s.mukerrerAciklama != null) s.mukerrerAciklama!,
                    ...s.uyarilar,
                  ].join(' · ')),
                  trailing: switch (s.durum) {
                    SatirDurumu.aktarilacak => const DurumRozeti('Aktarılacak', RozetTuru.onay),
                    SatirDurumu.mukerrer => const DurumRozeti('Atlanacak', RozetTuru.uyari),
                    SatirDurumu.hatali => const DurumRozeti('Hatalı', RozetTuru.kritik),
                  },
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: const Key('aktarim-aktar'),
                onPressed: o.sayi(SatirDurumu.aktarilacak) == 0 ? null : _aktar,
                child: Text('${o.sayi(SatirDurumu.aktarilacak)} kişiyi aktar'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================= Denetim kaydı

class DenetimKaydiEkrani extends StatelessWidget {
  const DenetimKaydiEkrani({super.key, required this.depo});

  final BellekVeriDeposu depo;

  @override
  Widget build(BuildContext context) {
    final olaylar = depo.denetim.olaylar.reversed.toList();
    final bozuk = depo.denetim.dogrula();
    return Scaffold(
      appBar: AppBar(title: const Text('Denetim kaydı')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Panel(
            child: Row(
              children: [
                Icon(bozuk == null ? Icons.verified_user_outlined : Icons.gpp_bad_outlined,
                    color: bozuk == null ? Renkler.yesil : Renkler.kritik, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    bozuk == null
                        ? 'Kayıt zinciri sağlam: ${olaylar.length} olay, hiçbiri sonradan değiştirilmemiş veya silinmemiş.'
                        : 'Kayıt zinciri $bozuk. olayda kırılmış! Bu durum yöneticiye ve güvenlik ekibine bildirilmelidir.',
                    key: const Key('denetim-durum'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final o in olaylar)
            ListTile(
              dense: true,
              leading: Text('#${o.sira}', style: const TextStyle(color: Renkler.metinIkincil)),
              title: Text('${o.islem.ad} · ${o.nesneTuru} ${o.nesneId}'),
              subtitle: Text('${tarihSaat(o.zaman.toLocal())} · ${depo.kullaniciAdi(o.kullaniciId)}'
                  '${o.aciklama.isNotEmpty ? ' · ${o.aciklama}' : ''}'),
              trailing: Text(o.ozet.substring(0, 8), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
