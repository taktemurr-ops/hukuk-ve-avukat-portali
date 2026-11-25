import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/kimlik_servisi.dart';
import '../servisler/veri_deposu.dart';
import '../tema/tema.dart';
import 'hesap_ekranlari.dart';

/// Müvekkilin gördüğü portal. Yalnızca davetle erişilir; büro hangi dosya ve belgeleri
/// paylaşırsa yalnızca onları gösterir. Süreler, görevler, iç notlar ve ekip bilgisi gösterilmez.
class MuvekkilPortaliEkrani extends StatefulWidget {
  const MuvekkilPortaliEkrani({super.key, required this.oturum, required this.cikisYap, this.depo, this.sifreDegistir});

  final Oturum oturum;
  final VoidCallback cikisYap;
  final BellekVeriDeposu? depo;

  /// Sunucu bağlıyken şifre değiştirme (eski, yeni) → hata ya da null; demoda yok.
  final Future<String?> Function(String eski, String yeni)? sifreDegistir;

  @override
  State<MuvekkilPortaliEkrani> createState() => _MuvekkilPortaliEkraniState();
}

class _MuvekkilPortaliEkraniState extends State<MuvekkilPortaliEkrani> {
  late final BellekVeriDeposu _depo =
      widget.depo ?? BellekVeriDeposu.demo(kiraciId: widget.oturum.kiraciId, avukatId: 'demo-av1');

  @override
  void initState() {
    super.initState();
    _depo.aktifKullanici = widget.oturum.kullaniciId;
    _depo.okumaKaydet(DenetimIslemi.girisBasarili, 'muvekkil_portali', widget.oturum.kullaniciId, widget.oturum.eposta);
  }

