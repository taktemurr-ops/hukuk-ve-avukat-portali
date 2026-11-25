import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import '../bilesenler/tasarim.dart';
import '../servisler/kimlik_servisi.dart';
import '../servisler/kurumsal_depo.dart';
import '../servisler/veri_deposu.dart';
import '../tema/tema.dart';
import 'sozlesmeler_ekrani.dart';

class RaporlarEkrani extends StatelessWidget {
  const RaporlarEkrani({super.key, required this.depo, required this.oturum, this.kurumsal});

  final BellekVeriDeposu depo;
  final Oturum oturum;
  final KurumsalDepo? kurumsal;

  void _csvKopyala(BuildContext context, String ad, String csv) {
    Clipboard.setData(ClipboardData(text: csv)).ignore();
    depo.okumaKaydet(DenetimIslemi.disaAktarma, 'rapor', ad, 'CSV panoya kopyalandı');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$ad CSV olarak kopyalandı; Excel\'e yapıştırabilirsiniz.')));
  }

  @override
  Widget build(BuildContext context) {
    final k = kurumsal;
    return ListenableBuilder(
      listenable: k == null ? depo : Listenable.merge([depo, k]),
      builder: (context, _) {
        final bugun = k?.bugunTarih ?? Tarih.from(DateTime.now());
        final aktor = Aktor(kullaniciId: oturum.kullaniciId, kiraciId: oturum.kiraciId, roller: oturum.roller);
        final dosyalar = depo.gorunurDosyalar(aktor);
        final idler = dosyalar.map((d) => d.id).toSet();
        final sureler = depo.sureler.where((s) => idler.contains(s.dosyaId)).toList();
        final gorevler = depo.gorevler.where((g) => g.dosyaId == null || idler.contains(g.dosyaId)).toList();
        final isYuku = Raporlar.isYuku(
          dosyalar: dosyalar,
          sureler: sureler,
          gorevler: gorevler,
          talepler: k?.gorunurTalepler ?? const [],
          bugun: bugun,
        );
        final dagilim = Raporlar.sureDagilimi(sureler, bugun);
        String ad(String id) => k?.kisiAdi(id) ?? depo.kullaniciAdi(id);
        final finans = oturum.lisans.modulAcik(Modul.buroFinansi);

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Raporlar', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text('Yalnızca görme yetkiniz olan dosyalar hesaba katılır. ${bugun.turkceBicim} itibarıyla.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            Panel(
              baslik: 'İş yükü',
              sag: _CsvDugmesi(
                anahtar: 'csv-is-yuku',
                onPressed: () => _csvKopyala(
                    context,
                    'İş yükü',
                    Raporlar.csv(
                      ['Kişi', 'Açık dosya', 'Açık süre', 'Kritik süre (7 gün)', 'Teyit bekleyen', 'Açık görev', 'Geciken görev', 'Açık talep'],
                      isYuku.map((s) => [
                            ad(s.kullanici), s.acikDosya, s.acikSure, s.kritikSure, s.teyitBekleyen,
                            s.acikGorev, s.gecikenGorev, s.acikTalep,
                          ]),
                    )),
              ),
              child: _Tablo(
                anahtar: 'rapor-is-yuku',
                basliklar: const ['Kişi', 'Dosya', 'Süre', 'Kritik', 'Teyitsiz', 'Görev', 'Geciken', 'Talep'],
                satirlar: [
                  for (final s in isYuku)
                    [ad(s.kullanici), '${s.acikDosya}', '${s.acikSure}', '${s.kritikSure}', '${s.teyitBekleyen}',
                      '${s.acikGorev}', '${s.gecikenGorev}', '${s.acikTalep}'],
                ],
                vurgu: (satir, sutun) => (sutun == 3 || sutun == 6) && satir[sutun] != '0',
              ),
            ),
            const SizedBox(height: 20),
            Panel(
              baslik: 'Açık sürelerin dağılımı',
              sag: Wrap(spacing: 8, children: [
                if (dagilim.teyitBekleyen > 0) DurumRozeti('${dagilim.teyitBekleyen} teyit bekliyor', RozetTuru.uyari),
                if (dagilim.sahipsiz > 0) DurumRozeti('${dagilim.sahipsiz} sahipsiz', RozetTuru.kritik),
              ]),
              child: _Cubuklar(anahtar: 'rapor-sure', degerler: [
                ('Kaçan', dagilim.kacan, Renkler.kritik),
                ('Bugün / yarın', dagilim.bugunYarin, Renkler.kritik),
                ('2–7 gün', dagilim.buHafta, Renkler.uyari),
                ('8–30 gün', dagilim.buAy, Renkler.bilgi),
                ('30+ gün', dagilim.sonra, Renkler.yesil),
              ]),
            ),
            if (finans) ...[
              const SizedBox(height: 20),
              _AlacakPaneli(depo: depo, bugun: bugun, csvKopyala: (c, a, v) => _csvKopyala(c, a, v)),
            ],
            if (k != null) ...[
              const SizedBox(height: 20),
              _TalepPaneli(k: k),
              const SizedBox(height: 20),
              _SozlesmePaneli(k: k),
            ],
          ],
        );
      },
    );
  }
}

