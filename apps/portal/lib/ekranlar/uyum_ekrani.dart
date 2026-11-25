import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/kurumsal_depo.dart';
import '../tema/tema.dart';

String _sureMetni(Duration d) {
  if (d.isNegative) return '${-d.inHours} saat geçti';
  return d.inHours >= 1 ? '${d.inHours} saat ${d.inMinutes % 60} dk kaldı' : '${d.inMinutes} dk kaldı';
}

class UyumEkrani extends StatelessWidget {
  const UyumEkrani({super.key, required this.kurumsal});

  final KurumsalDepo kurumsal;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Uyum ve iç soruşturma'),
          automaticallyImplyLeading: false,
          bottom: const TabBar(tabs: [
            Tab(key: Key('uyum-sekme-ihbar'), text: 'İhbarlar'),
            Tab(key: Key('uyum-sekme-sorusturma'), text: 'Soruşturmalar'),
            Tab(key: Key('uyum-sekme-ihlal'), text: 'Veri ihlalleri'),
          ]),
        ),
        body: ListenableBuilder(
          listenable: kurumsal,
          builder: (context, _) => TabBarView(children: [
            _IhbarSekmesi(k: kurumsal),
            _SorusturmaSekmesi(k: kurumsal),
            _IhlalSekmesi(k: kurumsal),
          ]),
        ),
      ),
    );
  }
}

class _IhbarSekmesi extends StatelessWidget {
  const _IhbarSekmesi({required this.k});
  final KurumsalDepo k;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('ihbar-yeni'),
        onPressed: () => showDialog<void>(context: context, builder: (_) => _IhbarDiyalogu(k: k)),
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('İhbar kaydet'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 96), children: [
        Text('İhbar içeriği yalnızca soruşturma ekibine açılır. Bu listede kategori, kanal ve durum görünür.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final i in k.ihbarlar.reversed)
          Card(
            child: ListTile(
              key: Key('ihbar-${i.id}'),
              leading: const Icon(Icons.campaign_outlined),
              title: Text(i.kategori.ad),
              subtitle: Text('${tarihSaat(i.zaman)} · ${i.kanal.ad} · ${i.anonim ? 'anonim' : 'kimliği belli'}'),
              trailing: () {
                final s = k.sorusturmaOf(i.id);
                if (s == null) {
                  return OutlinedButton(
                    key: Key('sorusturma-ac-${i.id}'),
                    onPressed: () => showDialog<void>(context: context, builder: (_) => _SorumluDiyalogu(k: k, ihbar: i)),
                    child: const Text('Soruşturma aç'),
                  );
                }
                return DurumRozeti(s.durum.ad, s.durum.acik ? RozetTuru.devam : RozetTuru.notr);
              }(),
            ),
          ),
      ]),
    );
  }
}

class _SorusturmaSekmesi extends StatelessWidget {
  const _SorusturmaSekmesi({required this.k});
  final KurumsalDepo k;

  @override
  Widget build(BuildContext context) {
    final simdi = DateTime.now();
    final erisilen = k.sorusturmalar.where((s) => s.erisebilir(k.kullaniciId)).toList();
    final digerleri = k.sorusturmalar.length - erisilen.length;
    return ListView(padding: const EdgeInsets.all(24), children: [
      if (digerleri > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('$digerleri soruşturmaya erişiminiz yok; içerikleri yalnızca ekipleri görür.',
              key: const Key('sorusturma-erisim-yok'), style: Theme.of(context).textTheme.bodySmall),
        ),
      if (erisilen.isEmpty) const Text('Ekibinde olduğunuz soruşturma yok.'),
      for (final s in erisilen)
        Card(
          child: ListTile(
            key: Key('sorusturma-${s.id}'),
            title: Text('${s.ihbar.kategori.ad} · ${s.durum.ad}'),
            subtitle: Text('Sorumlu ${k.kisiAdi(s.sorumlu)} · açılış ${tarihSaat(s.acilis)}'
                '${s.geriBildirimGecikti(simdi) ? ' · ihbarcıya geri bildirim gecikti' : ''}'
                '${s.sonucGecikti(simdi) ? ' · sonuç süresi aşıldı' : ''}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => SorusturmaDetayEkrani(k: k, sorusturmaId: s.id))),
          ),
        ),
    ]);
  }
}

class SorusturmaDetayEkrani extends StatelessWidget {
  const SorusturmaDetayEkrani({super.key, required this.k, required this.sorusturmaId});

