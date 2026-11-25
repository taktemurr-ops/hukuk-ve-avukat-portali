import 'package:flutter/material.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/bicim.dart';
import '../bilesenler/tasarim.dart';
import '../servisler/kimlik_servisi.dart';
import '../servisler/veri_deposu.dart';
import '../tema/tema.dart';

/// Hızlı işlem: Genel Bakış'taki "Yeni" düğmesinden açılan bölümler.
enum HizliIslem { tebligat, kisi, cikarCatismasi, sureHesapla }

class _IsSatiri {
  const _IsSatiri({
    required this.baslik,
    required this.alt,
    required this.sorumlu,
    required this.sonTarih,
    required this.durum,
    required this.rozet,
    this.dosyaId,
  });

  final String baslik;
  final String alt;
  final String sorumlu;
  final Tarih? sonTarih;
  final String durum;
  final RozetTuru rozet;
  final String? dosyaId;
}

/// Genel Bakış: göstergeler, iş kuyruğu, yaklaşan duruşmalar, tebligat kuyruğu.
class GenelBakisEkrani extends StatelessWidget {
  const GenelBakisEkrani({
    super.key,
    required this.depo,
    required this.oturum,
    required this.dosyaAc,
    required this.hizliIslem,
  });

  final BellekVeriDeposu depo;
  final Oturum oturum;
  final ValueChanged<String> dosyaAc;
  final ValueChanged<HizliIslem> hizliIslem;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: depo,
      builder: (context, _) {
        final bugun = Tarih.from(DateTime.now());
        final genislik = MediaQuery.sizeOf(context).width;
        final dosyalar = depo.gorunurDosyalar(
          Aktor(kullaniciId: oturum.kullaniciId, kiraciId: oturum.kiraciId, roller: oturum.roller),
        );
        final gorunurIdler = dosyalar.map((d) => d.id).toSet();
        final sureler = depo.sureler.where((s) => s.acik && gorunurIdler.contains(s.dosyaId)).toList();
        final uyarilar = depo.uyarilar(bugun).where((u) => gorunurIdler.contains(u.sure.dosyaId)).toList();
        final gorevler = depo.gorevler
            .where((g) => g.durum == GorevDurumu.acik && (g.dosyaId == null || gorunurIdler.contains(g.dosyaId)))
            .toList();

        final dolacak = sureler.where((s) => s.kalanGun(bugun) <= 7).length;
        final teyitBekleyen = sureler.where((s) => s.durum == SureDurumu.teyitBekliyor).length;
        final kuyruk = depo.eslesmeyenTebligatlar;

        final kritik = _kritikIsler(uyarilar, gorevler, bugun);
        final tum = _tumIsler(sureler, gorevler, bugun);

        final ustBaslik = Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Genel Bakış', style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: 4),
                  Text(uzunTarih(bugun),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Renkler.metinIkincil)),
                ],
              ),
            ),
            PopupMenuButton<HizliIslem>(
              key: const Key('yeni-islem'),
              onSelected: hizliIslem,
              position: PopupMenuPosition.under,
              itemBuilder: (_) => const [
                PopupMenuItem(value: HizliIslem.tebligat, child: Text('Tebligat kaydet')),
                PopupMenuItem(value: HizliIslem.kisi, child: Text('Yeni müvekkil / taraf')),
                PopupMenuItem(value: HizliIslem.cikarCatismasi, child: Text('Çıkar çatışması taraması')),
                PopupMenuItem(value: HizliIslem.sureHesapla, child: Text('Süre hesapla')),
              ],
              child: IgnorePointer(
                child: FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.add),
                  label: Text(oturum.hesapTuru == HesapTuru.kurumsal ? 'Yeni Talep' : 'Yeni İşlem'),
                ),
              ),
            ),
          ],
        );

        final kpiler = [
          _Kpi('Açık Dosya', '${dosyalar.where((d) => d.acik).length}', Icons.folder_outlined, Renkler.yesilZemin,
              Renkler.yesil),
          _Kpi('Dolacak Süre (7 gün)', '$dolacak', Icons.calendar_month_outlined, Renkler.uyariZemin, Renkler.uyari,
              vurgulu: dolacak > 0),
          _Kpi('Eşleşmeyen Tebligat', '${kuyruk.length}', Icons.mail_outline, Renkler.notrZemin, Renkler.notr),
          oturum.hesapTuru == HesapTuru.kurumsal
              ? const _Kpi('Sözleşme Onayı', '0', Icons.description_outlined, Renkler.yesilZemin, Renkler.yesil)
              : _Kpi('Teyit Bekleyen Süre', '$teyitBekleyen', Icons.fact_check_outlined, Renkler.yesilZemin,
                  Renkler.yesil),
        ];

        final kpiPaneli = Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
            child: genislik >= 900
                ? IntrinsicHeight(
                    child: Row(
                      children: [
                        for (var i = 0; i < kpiler.length; i++) ...[
                          if (i > 0) const VerticalDivider(width: 1),
                          Expanded(child: kpiler[i]),
                        ],
                      ],
                    ),
                  )
                : Wrap(
                    runSpacing: 16,
                    children: [for (final k in kpiler) SizedBox(width: 260, child: k)],
                  ),
          ),
        );

        final isKuyrugu = Panel(
          baslik: 'İş Kuyruğu',
          dolgu: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: _IsKuyrugu(kritik: kritik, tum: tum, depo: depo, dosyaAc: dosyaAc),
        );

        final yanPanel = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DurusmaPaneli(depo: depo, dosyaAc: dosyaAc),
            const SizedBox(height: 20),
            Panel(
              baslik: 'Tebligat Kuyruğu',
              child: Column(
                children: [
                  _KuyrukSatiri(
                    ikon: Icons.mail_outline,
                    zemin: Renkler.uyariZemin,
                    renk: Renkler.uyari,
                    metin: '${kuyruk.where((t) => t.eslesmeDurumu == EslesmeDurumu.onerildi).length} eşleşme önerisi bekliyor',
                    onTap: () => hizliIslem(HizliIslem.tebligat),
                  ),
                  const Divider(),
                  _KuyrukSatiri(
                    ikon: Icons.mark_email_unread_outlined,
                    zemin: Renkler.notrZemin,
                    renk: Renkler.notr,
                    metin: '${kuyruk.where((t) => t.eslesmeDurumu == EslesmeDurumu.eslesmedi).length} dosyası bulunamadı',
                    onTap: () => hizliIslem(HizliIslem.tebligat),
                  ),
                  const Divider(),
                  _KuyrukSatiri(
                    ikon: Icons.fact_check_outlined,
                    zemin: Renkler.yesilZemin,
                    renk: Renkler.yesil,
                    metin: '$teyitBekleyen süre hesabı teyit bekliyor',
                  ),
                ],
              ),
            ),
          ],
        );

        return ListView(
          padding: EdgeInsets.all(genislik >= 900 ? 32 : 16),
          children: [
            ustBaslik,
            const SizedBox(height: 24),
            kpiPaneli,
            const SizedBox(height: 24),
            if (genislik >= 1180)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: isKuyrugu),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: yanPanel),
                ],
              )
            else ...[
              isKuyrugu,
              const SizedBox(height: 20),
              yanPanel,
            ],
          ],
        );
      },
    );
  }

  List<_IsSatiri> _kritikIsler(List<SureUyarisi> uyarilar, List<Gorev> gorevler, Tarih bugun) {
    final satirlar = <_IsSatiri>[
      for (final u in uyarilar)
        _IsSatiri(
          baslik: u.sure.sonuc.kural.ad,
          alt: depo.dosya(u.sure.dosyaId)?.baslik ?? '',
          sorumlu: u.sure.sahipsiz ? 'Atanmamış' : depo.kullaniciAdi(u.sure.asilSorumlu),
          sonTarih: u.sure.sonGun,
          durum: _uyariDurumu(u),
          rozet: _uyariRozeti(u),
          dosyaId: u.sure.dosyaId,
        ),
      for (final g in gorevler.where((g) => g.gecikti(bugun)))
        _IsSatiri(
          baslik: g.baslik,
          alt: depo.dosya(g.dosyaId ?? '')?.baslik ?? '',
          sorumlu: depo.kullaniciAdi(g.atanan),
          sonTarih: g.sonTarih,
          durum: 'Gecikti',
          rozet: RozetTuru.kritik,
          dosyaId: g.dosyaId,
        ),
    ];
    return satirlar;
  }

  static String _uyariDurumu(SureUyarisi u) {
    if (u.seviye == UyariSeviyesi.kritik) return 'Süre geçti';
    if (u.sure.sahipsiz) return 'Atanmamış';
    if (u.sure.durum == SureDurumu.teyitBekliyor) return 'Teyit bekliyor';
    return switch (u.seviye) {
      UyariSeviyesi.yonetici => 'Son gün bugün',
      UyariSeviyesi.yedekSorumlu => 'Son gün yarın',
      _ => 'Yaklaşıyor',
    };
  }

  static RozetTuru _uyariRozeti(SureUyarisi u) {
    if (u.seviye == UyariSeviyesi.kritik || u.sure.sahipsiz) return RozetTuru.kritik;
    if (u.sure.durum == SureDurumu.teyitBekliyor) return RozetTuru.uyari;
    return switch (u.seviye) {
      UyariSeviyesi.yonetici || UyariSeviyesi.yedekSorumlu => RozetTuru.kritik,
      _ => RozetTuru.devam,
    };
  }

  List<_IsSatiri> _tumIsler(List<SureKaydi> sureler, List<Gorev> gorevler, Tarih bugun) {
    final kaynakli = sureler.map((s) => s.id).toSet();
    final satirlar = <_IsSatiri>[
      for (final s in sureler)
        _IsSatiri(
          baslik: s.sonuc.kural.ad,
          alt: depo.dosya(s.dosyaId)?.baslik ?? '',
          sorumlu: s.sahipsiz ? 'Atanmamış' : depo.kullaniciAdi(s.asilSorumlu),
          sonTarih: s.sonGun,
          durum: s.durum == SureDurumu.teyitBekliyor ? 'Teyit bekliyor' : 'Teyitli süre',
          rozet: s.durum == SureDurumu.teyitBekliyor ? RozetTuru.uyari : RozetTuru.onay,
          dosyaId: s.dosyaId,
        ),
      for (final g in gorevler.where((g) => !kaynakli.contains(g.kaynakSureId)))
        _IsSatiri(
          baslik: g.baslik,
          alt: depo.dosya(g.dosyaId ?? '')?.baslik ?? '',
          sorumlu: depo.kullaniciAdi(g.atanan),
          sonTarih: g.sonTarih,
          durum: g.gecikti(bugun) ? 'Gecikti' : 'Devam ediyor',
          rozet: g.gecikti(bugun) ? RozetTuru.kritik : RozetTuru.devam,
          dosyaId: g.dosyaId,
        ),
    ];
    satirlar.sort((a, b) {
      if (a.sonTarih == null) return 1;
      if (b.sonTarih == null) return -1;
      return a.sonTarih!.compareTo(b.sonTarih!);
    });
    return satirlar;
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.baslik, this.deger, this.ikon, this.zemin, this.renk, {this.vurgulu = false});

  final String baslik;
  final String deger;
  final IconData ikon;
  final Color zemin;
  final Color renk;
  final bool vurgulu;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: zemin, borderRadius: BorderRadius.circular(12)),
            child: Icon(ikon, color: renk),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(baslik, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Renkler.metinIkincil)),
                const SizedBox(height: 4),
                Text(
                  deger,
                  style: Theme.of(context)
                      .textTheme
                      .headlineLarge
                      ?.copyWith(color: vurgulu ? Renkler.uyari : Renkler.metin, height: 1.1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IsKuyrugu extends StatefulWidget {
  const _IsKuyrugu({required this.kritik, required this.tum, required this.depo, required this.dosyaAc});

  final List<_IsSatiri> kritik;
  final List<_IsSatiri> tum;
  final BellekVeriDeposu depo;
  final ValueChanged<String> dosyaAc;

  @override
  State<_IsKuyrugu> createState() => _IsKuyruguState();
}

class _IsKuyruguState extends State<_IsKuyrugu> {
  int _sekme = 0;

  @override
  Widget build(BuildContext context) {
    final satirlar = _sekme == 0 ? widget.kritik : widget.tum;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DefaultTabController(
          length: 2,
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            onTap: (i) => setState(() => _sekme = i),
            tabs: [
              Tab(key: const Key('sekme-kritik'), text: 'Kritik İşler (${widget.kritik.length})'),
              Tab(key: const Key('sekme-tum'), text: 'Tüm İşler (${widget.tum.length})'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final genis = c.maxWidth >= 560;
          if (satirlar.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Bu listede iş yok.', textAlign: TextAlign.center),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (genis)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(color: Renkler.krem, borderRadius: BorderRadius.circular(8)),
                  child: const Row(
                    children: [
                      Expanded(flex: 5, child: Text('İş', style: TextStyle(fontWeight: FontWeight.w700))),
                      Expanded(flex: 3, child: Text('Sorumlu', style: TextStyle(fontWeight: FontWeight.w700))),
                      Expanded(flex: 2, child: Text('Son Tarih', style: TextStyle(fontWeight: FontWeight.w700))),
                      Expanded(flex: 3, child: Text('Durum', style: TextStyle(fontWeight: FontWeight.w700))),
                    ],
                  ),
                ),
              for (final s in satirlar) ...[
                InkWell(
                  onTap: s.dosyaId == null ? null : () => widget.dosyaAc(s.dosyaId!),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: genis
                        ? Row(
                            children: [
                              Expanded(flex: 5, child: _isBasligi(context, s)),
                              Expanded(flex: 3, child: Text(s.sorumlu)),
                              Expanded(flex: 2, child: Text(s.sonTarih == null ? '-' : kisaTarih(s.sonTarih!))),
                              Expanded(
                                flex: 3,
                                child: Align(alignment: Alignment.centerLeft, child: DurumRozeti(s.durum, s.rozet)),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: _isBasligi(context, s, ek: '${s.sorumlu} · ${s.sonTarih == null ? '-' : kisaTarih(s.sonTarih!)}')),
                              DurumRozeti(s.durum, s.rozet),
                            ],
                          ),
                  ),
                ),
                const Divider(),
              ],
            ],
          );
        }),
      ],
    );
  }

  Widget _isBasligi(BuildContext context, _IsSatiri s, {String? ek}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.baslik, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (s.alt.isNotEmpty)
            Text(s.alt, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Renkler.metinIkincil)),
          if (ek != null) Text(ek, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _DurusmaPaneli extends StatelessWidget {
  const _DurusmaPaneli({required this.depo, required this.dosyaAc});

  final BellekVeriDeposu depo;
  final ValueChanged<String> dosyaAc;

  @override
  Widget build(BuildContext context) {
    final simdi = DateTime.now();
    final liste = depo.durusmalar.where((d) => d.baslangic.isAfter(simdi)).toList()
      ..sort((a, b) => a.baslangic.compareTo(b.baslangic));
    final cakisanlar = {for (final c in depo.cakismalar) ...[c.a.id, c.b.id]};
    return Panel(
      baslik: 'Yaklaşan Duruşmalar',
      child: Column(
        children: [
          if (liste.isEmpty) const Text('Yaklaşan duruşma yok.'),
          for (final d in liste.take(5)) ...[
            InkWell(
              onTap: () => dosyaAc(d.dosyaId),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Column(
                        children: [
                          Text('${d.baslangic.day}',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Renkler.yesil, height: 1)),
                          Text(ayKisaltmasi(d.baslangic.month),
                              style: const TextStyle(color: Renkler.metinIkincil, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 44, color: Renkler.kenar, margin: const EdgeInsets.symmetric(horizontal: 16)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(depo.dosya(d.dosyaId)?.baslik ?? d.tur, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${d.tur} · ${saat(d.baslangic)} · ${d.yer}',
                              style: const TextStyle(color: Renkler.metinIkincil)),
                        ],
                      ),
                    ),
                    if (cakisanlar.contains(d.id))
                      const Tooltip(
                        message: 'Aynı avukatın başka bir duruşmasıyla çakışıyor',
                        child: DurumRozeti('Çakışma', RozetTuru.kritik, key: Key('cakisma-rozeti')),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(),
          ],
        ],
      ),
    );
  }
}

class _KuyrukSatiri extends StatelessWidget {
  const _KuyrukSatiri({required this.ikon, required this.zemin, required this.renk, required this.metin, this.onTap});

  final IconData ikon;
  final Color zemin;
  final Color renk;
  final String metin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: zemin, borderRadius: BorderRadius.circular(10)),
              child: Icon(ikon, color: renk, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(metin, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            if (onTap != null) const Icon(Icons.chevron_right, color: Renkler.metinIkincil),
          ],
        ),
      ),
    );
  }
}