class _CsvDugmesi extends StatelessWidget {
  const _CsvDugmesi({required this.anahtar, required this.onPressed});

  final String anahtar;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        key: Key(anahtar),
        onPressed: onPressed,
        icon: const Icon(Icons.copy_all_outlined, size: 18),
        label: const Text('CSV kopyala'),
      );
}

class _Tablo extends StatelessWidget {
  const _Tablo({required this.anahtar, required this.basliklar, required this.satirlar, this.vurgu});

  final String anahtar;
  final List<String> basliklar;
  final List<List<String>> satirlar;
  final bool Function(List<String> satir, int sutun)? vurgu;

  @override
  Widget build(BuildContext context) {
    if (satirlar.isEmpty) return const Text('Kayıt yok.');
    final kucuk = Theme.of(context).textTheme.bodySmall;
    return SingleChildScrollView(
      key: Key(anahtar),
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 44,
        columnSpacing: 24,
        columns: [for (final b in basliklar) DataColumn(label: Text(b, style: kucuk))],
        rows: [
          for (final s in satirlar)
            DataRow(cells: [
              for (var i = 0; i < s.length; i++)
                DataCell(Text(s[i],
                    style: (vurgu?.call(s, i) ?? false)
                        ? const TextStyle(color: Renkler.kritik, fontWeight: FontWeight.w700)
                        : null)),
            ]),
        ],
      ),
    );
  }
}

class _Cubuklar extends StatelessWidget {
  const _Cubuklar({required this.anahtar, required this.degerler});

  final String anahtar;
  final List<(String, int, Color)> degerler;

  @override
  Widget build(BuildContext context) {
    final enBuyuk = degerler.fold<int>(0, (a, d) => d.$2 > a ? d.$2 : a);
    return Column(
      key: Key(anahtar),
      children: [
        for (final (etiket, deger, renk) in degerler)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 120, child: Text(etiket, style: Theme.of(context).textTheme.bodySmall)),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 18,
                      width: enBuyuk == 0 ? 0 : c.maxWidth * deger / enBuyuk,
                      decoration: BoxDecoration(color: renk, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 40, child: Text('$deger', textAlign: TextAlign.right)),
            ]),
          ),
      ],
    );
  }
}

class _AlacakPaneli extends StatelessWidget {
  const _AlacakPaneli({required this.depo, required this.bugun, required this.csvKopyala});

  final BellekVeriDeposu depo;
  final Tarih bugun;
  final void Function(BuildContext, String, String) csvKopyala;