  final KurumsalDepo k;
  final String sorusturmaId;

  void _m(BuildContext c, String? h) {
    if (h != null) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(h)));
  }

  Future<String?> _metin(BuildContext c, String baslik, String etiket, String anahtar) => MetinGirisDiyalogu.goster(
        c,
        MetinGirisDiyalogu(baslik: baslik, etiket: etiket, alanAnahtari: Key(anahtar), onayAnahtari: Key('$anahtar-kaydet')),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: k,
      builder: (context, _) {
        final s = k.sorusturmalar.where((x) => x.id == sorusturmaId).firstOrNull;
        if (s == null || !s.erisebilir(k.kullaniciId)) {
          return const Scaffold(body: Center(child: Text('Bu soruşturmaya erişim yetkiniz yok.')));
        }
        final u = k.kullaniciId;
        return Scaffold(
          appBar: AppBar(title: Text('Soruşturma · ${s.ihbar.kategori.ad}')),
          body: ListView(padding: const EdgeInsets.all(24), children: [
            Panel(
              baslik: 'İhbar',
              sag: DurumRozeti(s.durum.ad, s.durum.acik ? RozetTuru.devam : RozetTuru.notr),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.ihbar.aciklama),
                const SizedBox(height: 8),
                Text('Takip kodu: ${s.ihbar.takipKodu} · ${s.ihbar.kanal.ad} · ${tarihSaat(s.ihbar.zaman)}',
                    style: Theme.of(context).textTheme.bodySmall),
                Text('İhbarcıya ilk geri bildirim: ${s.ilkGeriBildirim == null ? 'en geç ${tarihSaat(s.geriBildirimSonu)}' : tarihSaat(s.ilkGeriBildirim!)}'
                    ' · sonuç hedefi ${tarihSaat(s.sonucSonu)}',
                    style: Theme.of(context).textTheme.bodySmall),
                Text('Ekip: ${[s.sorumlu, ...s.ekip].map(k.kisiAdi).join(', ')}', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (s.ilkGeriBildirim == null && s.durum.acik)
                    OutlinedButton(
                      key: const Key('sor-geri-bildirim'),
                      onPressed: () => _m(context, k.uyumIslemi('İhbarcıya geri bildirim', s.id, () => s.geriBildirimVer(u, DateTime.now()))),
                      child: const Text('Geri bildirim verildi'),
                    ),
                  if (s.durum == SorusturmaDurumu.onInceleme) ...[
                    FilledButton(
                      key: const Key('sor-sorusturmaya-al'),
                      onPressed: () => _m(context, k.uyumIslemi('Soruşturmaya alındı', s.id, () => s.sorusturmayaAl(u))),
                      child: const Text('Soruşturmaya al'),
                    ),
                    OutlinedButton(
                      key: const Key('sor-reddet'),
                      onPressed: () async {
                        final g = await _metin(context, 'Ön incelemede reddet', 'Gerekçe', 'sor-ret');
                        if (g != null && context.mounted) {
                          _m(context, k.uyumIslemi('Reddedildi', s.id, () => s.reddet(u, g)));
                        }
                      },
                      child: const Text('Reddet'),
                    ),
                  ],
                  if (s.durum == SorusturmaDurumu.sorusturma)
                    FilledButton(
                      key: const Key('sor-raporla'),
                      onPressed: () => _m(context, k.uyumIslemi('Raporlamaya geçildi', s.id, () => s.raporlamayaGec(u))),
                      child: const Text('Raporlamaya geç'),
                    ),
                  if (s.durum == SorusturmaDurumu.raporlama)
                    for (final sonuc in SorusturmaSonucu.values)
                      OutlinedButton(
                        key: Key('sor-kapat-${sonuc.name}'),
                        onPressed: () async {
                          final g = await _metin(context, 'Sonuç: ${sonuc.ad}', 'Sonuç özeti ve alınacak önlemler', 'sor-ozet');
                          if (g != null && context.mounted) {
                            _m(context, k.uyumIslemi('Kapatıldı: ${sonuc.ad}', s.id, () => s.kapat(u, sonuc, g)));
                          }
                        },
                        child: Text(sonuc.ad),
                      ),
                ]),
                if (s.sonucOzeti != null) ...[
                  const SizedBox(height: 8),
                  Text('Sonuç: ${s.sonuc?.ad ?? s.durum.ad} · ${s.sonucOzeti}', key: const Key('sor-sonuc')),
                ],
              ]),
            ),
            const SizedBox(height: 20),
            Panel(
              baslik: 'Soruşturma notları',
              sag: s.durum.acik
                  ? TextButton.icon(
                      key: const Key('sor-not-ekle'),
                      onPressed: () async {
                        final g = await _metin(context, 'Not ekle', 'Not', 'sor-not');
                        if (g != null && context.mounted) {
                          _m(context, k.uyumIslemi('Not eklendi', s.id, () => s.notEkle(u, g, DateTime.now())));
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Not'),
                    )
                  : null,
              child: s.notlar.isEmpty
                  ? const Text('Not yok.')
                  : Column(children: [
                      for (final n in s.notlar)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(n.metin),
                          subtitle: Text('${k.kisiAdi(n.kullanici)} · ${tarihSaat(n.zaman)}'),
                        ),
                    ]),
            ),
          ]),
        );
      },
    );
  }
}