  @override
  void dispose() {
    if (widget.depo == null) _depo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kisiId = widget.oturum.muvekkilKisiId!;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Renkler.lacivert,
        foregroundColor: Colors.white,
        toolbarHeight: 72,
        title: Row(children: [
          const Logo(),
          const SizedBox(width: 16),
          Flexible(
            child: Text('${widget.oturum.kurumAdi} · Müvekkil portalı',
                overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: Text(widget.oturum.adSoyad, style: const TextStyle(color: Colors.white70))),
          ),
          if (widget.sifreDegistir != null)
            IconButton(
              key: const Key('portal-sifre'),
              tooltip: 'Şifre değiştir',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SifreDegistirEkrani(kaydet: (eski, yeni, tekrar) async {
                  final h = Dogrulayicilar.sifre(yeni, eposta: widget.oturum.eposta) ??
                      (yeni != tekrar ? 'Yeni şifreler aynı değil.' : null) ??
                      (eski == yeni ? 'Yeni şifre eskisiyle aynı olamaz.' : null);
                  return h ?? await widget.sifreDegistir!(eski, yeni);
                }),
              )),
              icon: const Icon(Icons.password),
            ),
          IconButton(
            key: const Key('portal-cikis'),
            tooltip: 'Çıkış yap',
            onPressed: widget.cikisYap,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _depo,
        builder: (context, _) {
          final ozetler = _depo.muvekkilOzetleri(kisiId);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('Dosyalarım', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text('Avukatınızın sizinle paylaştığı dosyalar, belgeler ve yazışmalar.',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  if (ozetler.isEmpty)
                    const Panel(child: Text('Henüz sizinle paylaşılan bir dosya yok.'))
                  else
                    for (final o in ozetler)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          child: ListTile(
                            key: Key('portal-dosya-${o.dosyaId}'),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            leading: const Icon(Icons.folder_outlined, color: Renkler.yesil),
                            title: Text(o.baslik, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text([
                              '${o.tur} · ${o.asama}',
                              if (o.mahkeme != null) '${o.mahkeme}${o.esasNo == null ? '' : ' · ${o.esasNo}'}',
                              if (o.sonrakiDurusma != null) 'Sonraki duruşma: ${tarihSaat(o.sonrakiDurusma!)}',
                            ].join('\n')),
                            isThreeLine: true,
                            trailing: o.okunmamis > 0
                                ? Badge(
                                    label: Text('${o.okunmamis}'),
                                    child: const Icon(Icons.mail_outline),
                                  )
                                : const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) =>
                                    MuvekkilDosyaEkrani(depo: _depo, muvekkilKisiId: kisiId, dosyaId: o.dosyaId))),
                          ),
                        ),
                      ),
                  const SizedBox(height: 12),
                  Text(
                    'Bu portal yalnızca bilgilendirme amaçlıdır ve davetle erişilir. Bilgileriniz yalnızca '
                    'Türkiye\'deki sunucularda saklanır. Acil konularda avukatınızı telefonla arayın.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class MuvekkilDosyaEkrani extends StatefulWidget {
  const MuvekkilDosyaEkrani({super.key, required this.depo, required this.muvekkilKisiId, required this.dosyaId});

  final BellekVeriDeposu depo;
  final String muvekkilKisiId;
  final String dosyaId;

  @override
  State<MuvekkilDosyaEkrani> createState() => _MuvekkilDosyaEkraniState();
}

class _MuvekkilDosyaEkraniState extends State<MuvekkilDosyaEkrani> {
  @override
  void initState() {
    super.initState();
    widget.depo.okumaKaydet(DenetimIslemi.goruntuleme, 'dosya', widget.dosyaId, 'Müvekkil portalından');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final okunmamisVar = widget.depo.dosyaMesajlari(widget.dosyaId).any((m) => !m.muvekkildenMi && !m.okundu);
      if (!okunmamisVar) return;
      widget.depo.mesajIslemi(
        sunucuda: (u) => u.mesajlariOku(widget.dosyaId),
        yerelde: () {
          widget.depo.mesajlariOku(widget.dosyaId, muvekkilOkuyor: true);
          return null;
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final depo = widget.depo;
    return ListenableBuilder(
      listenable: depo,
      builder: (context, _) {
        MuvekkilDosyaOzeti? o;
        for (final x in depo.muvekkilOzetleri(widget.muvekkilKisiId)) {
          if (x.dosyaId == widget.dosyaId) o = x;
        }
        final ozet = o;
        if (ozet == null) {
          return const Scaffold(body: Center(child: Text('Bu dosya artık sizinle paylaşılmıyor.')));
        }
        return Scaffold(
          appBar: AppBar(title: Text(ozet.baslik)),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Panel(
                    baslik: 'Dosya bilgisi',
                    sag: DurumRozeti(ozet.asama, RozetTuru.devam),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ozet.tur),
                      if (ozet.mahkeme != null) Text(ozet.mahkeme!),
                      if (ozet.esasNo != null) Text('Esas no: ${ozet.esasNo}'),
                      const SizedBox(height: 8),
                      Text(
                        ozet.sonrakiDurusma == null
                            ? 'Planlanmış duruşma yok.'
                            : 'Sonraki duruşma: ${tarihSaat(ozet.sonrakiDurusma!)} · ${ozet.durusmaYeri ?? ''}',
                        key: const Key('portal-durusma'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  Panel(
                    baslik: 'Belgeler',
                    child: ozet.belgeler.isEmpty
                        ? const Text('Paylaşılan belge yok.')
                        : Column(children: [
                            for (final b in ozet.belgeler)
                              ListTile(
                                key: Key('portal-belge-${b.id}'),
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.description_outlined),
                                title: Text(b.ad),
                                subtitle: Text('${b.dosyaAdi} · ${b.tarih.turkceBicim}'),
                                trailing: IconButton(
                                  tooltip: 'İndir',
                                  icon: const Icon(Icons.download_outlined),
                                  onPressed: () {
                                    depo.okumaKaydet(DenetimIslemi.indirme, 'belge', b.id, 'Müvekkil portalından');
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                        content: Text('İndirme, sunucu bağlandığında çalışacak (önizleme).')));
                                  },
                                ),
                              ),
                          ]),
                  ),
                  const SizedBox(height: 20),
                  Panel(
                    baslik: 'Avukatınızla yazışma',
                    child: MesajAkisi(
                      depo: depo,
                      dosyaId: ozet.dosyaId,
                      muvekkilTarafi: true,
                      muvekkilKisiId: widget.muvekkilKisiId,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Dosya bazlı mesaj akışı ve yanıt alanı; hem müvekkil hem büro tarafında kullanılır.
class MesajAkisi extends StatefulWidget {
  const MesajAkisi({
    super.key,
    required this.depo,
    required this.dosyaId,
    required this.muvekkilTarafi,
    this.muvekkilKisiId,
  });

  final BellekVeriDeposu depo;
  final String dosyaId;
  final bool muvekkilTarafi;
  final String? muvekkilKisiId;

  @override
  State<MesajAkisi> createState() => _MesajAkisiState();
}

class _MesajAkisiState extends State<MesajAkisi> {
  final _metin = TextEditingController();
  String? _hata;

  @override
  void dispose() {
    _metin.dispose();
    super.dispose();
  }

  Future<void> _gonder() async {
    final metin = _metin.text;
    final hata = PortalMesaji.dogrula(metin) ??
        await widget.depo.mesajIslemi(
          sunucuda: (u) => u.mesajGonder(widget.dosyaId, metin),
          yerelde: () => widget.depo.mesajGonder(
            dosyaId: widget.dosyaId,
            metin: metin,
            muvekkildenMi: widget.muvekkilTarafi,
            muvekkilKisiId: widget.muvekkilKisiId,
          ),
        );
    if (!mounted) return;
    setState(() {
      _hata = hata;
      if (hata == null) _metin.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mesajlar = widget.depo.dosyaMesajlari(widget.dosyaId);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (mesajlar.isEmpty) const Text('Henüz mesaj yok.'),
      for (final m in mesajlar)
        Align(
          alignment: m.muvekkildenMi == widget.muvekkilTarafi ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: m.muvekkildenMi == widget.muvekkilTarafi ? Renkler.yesilZemin : Renkler.krem,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Renkler.kenar),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.metin),
              const SizedBox(height: 4),
              Text(
                '${m.muvekkildenMi ? (widget.muvekkilTarafi ? 'Siz' : 'Müvekkil') : (widget.muvekkilTarafi ? 'Avukatınız' : widget.depo.kullaniciAdi(m.gonderen))}'
                ' · ${tarihSaat(m.zaman)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
          ),
        ),
      const SizedBox(height: 8),
      TextField(
        key: Key(widget.muvekkilTarafi ? 'portal-mesaj' : 'buro-mesaj'),
        controller: _metin,
        minLines: 1,
        maxLines: 5,
        maxLength: PortalMesaji.azamiUzunluk,
        decoration: InputDecoration(
          hintText: widget.muvekkilTarafi ? 'Avukatınıza mesaj yazın' : 'Müvekkile yanıt yazın',
          errorText: _hata,
          counterText: '',
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          key: Key(widget.muvekkilTarafi ? 'portal-gonder' : 'buro-gonder'),
          onPressed: _gonder,
          icon: const Icon(Icons.send, size: 18),
          label: const Text('Gönder'),
        ),
      ),
    ]);
  }
}

/// Büro tarafında dosya detayındaki portal yönetimi: paylaşım anahtarı ve müvekkil yazışması.
class PortalYonetimBolumu extends StatelessWidget {
  const PortalYonetimBolumu({super.key, required this.depo, required this.dosyaId});

  final BellekVeriDeposu depo;
  final String dosyaId;

  @override
  Widget build(BuildContext context) {
    final muvekkil = depo.dosyaMuvekkili(dosyaId);
    final paylasildi = depo.portaldaMi(dosyaId);
    final okunmamis = depo.okunmamisMuvekkilMesaji(dosyaId);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Müvekkil portalı', style: Theme.of(context).textTheme.titleMedium)),
        if (okunmamis > 0) DurumRozeti('$okunmamis yeni mesaj', RozetTuru.uyari),
      ]),
      if (muvekkil == null)
        const ListTile(title: Text('Bu dosyada müvekkil kaydı yok; portalda paylaşılamaz.'))
      else ...[
        SwitchListTile(
          key: const Key('portal-paylas'),
          contentPadding: EdgeInsets.zero,
          value: paylasildi,
          onChanged: (v) async {
            final h = await depo.sunucudaVeyaYerelde(
              sunucuda: (u) => u.portalPaylas(dosyaId, v),
              yerelde: () {
                depo.portalPaylas(dosyaId, v);
                return null;
              },
            );
            if (h != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(h)));
          },
          title: const Text('Bu dosyayı müvekkil portalında paylaş'),
          subtitle: const Text('Müvekkil dosya özetini, duruşma tarihini, paylaştığınız belgeleri ve yazışmaları görür. '
              'Süreler, görevler ve iç notlar görünmez.'),
        ),
        if (paylasildi) ...[
          const SizedBox(height: 8),
          if (okunmamis > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('portal-okundu'),
                onPressed: () => depo.mesajIslemi(
                  sunucuda: (u) => u.mesajlariOku(dosyaId),
                  yerelde: () {
                    depo.mesajlariOku(dosyaId, muvekkilOkuyor: false);
                    return null;
                  },
                ),
                child: const Text('Okundu olarak işaretle'),
              ),
            ),
          MesajAkisi(depo: depo, dosyaId: dosyaId, muvekkilTarafi: false),
        ],
      ],
    ]);
  }
}