  @override
  Widget build(BuildContext context) {
    final y = Raporlar.alacakYaslandirma(depo.tumCariHareketler, bugun);
    String ad(String id) => depo.kisi(id)?.ad ?? id;
    final toplam = y.fold(Para.sifir, (a, b) => a + b.toplam);
    return Panel(
      baslik: 'Alacak yaşlandırma · toplam ${toplam.bicimli}',
      sag: _CsvDugmesi(
        anahtar: 'csv-alacak',
        onPressed: () => csvKopyala(
            context,
            'Alacak yaşlandırma',
            Raporlar.csv(
              ['Müvekkil', ...AlacakYaslandirma.kovaAdlari, 'Masraf alacağı', 'Toplam'],
              y.map((s) => [ad(s.muvekkilId), ...s.kovalar.map((p) => p.bicimli), s.masrafAlacagi.bicimli, s.toplam.bicimli]),
            )),
      ),
      child: _Tablo(
        anahtar: 'rapor-alacak',
        basliklar: ['Müvekkil', ...AlacakYaslandirma.kovaAdlari, 'Masraf', 'Toplam'],
        satirlar: [
          for (final s in y)
            [ad(s.muvekkilId), ...s.kovalar.map((p) => p.bicimli), s.masrafAlacagi.bicimli, s.toplam.bicimli],
        ],
        vurgu: (satir, sutun) => (sutun == 3 || sutun == 4) && satir[sutun] != Para.sifir.bicimli,
      ),
    );
  }
}

class _TalepPaneli extends StatelessWidget {
  const _TalepPaneli({required this.k});

  final KurumsalDepo k;

  @override
  Widget build(BuildContext context) {
    final p = Raporlar.talepPerformansi(k.gorunurTalepler, k.bugunTarih, k.hesap);
    final metin = Theme.of(context).textTheme;
    Widget kutu(String etiket, String deger, {bool vurgu = false}) => SizedBox(
          width: 170,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(etiket, style: metin.bodySmall),
            Text(deger, style: metin.headlineSmall?.copyWith(color: vurgu ? Renkler.kritik : Renkler.metin)),
          ]),
        );
    return Panel(
      baslik: 'Hukuk talepleri',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 16, runSpacing: 16, children: [
          kutu('Açık', '${p.acik}'),
          kutu('Geciken', '${p.geciken}', vurgu: p.geciken > 0),
          kutu('Kapanan', '${p.kapanan}'),
          kutu('SLA uyumu', p.slaUyumu == null ? '—' : '%${p.slaUyumu}'),
          kutu('Ort. çözüm', p.ortalamaCozum == null ? '—' : '${p.ortalamaCozum!.toStringAsFixed(1)} iş günü'),
        ]),
        if (p.acikTurlere.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Cubuklar(anahtar: 'rapor-talep-tur', degerler: [
            for (final e in p.acikTurlere.entries) (e.key.ad, e.value, Renkler.bilgi),
          ]),
        ],
      ]),
    );
  }
}

class _SozlesmePaneli extends StatelessWidget {
  const _SozlesmePaneli({required this.k});

  final KurumsalDepo k;

  @override
  Widget build(BuildContext context) {
    final o = Raporlar.sozlesmeOzeti(k.gorunurSozlesmeler, k.bugunTarih);
    return Panel(
      baslik: 'Sözleşmeler',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in RiskSeviyesi.values.reversed)
            DurumRozeti('${o.risk[r]} ${r.ad.toLowerCase()} risk', riskRozeti(r)),
          if (o.taranmamis > 0) DurumRozeti('${o.taranmamis} taranmamış', RozetTuru.notr),
        ]),
        const SizedBox(height: 16),
        Text('Önümüzdeki 12 ayda biten sözleşmeler', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (o.bitisAylari.isEmpty)
          const Text('Yok.')
        else
          _Cubuklar(anahtar: 'rapor-sozlesme-bitis', degerler: [
            for (final e in (o.bitisAylari.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
              (e.key, e.value, Renkler.uyari),
          ]),
      ]),
    );
  }
}
