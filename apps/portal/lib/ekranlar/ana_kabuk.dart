import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/bildirim_servisi.dart';
import '../servisler/kimlik_servisi.dart';
import '../servisler/kurumsal_depo.dart';
import '../servisler/sunucu_senkronu.dart';
import '../servisler/veri_deposu.dart';
import '../tema/tema.dart';
import 'bildirim_paneli.dart';
import 'cikar_catismasi_ekrani.dart';
import 'dis_avukat_ekrani.dart';
import 'dosyalar_ekrani.dart';
import 'finans_ekrani.dart';
import 'genel_bakis_ekrani.dart';
import 'gorev_sablonlari_ekrani.dart';
import 'hesap_ekranlari.dart';
import 'hesap_turleri_ekrani.dart';
import 'hesaplamalar_ekrani.dart';
import 'icra_ekrani.dart';
import 'kvkk_ekrani.dart';
import 'muvekkiller_ekrani.dart';
import 'organizasyon_ekrani.dart';
import 'raporlar_ekrani.dart';
import 'sozlesmeler_ekrani.dart';
import 'sunucu_abonelik_ekrani.dart';
import 'takvim_ekrani.dart';
import 'talepler_ekrani.dart';
import 'uyum_ekrani.dart';
import 'tebligatlar_ekrani.dart';
import 'vekaletler_ekrani.dart';
import 'yonetim_ekranlari.dart';
import 'zaman_ekrani.dart';

enum _B {
  genelBakis,
  talepler,
  dosyalar,
  icra,
  sozlesmeler,
  disAvukatlar,
  organizasyon,
  uyum,
  tebligatlar,
  takvim,
  muvekkiller,
  cikarCatismasi,
  vekaletler,
  finans,
  zaman,
  hesaplamalar,
  raporlar,
  ayarlar,
}

class _Bolum {
  const _Bolum(this.id, this.baslik, this.ikon, {this.yalnizca});

  final _B id;
  final String baslik;
  final IconData ikon;

  /// Doluysa yalnızca bu hesap türlerinde görünür.
  final Set<HesapTuru>? yalnizca;
}

/// Uygulamanın ana iskeleti: lacivert yan menü, üst çubuk ve içerik.
class AnaKabuk extends StatefulWidget {
  const AnaKabuk({super.key, required this.oturum, required this.cikisYap, this.depo, this.kurumsal});

  final Oturum oturum;
  final VoidCallback cikisYap;

  /// Verilmezse demo verisiyle bellek deposu oluşturulur.
  final BellekVeriDeposu? depo;

  /// Kurumsal sözleşme ve talep verisi; verilmezse demo verisi.
  final KurumsalDepo? kurumsal;

  @override
  State<AnaKabuk> createState() => _AnaKabukState();
}

class _AnaKabukState extends State<AnaKabuk> {
  _B _secili = _B.genelBakis;
  late final BellekVeriDeposu _depo =
      widget.depo ?? BellekVeriDeposu.demo(kiraciId: widget.oturum.kiraciId, avukatId: widget.oturum.kullaniciId);

  late final HesapYonetimi _yonetim = HesapYonetimi(oturum: widget.oturum, depo: _depo);
  late final BildirimServisi _bildirimler = BildirimServisi(
      depo: _depo,
      oturum: widget.oturum,
      kurumsal: widget.oturum.hesapTuru == HesapTuru.kurumsal ? _kurumsal : null);

