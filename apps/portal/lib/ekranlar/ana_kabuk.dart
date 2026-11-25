import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/kimlik_servisi.dart';
import '../servisler/veri_deposu.dart';
import '../tema/tema.dart';
import 'cikar_catismasi_ekrani.dart';
import 'dosyalar_ekrani.dart';
import 'genel_bakis_ekrani.dart';
import 'hesap_turleri_ekrani.dart';
import 'muvekkiller_ekrani.dart';
import 'finans_ekrani.dart';
import 'hesaplamalar_ekrani.dart';
import 'takvim_ekrani.dart';
import 'tebligatlar_ekrani.dart';
import 'vekaletler_ekrani.dart';

enum _B {
  genelBakis,
  talepler,
  dosyalar,
  sozlesmeler,
  tebligatlar,
  takvim,
  muvekkiller,
  cikarCatismasi,
  vekaletler,
  finans,
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
  const AnaKabuk({super.key, required this.oturum, required this.cikisYap, this.depo});

  final Oturum oturum;
  final VoidCallback cikisYap;

  /// Verilmezse demo verisiyle bellek deposu oluşturulur.
  final BellekVeriDeposu? depo;

  @override
  State<AnaKabuk> createState() => _AnaKabukState();
}

class _AnaKabukState extends State<AnaKabuk> {
  _B _secili = _B.genelBakis;
  late final BellekVeriDeposu _depo =
      widget.depo ?? BellekVeriDeposu.demo(kiraciId: widget.oturum.kiraciId, avukatId: widget.oturum.kullaniciId);

  static const _tumBolumler = [
    _Bolum(_B.genelBakis, 'Genel Bakış', Icons.grid_view_rounded),
    _Bolum(_B.talepler, 'Hukuk Talepleri', Icons.description_outlined, yalnizca: {HesapTuru.kurumsal}),
    _Bolum(_B.dosyalar, 'Dosyalar', Icons.folder_outlined),
    _Bolum(_B.sozlesmeler, 'Sözleşmeler', Icons.article_outlined, yalnizca: {HesapTuru.kurumsal}),
    _Bolum(_B.tebligatlar, 'Tebligatlar', Icons.mail_outline),
    _Bolum(_B.takvim, 'Takvim', Icons.calendar_today_outlined),
    _Bolum(_B.muvekkiller, 'Müvekkiller', Icons.people_outline),
    _Bolum(_B.cikarCatismasi, 'Çıkar çatışması', Icons.gpp_maybe_outlined),
    _Bolum(_B.vekaletler, 'Vekâletler', Icons.assignment_ind_outlined),
    _Bolum(_B.finans, 'Finans', Icons.account_balance_wallet_outlined,
        yalnizca: {HesapTuru.avukatlikBurosu, HesapTuru.hukukBurosu}),
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
      });

  Widget _sayfa() => switch (_secili) {
        _B.genelBakis => GenelBakisEkrani(
            depo: _depo, oturum: widget.oturum, dosyaAc: _dosyaAc, hizliIslem: _hizliIslem),
        _B.talepler => const YakindaSayfasi(
            baslik: 'Hukuk Talepleri',
            faz: 'Faz 2',
            ikon: Icons.description_outlined,
            aciklama: 'İş birimlerinin sözleşme inceleme, görüş ve ihtar taleplerini SLA ve onay akışıyla yönetin.',
          ),
        _B.dosyalar => DosyalarEkrani(depo: _depo, oturum: widget.oturum),
        _B.sozlesmeler => const YakindaSayfasi(
            baslik: 'Sözleşmeler',
            faz: 'Faz 2',
            ikon: Icons.article_outlined,
            aciklama: 'Yüklenen her sözleşme otomatik taranır; taraflar, süreler, riskli maddeler ve '
                'yükümlülükler çıkarılır, yenileme tarihleri takvime düşer.',
          ),
        _B.tebligatlar => TebligatlarEkrani(depo: _depo, oturum: widget.oturum),
        _B.takvim => TakvimEkrani(depo: _depo, dosyaAc: _dosyaAc),
        _B.muvekkiller => MuvekkillerEkrani(depo: _depo),
        _B.cikarCatismasi => CikarCatismasiEkrani(depo: _depo, oturum: widget.oturum),
        _B.vekaletler => VekaletlerEkrani(depo: _depo, oturum: widget.oturum),
        _B.finans => FinansEkrani(depo: _depo),
        _B.hesaplamalar => const HesaplamalarEkrani(),
        _B.raporlar => const YakindaSayfasi(
            baslik: 'Raporlar',
            faz: 'Faz 2',
            ikon: Icons.bar_chart_rounded,
            aciklama: 'Açık dosya, kritik süre, tahsilat, iş yükü ve çevrim süresi göstergeleri.',
          ),
        _B.ayarlar => const _AyarlarSayfasi(),
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
                  uyarilaraGit: () => _sec(_B.genelBakis),
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
    required this.uyarilaraGit,
    required this.muvekkillereGit,
  });

  final Oturum oturum;
  final BellekVeriDeposu depo;
  final bool menuDugmesi;
  final VoidCallback cikisYap;
  final ValueChanged<String> dosyaAc;
  final VoidCallback uyarilaraGit;
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
                child: OutlinedButton(
                  key: const Key('kurum-secici'),
                  style: OutlinedButton.styleFrom(foregroundColor: Renkler.metin),
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Grup şirketleri arasında geçiş Organizasyon modülüyle gelecek.')),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(oturum.kurumAdi,
                            overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
                      ),
                      const Icon(Icons.keyboard_arrow_down),
                    ],
                  ),
                ),
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
              listenable: depo,
              builder: (context, _) {
                final sayi = depo.uyarilar(Tarih.from(DateTime.now())).length;
                return IconButton(
                  key: const Key('bildirimler'),
                  tooltip: 'Bildirimler',
                  onPressed: uyarilaraGit,
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
  const _AyarlarSayfasi();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        Panel(
          baslik: 'Veri konumu',
          child: Text('Tüm verileriniz yalnızca Türkiye\'deki sunucularda tutulur ve işlenir; '
              'yedekler, kayıtlar ve yapay zekâ işlemleri dahil.'),
        ),
        SizedBox(height: 20),
        Panel(baslik: 'Paketler ve hesap türleri', dolgu: EdgeInsets.fromLTRB(4, 20, 4, 4), child: HesapTurleriIcerigi()),
      ],
    );
  }
}