class _IhlalSekmesi extends StatelessWidget {
  const _IhlalSekmesi({required this.k});
  final KurumsalDepo k;

  @override
  Widget build(BuildContext context) {
    final simdi = DateTime.now();
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('KVKK Kurulu kararı (2019/10) uyarınca veri ihlali, öğrenildiği andan itibaren en geç 72 saat içinde Kurul\'a bildirilir.',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const Key('ihlal-yeni'),
          onPressed: () async {
            final g = await MetinGirisDiyalogu.goster(
              context,
              const MetinGirisDiyalogu(
                baslik: 'Veri ihlali kaydet (öğrenilme: şimdi)',
                etiket: 'Ne oldu?',
                alanAnahtari: Key('ihlal-aciklama'),
                onayAnahtari: Key('ihlal-kaydet'),
              ),
            );
            if (g != null && g.trim().isNotEmpty) k.ihlalKaydet(g, DateTime.now());
          },
          icon: const Icon(Icons.report_gmailerrorred_outlined),
          label: const Text('Veri ihlali kaydet'),
        ),
      ),
      const SizedBox(height: 12),
      for (final v in k.veriIhlalleri.reversed)
        Card(
          child: ListTile(
            key: Key('ihlal-${v.id}'),
            leading: Icon(Icons.warning_amber_rounded,
                color: v.kurulaBildirim != null
                    ? Renkler.yesil
                    : v.gecikti(simdi)
                        ? Renkler.kritik
                        : Renkler.uyari),
            title: Text(v.aciklama),
            subtitle: Text('Öğrenilme ${tarihSaat(v.ogrenilme)}'
                '${v.etkilenenKisiSayisi == null ? '' : ' · ${v.etkilenenKisiSayisi} kişi'}'
                ' · Kurul bildirimi son: ${tarihSaat(v.kurulSonZaman)}'),
            trailing: v.kurulaBildirim != null
                ? DurumRozeti(v.gecikti(simdi) ? 'Geç bildirildi' : 'Kurul\'a bildirildi',
                    v.gecikti(simdi) ? RozetTuru.uyari : RozetTuru.onay)
                : Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    DurumRozeti(_sureMetni(v.kalan(simdi)), v.gecikti(simdi) ? RozetTuru.kritik : RozetTuru.uyari),
                    FilledButton(
                      key: Key('ihlal-bildir-${v.id}'),
                      onPressed: () => k.uyumIslemi('Kurul\'a bildirildi', v.id, () => v.kurulaBildirildi(DateTime.now())),
                      child: const Text('Bildirildi'),
                    ),
                  ]),
          ),
        ),
    ]);
  }
}

class _IhbarDiyalogu extends StatefulWidget {
  const _IhbarDiyalogu({required this.k});
  final KurumsalDepo k;

  @override
  State<_IhbarDiyalogu> createState() => _IhbarDiyaloguState();
}