  void _bildirimAc(HedefliBildirim h) {
    final id = h.bildirim.hedefId;
    switch (h.hedef) {
      case BildirimHedefi.dosya:
        if (id != null) _dosyaAc(id);
      case BildirimHedefi.tebligatKuyrugu:
        _sec(_B.tebligatlar);
      case BildirimHedefi.talep:
        if (id != null) {
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => TalepDetayEkrani(kurumsal: _kurumsal, talepId: id)));
        }
      case BildirimHedefi.sozlesme:
        if (id != null) {
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => SozlesmeDetayEkrani(kurumsal: _kurumsal, sozlesmeId: id)));
        }
    }
  }

  late final KurumsalDepo _kurumsal =
      widget.kurumsal ?? KurumsalDepo.demo(depo: _depo, kullaniciId: widget.oturum.kullaniciId);

  @override
  void dispose() {
    _yonetim.dispose();
    _bildirimler.dispose();
    if (widget.kurumsal == null) _kurumsal.dispose();
    super.dispose();
  }

  static const _tumBolumler = [
    _Bolum(_B.genelBakis, 'Genel Bakış', Icons.grid_view_rounded),
    _Bolum(_B.talepler, 'Hukuk Talepleri', Icons.description_outlined, yalnizca: {HesapTuru.kurumsal}),
    _Bolum(_B.dosyalar, 'Dosyalar', Icons.folder_outlined),
    _Bolum(_B.icra, 'İcra', Icons.gavel_outlined),
    _Bolum(_B.sozlesmeler, 'Sözleşmeler', Icons.article_outlined, yalnizca: {HesapTuru.kurumsal}),
    _Bolum(_B.disAvukatlar, 'Dış avukatlar', Icons.handshake_outlined, yalnizca: {HesapTuru.kurumsal}),
    _Bolum(_B.organizasyon, 'Grup şirketleri', Icons.account_tree_outlined, yalnizca: {HesapTuru.kurumsal}),
    _Bolum(_B.uyum, 'Uyum ve soruşturma', Icons.policy_outlined, yalnizca: {HesapTuru.kurumsal}),
    _Bolum(_B.tebligatlar, 'Tebligatlar', Icons.mail_outline),
    _Bolum(_B.takvim, 'Takvim', Icons.calendar_today_outlined),
    _Bolum(_B.muvekkiller, 'Müvekkiller', Icons.people_outline),
    _Bolum(_B.cikarCatismasi, 'Çıkar çatışması', Icons.gpp_maybe_outlined),
    _Bolum(_B.vekaletler, 'Vekâletler', Icons.assignment_ind_outlined),
    _Bolum(_B.finans, 'Finans', Icons.account_balance_wallet_outlined,
        yalnizca: {HesapTuru.avukatlikBurosu, HesapTuru.hukukBurosu}),
    _Bolum(_B.zaman, 'Zaman kaydı', Icons.timer_outlined, yalnizca: {HesapTuru.hukukBurosu}),
    _Bolum(_B.hesaplamalar, 'Hesaplamalar', Icons.calculate_outlined),
    _Bolum(_B.raporlar, 'Raporlar', Icons.bar_chart_rounded),
  ];

  static const _ayarlar = _Bolum(_B.ayarlar, 'Ayarlar', Icons.settings_outlined);

  List<_Bolum> get _bolumler => [
        for (final b in _tumBolumler)
          if (b.yalnizca == null || b.yalnizca!.contains(widget.oturum.hesapTuru))
            b.id == _B.muvekkiller && widget.oturum.hesapTuru == HesapTuru.kurumsal
                ? const _Bolum(_B.muvekkiller, 'Taraflar', Icons.people_outline)
                : b,
      ];

  @override
  void initState() {
    super.initState();
    _depo.aktifKullanici = widget.oturum.kullaniciId;
    _depo.okumaKaydet(DenetimIslemi.girisBasarili, 'oturum', widget.oturum.kullaniciId, widget.oturum.eposta);
  }

  void _sec(_B b) => setState(() => _secili = b);

  void _dosyaAc(String dosyaId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DosyaDetayEkrani(depo: _depo, oturum: widget.oturum, dosyaId: dosyaId),
      ),
    );
  }

  void _hizliIslem(HizliIslem i) => _sec(switch (i) {
        HizliIslem.tebligat => _B.tebligatlar,
        HizliIslem.kisi => _B.muvekkiller,
        HizliIslem.cikarCatismasi => _B.cikarCatismasi,
        HizliIslem.sureHesapla => _B.hesaplamalar,
        HizliIslem.talep => _B.talepler,
        HizliIslem.sozlesme => _B.sozlesmeler,
      });

  Widget _sayfa() => switch (_secili) {
        _B.genelBakis => GenelBakisEkrani(
            depo: _depo,
            oturum: widget.oturum,
            dosyaAc: _dosyaAc,
            hizliIslem: _hizliIslem,
            kurumsal: widget.oturum.hesapTuru == HesapTuru.kurumsal ? _kurumsal : null),
        _B.talepler => TaleplerEkrani(kurumsal: _kurumsal),
        _B.dosyalar => DosyalarEkrani(depo: _depo, oturum: widget.oturum),
        _B.icra => IcraEkrani(depo: _depo, oturum: widget.oturum),
        _B.sozlesmeler => SozlesmelerEkrani(kurumsal: _kurumsal),
        _B.disAvukatlar => DisAvukatlarEkrani(kurumsal: _kurumsal),
        _B.organizasyon => OrganizasyonEkrani(kurumsal: _kurumsal),
        _B.uyum => UyumEkrani(kurumsal: _kurumsal),
        _B.tebligatlar => TebligatlarEkrani(depo: _depo, oturum: widget.oturum),
        _B.takvim => TakvimEkrani(depo: _depo, dosyaAc: _dosyaAc),
        _B.muvekkiller => MuvekkillerEkrani(depo: _depo),
        _B.cikarCatismasi => CikarCatismasiEkrani(depo: _depo, oturum: widget.oturum),
        _B.vekaletler => VekaletlerEkrani(depo: _depo, oturum: widget.oturum),
        _B.finans => FinansEkrani(depo: _depo),
        _B.zaman => ZamanEkrani(depo: _depo, oturum: widget.oturum),
        _B.hesaplamalar => const HesaplamalarEkrani(),
        _B.raporlar => RaporlarEkrani(
            depo: _depo,
            oturum: widget.oturum,
            kurumsal: widget.oturum.hesapTuru == HesapTuru.kurumsal ? _kurumsal : null),
        _B.ayarlar => _AyarlarSayfasi(depo: _depo, yonetim: _yonetim),
      };

  @override
  Widget build(BuildContext context) {
    final genis = MediaQuery.sizeOf(context).width >= 1000;
    final menu = _YanMenu(
      bolumler: _bolumler,
      ayarlar: _ayarlar,
      secili: _secili,
      sec: (b) {
        _sec(b);
        if (!genis) Navigator.of(context).maybePop();
      },
    );

    return Scaffold(
      drawer: genis ? null : Drawer(backgroundColor: Renkler.lacivert, child: menu),
      body: Row(
        children: [
          if (genis) SizedBox(width: 268, child: menu),
          Expanded(
            child: Column(
              children: [
                _UstCubuk(
                  oturum: widget.oturum,
                  depo: _depo,
                  menuDugmesi: !genis,
                  cikisYap: widget.cikisYap,
                  dosyaAc: _dosyaAc,
                  bildirimler: _bildirimler,
                  bildirimAc: _bildirimAc,
                  muvekkillereGit: () => _sec(_B.muvekkiller),
                ),
                Expanded(child: _sayfa()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _YanMenu extends StatelessWidget {
  const _YanMenu({required this.bolumler, required this.ayarlar, required this.secili, required this.sec});

  final List<_Bolum> bolumler;
  final _Bolum ayarlar;
  final _B secili;
  final ValueChanged<_B> sec;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Renkler.lacivert,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(28, 28, 16, 36), child: Logo()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [for (final b in bolumler) _ogeler(b)],
              ),
            ),
            const Divider(color: Color(0x33FFFFFF), indent: 20, endIndent: 20),
            Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 20), child: _ogeler(ayarlar)),
          ],
        ),
      ),
    );
  }

  Widget _ogeler(_Bolum b) {
    final aktif = b.id == secili;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: aktif ? Renkler.yesilAcik : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: Key('menu-${b.id.name}'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => sec(b.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(b.ikon, color: aktif ? Colors.white : const Color(0xFFC9D1DE), size: 22),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    b.baslik,
                    style: TextStyle(
                      color: aktif ? Colors.white : const Color(0xFFE3E8EF),
                      fontSize: 16,
                      fontWeight: aktif ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UstCubuk extends StatelessWidget {
  const _UstCubuk({
    required this.oturum,
    required this.depo,
    required this.menuDugmesi,
    required this.cikisYap,
    required this.dosyaAc,
    required this.bildirimler,
    required this.bildirimAc,
    required this.muvekkillereGit,
  });

  final Oturum oturum;
  final BellekVeriDeposu depo;
  final bool menuDugmesi;
  final VoidCallback cikisYap;
  final ValueChanged<String> dosyaAc;
  final BildirimServisi bildirimler;
  final ValueChanged<HedefliBildirim> bildirimAc;
  final VoidCallback muvekkillereGit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Renkler.kenar))),
        child: Row(
          children: [
            if (menuDugmesi)
              Builder(
                builder: (context) => IconButton(
                  tooltip: 'Menüyü aç',
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: _KurumSecici(oturum: oturum, kurumsal: bildirimler.kurumsal),
              ),
            ),
            const Spacer(),
            IconButton(
              key: const Key('genel-arama'),
              tooltip: 'Ara',
              icon: const Icon(Icons.search),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _AramaDiyalogu(depo: depo, oturum: oturum, dosyaAc: dosyaAc, kisilereGit: muvekkillereGit),
              ),
            ),
            const SizedBox(height: 28, child: VerticalDivider(width: 24)),
            ListenableBuilder(
              listenable: Listenable.merge([depo, bildirimler, if (bildirimler.kurumsal != null) bildirimler.kurumsal!]),
              builder: (context, _) {
                final sayi = bildirimler.okunmamis();
                return IconButton(
                  key: const Key('bildirimler'),
                  tooltip: 'Bildirimler',
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => BildirimPaneli(servis: bildirimler, ac: bildirimAc),
                  ),
                  icon: Badge(
                    isLabelVisible: sayi > 0,
                    label: Text('$sayi'),
                    child: const Icon(Icons.notifications_none),
                  ),
                );
              },
            ),
            const SizedBox(height: 28, child: VerticalDivider(width: 24)),
            PopupMenuButton<String>(
              key: const Key('profil-menu'),
              tooltip: 'Profil',
              position: PopupMenuPosition.under,
              onSelected: (s) {
                if (s == 'cikis') cikisYap();
              },
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(oturum.adSoyad, style: const TextStyle(fontWeight: FontWeight.w700, color: Renkler.metin)),
                      Text(oturum.eposta, style: const TextStyle(color: Renkler.metinIkincil)),
                      Text(oturum.hesapTuru.ad, style: const TextStyle(color: Renkler.metinIkincil)),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  key: Key('cikis-yap'),
                  value: 'cikis',
                  child: Row(children: [Icon(Icons.logout), SizedBox(width: 12), Text('Çıkış yap')]),
                ),
              ],
              child: CircleAvatar(
                radius: 22,
                backgroundColor: Renkler.yesil,
                child: Text(
                  basHarfler(oturum.adSoyad),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dosya ve kişi arasında Türkçeye duyarlı genel arama (yetki filtreli).
class _AramaDiyalogu extends StatefulWidget {
  const _AramaDiyalogu({required this.depo, required this.oturum, required this.dosyaAc, required this.kisilereGit});

  final BellekVeriDeposu depo;
  final Oturum oturum;
  final ValueChanged<String> dosyaAc;
  final VoidCallback kisilereGit;

  @override
  State<_AramaDiyalogu> createState() => _AramaDiyaloguState();
}

class _AramaDiyaloguState extends State<_AramaDiyalogu> {
  String _sorgu = '';

  @override
  Widget build(BuildContext context) {
    final n = IsimEslestirme.normallestir(_sorgu);
    final dosyalar = n.isEmpty
        ? const <Dosya>[]
        : widget.depo
            .gorunurDosyalar(Aktor(
                kullaniciId: widget.oturum.kullaniciId, kiraciId: widget.oturum.kiraciId, roller: widget.oturum.roller))
            .where((d) =>
                IsimEslestirme.normallestir('${d.baslik} ${d.icNo} ${d.esasNo ?? ''} ${d.mahkeme ?? ''}').contains(n))
            .toList();
    final kisiler = n.isEmpty ? const <Kisi>[] : widget.depo.ara(_sorgu);
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const Key('arama-alani'),
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Dosya, esas no, müvekkil, TCKN/VKN…',
                ),
                onChanged: (v) => setState(() => _sorgu = v),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (dosyalar.isNotEmpty) const _AramaBasligi('Dosyalar'),
                  for (final d in dosyalar)
                    ListTile(
                      leading: Icon(d.gizli ? Icons.lock_outline : Icons.folder_outlined),
                      title: Text(d.baslik),
                      subtitle: Text('${d.icNo}${d.esasNo != null ? ' · ${d.esasNo}' : ''}'),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.dosyaAc(d.id);
                      },
                    ),
                  if (kisiler.isNotEmpty) const _AramaBasligi('Kişiler'),
                  for (final k in kisiler)
                    ListTile(
                      leading: Icon(k.tur == KisiTuru.gercek ? Icons.person_outline : Icons.business_outlined),
                      title: Text(k.ad),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.kisilereGit();
                      },
                    ),
                  if (n.isNotEmpty && dosyalar.isEmpty && kisiler.isEmpty)
                    const Padding(padding: EdgeInsets.all(24), child: Text('Sonuç bulunamadı.')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AramaBasligi extends StatelessWidget {
  const _AramaBasligi(this.metin);

  final String metin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(metin, style: const TextStyle(fontWeight: FontWeight.w700, color: Renkler.metinIkincil)),
      );
}

class _AyarlarSayfasi extends StatelessWidget {
  const _AyarlarSayfasi({required this.depo, required this.yonetim});

  final BellekVeriDeposu depo;
  final HesapYonetimi yonetim;

  @override
  Widget build(BuildContext context) {
    void ac(Widget sayfa) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => sayfa));
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Panel(
          baslik: 'Hesap',
          child: Column(
            children: [
              ListTile(
                key: const Key('ayar-abonelik'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.workspace_premium_outlined),
                title: const Text('Abonelik ve ödeme'),
                subtitle: Text('${yonetim.abonelik.paket.hesapTuru.ad} · ${yonetim.abonelik.durum.ad}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final uzak = yonetim.depo.uzak;
                  ac(uzak != null ? SunucuAbonelikEkrani(uzak: uzak) : AbonelikEkrani(yonetim: yonetim));
                },
              ),
              const Divider(),
              ListTile(
                key: const Key('ayar-ekip'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.group_outlined),
                title: const Text('Ekip ve davetler'),
                subtitle: const Text('Kullanıcı davet edin, rol verin, lisans koltuklarını izleyin.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // Sunucu bağlıyken davetler ve koltuklar sunucudan gelir (yönetici değilse liste boş kalır).
                  yonetim.sunucudanYukle().then((_) {}, onError: (Object _) {});
                  ac(EkipEkrani(yonetim: yonetim));
                },
              ),
              const Divider(),
              ListTile(
                key: const Key('ayar-2fa'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phonelink_lock_outlined),
                title: const Text('İki adımlı doğrulama'),
                subtitle: const Text('Girişte doğrulayıcı uygulamadan 6 haneli kod istenir.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ac(IkiAdimliEkrani(yonetim: yonetim)),
              ),
              const Divider(),
              ListTile(
                key: const Key('ayar-sifre'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.password),
                title: const Text('Şifre değiştir'),
                subtitle: const Text('Değişince diğer cihazlardaki oturumlarınız kapanır.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ac(SifreDegistirEkrani(kaydet: yonetim.sifreDegistir)),
              ),
              const Divider(),
              ListTile(
                key: const Key('ayar-oturumlar'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.devices),
                title: const Text('Açık oturumlar'),
                subtitle: const Text('Hangi cihazlarda oturumunuz açık; uzaktan kapatın.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ac(OturumlarEkrani(yonetim: yonetim)),
              ),
              const Divider(),
              if (yonetim.depo.uzak != null) ...[
                _HaftalikOzetAyari(uzak: yonetim.depo.uzak!),
                const Divider(),
              ],
              ListTile(
                key: const Key('ayar-takvim'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available_outlined),
                title: const Text('Takvim aboneliği'),
                subtitle: const Text('Duruşma ve süreleriniz Google, Outlook ya da Apple takviminizde.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ac(TakvimAbonelikEkrani(
                  yonetim: yonetim,
                  baglantiAc: (u) => launchUrl(u, mode: LaunchMode.externalApplication),
                )),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Panel(
          baslik: 'Veri ve güvenlik',
          child: Column(
            children: [
              ListTile(
                key: const Key('ayar-aktarim'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Veri aktarımı'),
                subtitle: const Text('Excel/CSV\'den müvekkil ve taraf listesi aktarın (önizlemeli, mükerrer kontrollü).'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ac(VeriAktarimEkrani(depo: depo)),
              ),
              const Divider(),
              ListTile(
                key: const Key('ayar-dosya-aktarim'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.drive_folder_upload_outlined),
                title: const Text('UYAP dosya listesi aktarımı'),
                subtitle: const Text('UYAP\'tan ya da başka programdan Excel/CSV dosya listesini aktarın (mükerrer kontrollü).'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ac(DosyaAktarimEkrani(depo: depo, kullaniciId: depo.aktifKullanici)),
              ),
              const Divider(),
              ListTile(
                key: const Key('ayar-sablonlar'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.checklist_rtl),
                title: const Text('Görev şablonları'),
                subtitle: const Text('Dosya açılınca otomatik atanan iş adımları (ör. iş davası açılışı).'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ac(GorevSablonlariEkrani(depo: depo)),
              ),
              const Divider(),
              ListTile(
                key: const Key('ayar-denetim'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.policy_outlined),
                title: const Text('Denetim kaydı'),
                subtitle: const Text('Kim, neyi, ne zaman yaptı; değiştirilemez kayıt zinciri.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ac(DenetimKaydiEkrani(depo: depo)),
              ),
              const Divider(),
              ListTile(
                key: const Key('ayar-kvkk'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.auto_delete_outlined),
                title: const Text('KVKK: saklama ve imha'),
                subtitle: const Text('Saklama süreleri, imha zamanı gelen kayıtlar ve dört göz onaylı imha tutanakları.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ac(KvkkEkrani(depo: depo)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Panel(
          baslik: 'Veri konumu',
          child: Text('Tüm verileriniz yalnızca Türkiye\'deki sunucularda tutulur ve işlenir; '
              'yedekler, kayıtlar ve yapay zekâ işlemleri dahil.'),
        ),
        const SizedBox(height: 20),
        const Panel(baslik: 'Paketler ve hesap türleri', dolgu: EdgeInsets.fromLTRB(4, 20, 4, 4), child: HesapTurleriIcerigi()),
      ],
    );
  }
}

/// Kurumsal hesapta grup şirketi seçimi (seçilen şirket alt şirketleriyle birlikte süzülür).
class _KurumSecici extends StatelessWidget {
  const _KurumSecici({required this.oturum, required this.kurumsal});

  final Oturum oturum;
  final KurumsalDepo? kurumsal;

  @override
  Widget build(BuildContext context) {
    final k = kurumsal;
    Widget etiket(String metin) => Row(children: [
          Expanded(child: Text(metin, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16))),
          const Icon(Icons.keyboard_arrow_down),
        ]);
    if (k == null || k.grup.tumu.isEmpty) {
      return OutlinedButton(
        key: const Key('kurum-secici'),
        style: OutlinedButton.styleFrom(foregroundColor: Renkler.metin),
        onPressed: null,
        child: etiket(oturum.kurumAdi),
      );
    }
    return ListenableBuilder(
      listenable: k,
      builder: (context, _) => PopupMenuButton<String>(
        key: const Key('kurum-secici'),
        tooltip: 'Grup şirketi seç',
        position: PopupMenuPosition.under,
        onSelected: (id) => k.sirketSec(id == '*' ? null : id),
        itemBuilder: (_) => [
          const PopupMenuItem(value: '*', child: Text('Tüm grup')),
          for (final (sirket, derinlik) in k.grup.agacSirasi())
            PopupMenuItem(
              key: Key('sirket-${sirket.id}'),
              value: sirket.id,
              child: Padding(
                padding: EdgeInsets.only(left: 16.0 * derinlik),
                child: Text(sirket.gorunenAd),
              ),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(border: Border.all(color: Renkler.kenar), borderRadius: BorderRadius.circular(10)),
          child: etiket(k.aktifSirket == null ? '${oturum.kurumAdi} · tüm grup' : k.aktifSirket!.gorunenAd),
        ),
      ),
    );
  }
}

/// Haftalık özet e-postası tercihi (sunucu bağlıyken).
class _HaftalikOzetAyari extends StatefulWidget {
  const _HaftalikOzetAyari({required this.uzak});

  final UzakIslemler uzak;

  @override
  State<_HaftalikOzetAyari> createState() => _HaftalikOzetAyariState();
}

class _HaftalikOzetAyariState extends State<_HaftalikOzetAyari> {
  bool? _acik;

  @override
  void initState() {
    super.initState();
    widget.uzak.haftalikOzetAcikMi().then((v) {
      if (mounted) setState(() => _acik = v);
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
        key: const Key('ayar-haftalik-ozet'),
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.mark_email_unread_outlined),
        title: const Text('Haftalık özet e-postası'),
        subtitle: const Text('Pazartesi sabahı süre, görev ve duruşma sayılarınız (müvekkil bilgisi olmadan).'),
        value: _acik ?? true,
        onChanged: _acik == null
            ? null
            : (v) async {
                setState(() => _acik = v);
                try {
                  await widget.uzak.haftalikOzetAyarla(v);
                } on Exception {
                  if (mounted) setState(() => _acik = !v);
                }
              },
      );
}