class _IhbarDiyaloguState extends State<_IhbarDiyalogu> {
  final _aciklama = TextEditingController();
  IhbarKategorisi _kategori = IhbarKategorisi.diger;
  IhbarKanali _kanal = IhbarKanali.web;
  bool _anonim = true;
  String? _hata;
  Ihbar? _kaydedilen;

  @override
  void dispose() {
    _aciklama.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kayit = _kaydedilen;
    if (kayit != null) {
      return AlertDialog(
        title: const Text('İhbar kaydedildi'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('İhbarcıya iletilecek takip kodu:'),
          const SizedBox(height: 8),
          SelectableText(kayit.takipKodu,
              key: const Key('ihbar-takip-kodu'), style: const TextStyle(fontSize: 22, letterSpacing: 2, fontFamily: 'monospace')),
          const SizedBox(height: 8),
          const Text('Kod kaybolursa yeniden üretilemez; ihbarcı bu kodla durumu izler ve ek bilgi verir.'),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam'))],
      );
    }
    return AlertDialog(
      title: const Text('İhbar kaydet'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownMenu<IhbarKategorisi>(
              key: const Key('ihbar-kategori'),
              label: const Text('Kategori'),
              expandedInsets: EdgeInsets.zero,
              initialSelection: _kategori,
              onSelected: (v) => setState(() => _kategori = v ?? _kategori),
              dropdownMenuEntries: [for (final c in IhbarKategorisi.values) DropdownMenuEntry(value: c, label: c.ad)],
            ),
            const SizedBox(height: 12),
            DropdownMenu<IhbarKanali>(
              label: const Text('Kanal'),
              expandedInsets: EdgeInsets.zero,
              initialSelection: _kanal,
              onSelected: (v) => setState(() => _kanal = v ?? _kanal),
              dropdownMenuEntries: [for (final c in IhbarKanali.values) DropdownMenuEntry(value: c, label: c.ad)],
            ),
            TextField(
              key: const Key('ihbar-aciklama'),
              controller: _aciklama,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'İhbarın içeriği'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _anonim,
              onChanged: (v) => setState(() => _anonim = v),
              title: const Text('Anonim'),
              subtitle: const Text('Anonim ihbarda ihbarcı bilgisi tutulmaz.'),
            ),
            if (_hata != null) Text(_hata!, key: const Key('ihbar-hata'), style: const TextStyle(color: Renkler.kritik)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          key: const Key('ihbar-kaydet'),
          onPressed: () {
            try {
              final i = widget.k.ihbarKaydet(kanal: _kanal, kategori: _kategori, aciklama: _aciklama.text, anonim: _anonim);
              setState(() => _kaydedilen = i);
            } on ArgumentError catch (e) {
              setState(() => _hata = '${e.message}');
            }
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

class _SorumluDiyalogu extends StatefulWidget {
  const _SorumluDiyalogu({required this.k, required this.ihbar});
  final KurumsalDepo k;
  final Ihbar ihbar;

  @override
  State<_SorumluDiyalogu> createState() => _SorumluDiyaloguState();
}

class _SorumluDiyaloguState extends State<_SorumluDiyalogu> {
  String? _sorumlu;
  String? _hata;

  @override
  Widget build(BuildContext context) {
    final k = widget.k;
    return AlertDialog(
      title: const Text('Soruşturma aç'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownMenu<String>(
            key: const Key('sorusturma-sorumlu'),
            label: const Text('Sorumlu'),
            expandedInsets: EdgeInsets.zero,
            onSelected: (v) => setState(() => _sorumlu = v),
            dropdownMenuEntries: [for (final e in k.ekip) DropdownMenuEntry(value: e, label: k.kisiAdi(e))],
          ),
          if (_hata != null) Text(_hata!, key: const Key('sorusturma-hata'), style: const TextStyle(color: Renkler.kritik)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          key: const Key('sorusturma-kaydet'),
          onPressed: () {
            final s = _sorumlu;
            final h = s == null ? 'Sorumlu seçin.' : k.sorusturmaAc(widget.ihbar, s);
            if (h == null) {
              Navigator.pop(context);
            } else {
              setState(() => _hata = h);
            }
          },
          child: const Text('Aç'),
        ),
      ],
    );
  }
}
