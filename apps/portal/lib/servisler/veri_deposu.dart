import 'package:flutter/foundation.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import 'sunucu_senkronu.dart';

/// Kaydedilmiş iş kabul kararı.
class KayitliKarar {
  const KayitliKarar({required this.adaylar, required this.rapor, required this.karar, required this.zaman});

  final List<AdayTaraf> adaylar;
  final CikarCatismasiRaporu rapor;
  final CikarCatismasiKarari karar;
  final DateTime zaman;
}

/// Geliştirme için bellekte çalışan veri deposu. Sunucu hazır olduğunda aynı
/// yüzeyi koruyan Serverpod uygulamasıyla değiştirilecek.
class BellekVeriDeposu extends ChangeNotifier {
  BellekVeriDeposu(this.kiraciId);

  /// Demo verisiyle doldurulmuş depo. [avukatId] oturumdaki kullanıcıdır.
  factory BellekVeriDeposu.demo({required String kiraciId, required String avukatId}) {
    final d = BellekVeriDeposu(kiraciId);
    Kisi k(String id, KisiTuru tur, String ad, {String? no, String? eposta}) =>
        Kisi(id: id, kiraciId: kiraciId, tur: tur, ad: ad, kimlikNo: no, eposta: eposta);

    d._kisiler.addAll([
      k('abc', KisiTuru.tuzel, 'ABC Gıda Sanayi ve Ticaret A.Ş.', no: '1234567890', eposta: 'hukuk@abcgida.com.tr'),
      k('abcHolding', KisiTuru.tuzel, 'ABC Holding A.Ş.'),
      k('ayse', KisiTuru.gercek, 'Ayşe Kara', no: '10000000146'),
      k('demirci', KisiTuru.gercek, 'Mehmet Demirci'),
      k('delta', KisiTuru.tuzel, 'Delta İnşaat Ltd. Şti.', no: '9876543217'),
      k('orman', KisiTuru.tuzel, 'Orman Enerji A.Ş.'),
    ]);
    d._iliskiler.add(const KisiIliskisi(kisiA: 'abcHolding', kisiB: 'abc', tur: IliskiTuru.istirak));
    d._dosyaKayitlari.addAll(const [
      DosyaTarafKaydi(dosyaId: 'd1', dosyaAdi: 'ABC Gıda - Tedarik alacağı', kisiId: 'abc', sifat: TarafSifati.muvekkil),
      DosyaTarafKaydi(dosyaId: 'd1', dosyaAdi: 'ABC Gıda - Tedarik alacağı', kisiId: 'delta', sifat: TarafSifati.karsiTaraf),
      DosyaTarafKaydi(dosyaId: 'd2', dosyaAdi: 'Kara - İşe iade', kisiId: 'ayse', sifat: TarafSifati.muvekkil),
      DosyaTarafKaydi(dosyaId: 'd2', dosyaAdi: 'Kara - İşe iade', kisiId: 'demirci', sifat: TarafSifati.karsiTaraf),
      DosyaTarafKaydi(dosyaId: 'd3', dosyaAdi: 'Holding birleşme danışmanlığı', kisiId: 'abcHolding', sifat: TarafSifati.muvekkil),
      DosyaTarafKaydi(
          dosyaId: 'd4', dosyaAdi: 'Orman Enerji iç soruşturma', kisiId: 'orman', sifat: TarafSifati.muvekkil, gizli: true),
    ]);
    d._vekaletnameler.addAll([
      Vekaletname(
        id: 'v1',
        kiraciId: kiraciId,
        muvekkilId: 'abc',
        avukatlar: {avukatId},
        duzenlemeTarihi: Tarih(2025, 3, 14),
        noter: 'Kadıköy 5. Noterliği',
        yevmiyeNo: '04512',
        ozelYetkiler: const {OzelYetki.sulh, OzelYetki.tevkil, OzelYetki.ahzuKabz, OzelYetki.ibra},
        asilEvrakYeri: 'Arşiv dolabı 2, klasör 7',
      ),
      Vekaletname(
        id: 'v2',
        kiraciId: kiraciId,
        muvekkilId: 'ayse',
        avukatlar: {avukatId},
        duzenlemeTarihi: Tarih(2026, 2, 2),
        noter: 'Beşiktaş 12. Noterliği',
        yevmiyeNo: '00987',
        genel: false,
        dosyalar: const {'d2'},
      ),
    ]);
    d._operasyonDemosu(avukatId, Tarih.from(DateTime.now()));
    d._finansVeBelgeDemosu(avukatId, Tarih.from(DateTime.now()));
    return d;
  }

  final String kiraciId;
  final List<Kisi> _kisiler = [];
  final List<KisiIliskisi> _iliskiler = [];
  final List<DosyaTarafKaydi> _dosyaKayitlari = [];
  final List<Vekaletname> _vekaletnameler = [];
  final List<KayitliKarar> _kararlar = [];
  int _sayac = 0;

  List<Kisi> get kisiler => List.unmodifiable(_kisiler);
  List<KisiIliskisi> get iliskiler => List.unmodifiable(_iliskiler);

  /// Sunucu kimlikleri (ilişki silmek için); yerelde boş.
  final Map<KisiIliskisi, String> _iliskiIdleri = Map.identity();

  List<KisiIliskisi> kisininIliskileri(String kisiId) =>
      _iliskiler.where((i) => i.kisiA == kisiId || i.kisiB == kisiId).toList();

  /// Kartın güncellenmesi; tür değişmez. Ad değişirse eski ad unvan geçmişine yazılır (sunucuda veritabanı yazar).
  Future<String?> kisiGuncelle(Kisi yeni) => sunucudaVeyaYerelde(
        sunucuda: (u) => u.kisiGuncelle(yeni),
        yerelde: () {
          final i = _kisiler.indexWhere((k) => k.id == yeni.id);
          if (i < 0) return 'Kişi bulunamadı.';
          final eski = _kisiler[i];
          if (yeni.ad.trim().isEmpty) return 'Ad boş olamaz.';
          final ad = yeni.ad.trim();
          // Boşaltılan alanlar da boşalsın diye kopya() yerine yeni kart kurulur; tür ve geçmiş eskiden gelir.
          final guncel = Kisi(
            id: eski.id,
            kiraciId: eski.kiraciId,
            tur: eski.tur,
            ad: ad,
            kimlikNo: yeni.kimlikNo,
            mersisNo: yeni.mersisNo,
            eposta: yeni.eposta,
            telefon: yeni.telefon,
            adres: yeni.adres,
            iletisimTercihi: yeni.iletisimTercihi,
            notlar: yeni.notlar,
            unvanGecmisi: ad == eski.ad
                ? eski.unvanGecmisi
                : [...eski.unvanGecmisi, UnvanKaydi(unvan: eski.ad, gecerlilikBitisi: Tarih.from(DateTime.now()))],
          );
          _kisiler[i] = guncel;
          _kaydet(DenetimIslemi.degisiklik, 'kisi', yeni.id, eski.ad == guncel.ad ? 'Kart güncellendi' : 'Unvan: ${eski.ad} → ${guncel.ad}');
          notifyListeners();
          return null;
        },
      );

  Future<String?> iliskiEkle(String kisiA, String kisiB, IliskiTuru tur) => sunucudaVeyaYerelde(
        sunucuda: (u) => u.iliskiEkle(kisiA: kisiA, kisiB: kisiB, tur: tur),
        yerelde: () {
          if (kisiA == kisiB) return 'Kişi kendisiyle ilişkilendirilemez.';
          final mevcut = _iliskiler.any((i) => i.tur == tur && {i.kisiA, i.kisiB}.containsAll({kisiA, kisiB}));
          if (mevcut) return 'Bu ilişki zaten kayıtlı.';
          _iliskiler.add(KisiIliskisi(kisiA: kisiA, kisiB: kisiB, tur: tur));
          _kaydet(DenetimIslemi.olusturma, 'kisi_iliski', '$kisiA-$kisiB', tur.name);
          notifyListeners();
          return null;
        },
      );

  Future<String?> iliskiSil(KisiIliskisi i) {
    final id = _iliskiIdleri[i];
    return sunucudaVeyaYerelde(
      sunucuda: (u) => id == null ? Future.error(Exception('İlişki sunucuda bulunamadı.')) : u.iliskiSil(id),
      yerelde: () {
        if (!_iliskiler.remove(i)) return 'İlişki bulunamadı.';
        _kaydet(DenetimIslemi.silme, 'kisi_iliski', '${i.kisiA}-${i.kisiB}', i.tur.name);
        notifyListeners();
        return null;
      },
    );
  }
  List<DosyaTarafKaydi> get dosyaKayitlari => List.unmodifiable(_dosyaKayitlari);
  List<Vekaletname> get vekaletnameler => List.unmodifiable(_vekaletnameler);
  List<KayitliKarar> get kararlar => List.unmodifiable(_kararlar);

  Kisi? kisi(String id) {
    for (final k in _kisiler) {
      if (k.id == id) return k;
    }
    return null;
  }

  int dosyaSayisi(String kisiId) => _dosyaKayitlari.where((d) => d.kisiId == kisiId).map((d) => d.dosyaId).toSet().length;

  List<Kisi> ara(String sorgu) {
    final s = sorgu.trim();
    if (s.isEmpty) return kisiler;
    final n = IsimEslestirme.normallestir(s);
    return _kisiler
        .where((k) =>
            (k.kimlikNo?.contains(s) ?? false) ||
            k.tumAdlar.any((a) => IsimEslestirme.normallestir(a).contains(n)) ||
            IsimEslestirme.benzerlik(s, k.ad) >= IsimEslestirme.varsayilanEsik)
        .toList();
  }

  CikarCatismasiTarayici get tarayici =>
      CikarCatismasiTarayici(kisiler: _kisiler, iliskiler: _iliskiler, dosyaKayitlari: _dosyaKayitlari);

  Kisi kisiEkle({
    required KisiTuru tur,
    required String ad,
    String? kimlikNo,
    String? eposta,
    String? telefon,
  }) {
    _sayac++;
    final yeni = Kisi(
      id: 'yeni$_sayac',
      kiraciId: kiraciId,
      tur: tur,
      ad: ad.trim(),
      kimlikNo: (kimlikNo?.trim().isEmpty ?? true) ? null : kimlikNo!.trim(),
      eposta: (eposta?.trim().isEmpty ?? true) ? null : eposta!.trim(),
      telefon: (telefon?.trim().isEmpty ?? true) ? null : telefon!.trim(),
    );
    _kisiler.add(yeni);
    _kaydet(DenetimIslemi.olusturma, 'kisi', yeni.id, yeni.ad);
    notifyListeners();
    return yeni;
  }

  void kararKaydet(KayitliKarar karar) {
    _kararlar.add(karar);
    _kaydet(DenetimIslemi.kararKaydi, 'is_kabul', karar.adaylar.map((a) => a.ad).join(', '),
        '${karar.karar.tur.name}: ${karar.karar.gerekce}');
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Dosya, süre, görev, tebligat, duruşma
  // ---------------------------------------------------------------------------

  final List<Dosya> _dosyalar = [];
  final List<SureKaydi> _sureler = [];
  final List<Gorev> _gorevler = [];
  final List<Tebligat> _tebligatlar = [];
  final List<Durusma> _durusmalar = [];
  final Map<String, String> _kullaniciAdlari = {};
  late final NumaraSerisi _dosyaSerisi = NumaraSerisi(yil: DateTime.now().year);

  /// Geliştirmede taslak süre kuralları kullanılabilir; ekranda uyarı gösterilir.
  final SureHesaplayici hesaplayici = SureHesaplayici(
    TurkiyeTatilleri.takvim(TurkiyeTatilleri.diniBayramVerisiOlanYillar),
    ayarlar: const HesapAyarlari(taslakKuralaIzinVer: true),
  );

  List<SureKaydi> get sureler => List.unmodifiable(_sureler);
  List<Gorev> get gorevler => List.unmodifiable(_gorevler);
  List<Tebligat> get tebligatlar => List.unmodifiable(_tebligatlar);
  List<Durusma> get durusmalar => List.unmodifiable(_durusmalar);

  String kullaniciAdi(String id) => id.trim().isEmpty ? '(atanmamış)' : _kullaniciAdlari[id] ?? id;

  Dosya? dosya(String id) {
    for (final d in _dosyalar) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Tek kapı: yalnızca kullanıcının görebileceği dosyalar.
  List<Dosya> gorunurDosyalar(Aktor aktor) => const YetkiDenetcisi()
      .gorunurOlanlar(
          aktor,
          _dosyalar,
          (d) => KorunanNesne(
              kiraciId: d.kiraciId, gizli: d.gizli, atananKullanicilar: d.tumEkip, etikDuvar: etikDuvar.engelliler(d.id)))
      .toList();

  final EtikDuvarDefteri etikDuvar = EtikDuvarDefteri();

  /// Hata varsa mesajı döner.
  String? etikDuvarKur(String dosyaId, String kullanici, String gerekce) {
    final d = dosya(dosyaId);
    if (d == null) return 'Dosya bulunamadı.';
    try {
      etikDuvar.kur(
        dosyaId: dosyaId,
        kullanici: kullanici,
        gerekce: gerekce,
        kuran: aktifKullanici,
        tarih: Tarih.from(DateTime.now()),
        dosyaEkibi: d.tumEkip,
      );
      _kaydet(DenetimIslemi.degisiklik, 'etik_duvar', dosyaId, '${kullaniciAdi(kullanici)} engellendi: $gerekce');
      notifyListeners();
      return null;
    } on ArgumentError catch (e) {
      return '${e.message}';
    } on StateError catch (e) {
      return e.message;
    }
  }

  String? etikDuvarKaldir(String dosyaId, String kullanici, String gerekce) {
    try {
      etikDuvar.kaldir(
          dosyaId: dosyaId, kullanici: kullanici, gerekce: gerekce, kaldiran: aktifKullanici, tarih: Tarih.from(DateTime.now()));
      _kaydet(DenetimIslemi.degisiklik, 'etik_duvar', dosyaId, '${kullaniciAdi(kullanici)} engeli kaldırıldı: $gerekce');
      notifyListeners();
      return null;
    } on ArgumentError catch (e) {
      return '${e.message}';
    } on StateError catch (e) {
      return e.message;
    }
  }

  Map<String, List<String>> get dosyaTaraflari {
    final sonuc = <String, List<String>>{};
    for (final k in _dosyaKayitlari) {
      final ad = kisi(k.kisiId)?.ad;
      if (ad != null) sonuc.putIfAbsent(k.dosyaId, () => []).add(ad);
    }
    return sonuc;
  }

  List<SureKaydi> dosyaSureleri(String dosyaId) => _sureler.where((s) => s.dosyaId == dosyaId).toList()
    ..sort((a, b) => a.sonGun.compareTo(b.sonGun));

  List<Gorev> dosyaGorevleri(String dosyaId) => _gorevler.where((g) => g.dosyaId == dosyaId).toList();

  List<Tebligat> dosyaTebligatlari(String dosyaId) => _tebligatlar.where((t) => t.dosyaId == dosyaId).toList();

  List<Tebligat> get eslesmeyenTebligatlar =>
      _tebligatlar.where((t) => t.eslesmeDurumu != EslesmeDurumu.eslesti).toList();

  List<SureUyarisi> uyarilar(Tarih bugun) => const EskalasyonMotoru().degerlendir(_sureler, bugun);

  List<Cakisma> get cakismalar => CakismaKontrolu.bul(_durusmalar);

  /// Tebligatı kaydeder. Aynı evrak ikinci kez gelirse çoğaltmaz, mevcut kaydı döner.
  ({Tebligat tebligat, bool mukerrer}) tebligatEkle(Tebligat yeni) {
    for (final t in _tebligatlar) {
      if (t.tekillikAnahtari == yeni.tekillikAnahtari) return (tebligat: t, mukerrer: true);
    }
    final oneriler = TebligatEslestirici.oner(yeni, _dosyalar, dosyaTaraflari: dosyaTaraflari);
    final otomatik = TebligatEslestirici.otomatikEslesme(oneriler);
    final kayit = otomatik != null
        ? yeni.dosyayaBagla(otomatik.id)
        : Tebligat(
            id: yeni.id,
            kiraciId: yeni.kiraciId,
            kanal: yeni.kanal,
            ulasmaTarihi: yeni.ulasmaTarihi,
            tebligTarihi: yeni.tebligTarihi,
            gonderen: yeni.gonderen,
            konu: yeni.konu,
            esasNo: yeni.esasNo,
            taraflar: yeni.taraflar,
            belgeOzeti: yeni.belgeOzeti,
            eslesmeDurumu: oneriler.isEmpty ? EslesmeDurumu.eslesmedi : EslesmeDurumu.onerildi,
          );
    _tebligatlar.add(kayit);
    _kaydet(DenetimIslemi.olusturma, 'tebligat', kayit.id, '${kayit.konu} · ${kayit.gonderen}');
    notifyListeners();
    return (tebligat: kayit, mukerrer: false);
  }

  List<EslesmeOnerisi> tebligatOnerileri(Tebligat t) =>
      TebligatEslestirici.oner(t, _dosyalar, dosyaTaraflari: dosyaTaraflari);

  void tebligatBagla(String tebligatId, String dosyaId) {
    final i = _tebligatlar.indexWhere((t) => t.id == tebligatId);
    if (i < 0) return;
    _tebligatlar[i] = _tebligatlar[i].dosyayaBagla(dosyaId);
    _kaydet(DenetimIslemi.degisiklik, 'tebligat', tebligatId, 'Dosyaya bağlandı: $dosyaId');
    notifyListeners();
  }

  String yeniId(String onek) => '$onek${++_sayac}';

  /// Tebliğ tarihinden süre hesaplar; asıl ve yedek sorumlu dosyadan gelir.
  SureKaydi sureOlustur({
    required String dosyaId,
    required SureKurali kural,
    required Tarih baslangic,
    required String olusturan,
    String? aciklama,
    String? tebligatId,
  }) {
    final d = dosya(dosyaId)!;
    final kayit = SureKaydi(
      id: yeniId('s'),
      dosyaId: dosyaId,
      aciklama: aciklama ?? '${kural.ad} · ${d.baslik}',
      sonuc: hesaplayici.hesapla(kural: kural, baslangic: baslangic),
      olusturan: olusturan,
      olusturmaTarihi: Tarih.from(DateTime.now()),
      asilSorumlu: d.sorumlu,
      yedekSorumlu: d.yedekSorumlu,
      tetikleyenTebligatId: tebligatId,
    );
    _sureler.add(kayit);
    _kaydet(DenetimIslemi.olusturma, 'sure', kayit.id, '${kayit.aciklama} · son gün ${kayit.sonGun.turkceBicim}');
    _gorevler.add(Gorev(
      id: yeniId('g'),
      baslik: kural.ad,
      atanan: d.sorumlu,
      yedek: d.yedekSorumlu,
      dosyaId: dosyaId,
      sonTarih: kayit.sonGun,
      oncelik: GorevOnceligi.kritik,
      kaynakSureId: kayit.id,
    ));
    notifyListeners();
    return kayit;
  }

  void sureGuncelle(SureKaydi yeni) {
    final i = _sureler.indexWhere((s) => s.id == yeni.id);
    if (i >= 0) {
      _sureler[i] = yeni;
      _kaydet(yeni.durum == SureDurumu.teyitli ? DenetimIslemi.sureTeyit : DenetimIslemi.degisiklik, 'sure', yeni.id,
          '${yeni.durum.ad}${yeni.tamamlanmaKaniti != null ? ' · kanıt: ${yeni.tamamlanmaKaniti}' : ''}');
      notifyListeners();
    }
  }

  void gorevGuncelle(Gorev yeni) {
    final i = _gorevler.indexWhere((g) => g.id == yeni.id);
    if (i >= 0) {
      _gorevler[i] = yeni;
      _kaydet(DenetimIslemi.degisiklik, 'gorev', yeni.id, '${yeni.baslik} · ${yeni.durum.name}');
      notifyListeners();
    }
  }

  void _operasyonDemosu(String av1, Tarih bugun) {
    const av2 = 'demo-av2';
    const stj = 'demo-stj';
    _kullaniciAdlari.addAll({av1: 'Siz', av2: 'Av. Mert Şahin', stj: 'Stj. Av. Elif Koç'});
    zaman = ZamanDefteri(
      tarife: SaatlikUcretTarifesi(
        kullanici: {av1: Para.tl(3000), av2: Para.tl(2500), stj: Para.tl(1000)},
        varsayilan: Para.tl(2000),
      ),
    );

    Dosya dosyaOlustur(String id, DosyaTuru tur, String baslik, String sorumlu, String? yedek,
            {String? mahkeme, String? esas, bool gizli = false, DosyaAsamasi asama = DosyaAsamasi.ilkDerece}) =>
        Dosya(
          id: id,
          kiraciId: kiraciId,
          icNo: _dosyaSerisi.sonraki(),
          tur: tur,
          baslik: baslik,
          sorumlu: sorumlu,
          yedekSorumlu: yedek,
          ekip: {stj},
          mahkeme: mahkeme,
          esasNo: esas,
          gizli: gizli,
          asama: asama,
          acilisTarihi: bugun.gunEkle(-60),
        );

    _dosyalar.addAll([
      dosyaOlustur('d1', DosyaTuru.hukuk, 'ABC Gıda - Tedarik alacağı', av1, av2,
          mahkeme: 'İstanbul 5. Asliye Ticaret Mahkemesi', esas: '2026/123 E.'),
      dosyaOlustur('d2', DosyaTuru.hukuk, 'Kara - İşe iade', av1, av2,
          mahkeme: 'İstanbul 12. İş Mahkemesi', esas: '2026/456 E.'),
      dosyaOlustur('d3', DosyaTuru.danismanlik, 'Holding birleşme danışmanlığı', av2, av1,
          asama: DosyaAsamasi.onDegerlendirme),
      dosyaOlustur('d4', DosyaTuru.danismanlik, 'Orman Enerji iç soruşturma', av2, null,
          gizli: true, asama: DosyaAsamasi.onDegerlendirme),
    ]);

    SureKurali kural(String kod) => KuralKatalogu.bul(kod)!;
    SureKaydi sure(String id, String dosyaId, String kod, Tarih son, String asil, String? yedek,
            {SureDurumu durum = SureDurumu.teyitli, Tarih? olusturma, String olusturan = stj}) =>
        SureKaydi(
          id: id,
          dosyaId: dosyaId,
          aciklama: '${kural(kod).ad} · ${dosya(dosyaId)!.baslik}',
          sonuc: SureSonucu(
            kural: kural(kod),
            baslangic: son.gunEkle(-14),
            sonGun: son,
            adimlar: [HesapAdimi(son, 'Demo verisi')],
            uyarilar: const [],
          ),
          olusturan: olusturan,
          olusturmaTarihi: olusturma ?? bugun.gunEkle(-3),
          asilSorumlu: asil,
          yedekSorumlu: yedek,
          durum: durum,
          teyitEden: durum == SureDurumu.teyitli ? av1 : null,
        );

    _sureler.addAll([
      sure('s1', 'd1', 'HMK_ISTINAF', bugun.gunEkle(1), av1, av2),
      sure('s2', 'd2', 'HMK_CEVAP_DILEKCESI', bugun.gunEkle(9), av1, av2,
          durum: SureDurumu.teyitBekliyor, olusturma: bugun.gunEkle(-2)),
      sure('s3', 'd3', 'IIK_ODEME_EMRINE_ITIRAZ', bugun.gunEkle(7), av2, av1),
    ]);

    var n = 0;
    _gorevler.addAll(GorevSablonu.isDavasiAcilisi.uygula(
      dosyaId: 'd2',
      baslangic: bugun.gunEkle(-6),
      roller: {'sorumlu': av1, 'yedek': av2, 'stajyer': stj},
      idUret: () => 'dg${++n}',
    ));

    final ikiGunSonra = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day + 2);
    _durusmalar.addAll([
      Durusma(
        id: 'du1',
        dosyaId: 'd1',
        baslangic: ikiGunSonra.add(const Duration(hours: 10)),
        yer: 'Çağlayan Adliyesi',
        katilan: av1,
      ),
      Durusma(
        id: 'du2',
        dosyaId: 'd2',
        baslangic: ikiGunSonra.add(const Duration(hours: 10, minutes: 30)),
        yer: 'Çağlayan Adliyesi',
        katilan: av1,
      ),
      Durusma(
        id: 'du3',
        dosyaId: 'd2',
        baslangic: ikiGunSonra.add(const Duration(days: 3, hours: 14)),
        yer: 'Kartal Adliyesi',
        katilan: av1,
        tur: 'Bilirkişi incelemesi',
      ),
    ]);

    _tebligatlar.addAll([
      Tebligat(
        id: 't1',
        kiraciId: kiraciId,
        kanal: TebligatKanali.uyap,
        ulasmaTarihi: bugun.gunEkle(-10),
        gonderen: 'İstanbul 5. Asliye Ticaret Mahkemesi',
        konu: 'Gerekçeli karar',
        esasNo: '2026/123 E.',
        dosyaId: 'd1',
        eslesmeDurumu: EslesmeDurumu.eslesti,
      ),
      Tebligat(
        id: 't2',
        kiraciId: kiraciId,
        kanal: TebligatKanali.uets,
        ulasmaTarihi: bugun.gunEkle(-1),
        gonderen: 'İstanbul 12. İş Mahkemesi',
        konu: 'Bilirkişi raporu',
        taraflar: const ['Mehmet Demirci'],
        eslesmeDurumu: EslesmeDurumu.onerildi,
      ),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Finans ve belgeler
  // ---------------------------------------------------------------------------

  final List<CariHareket> _cari = [];
  final EmanetHesabi emanet = EmanetHesabi();
  final List<Belge> _belgeler = [];
  final Map<String, String> _belgeMetinleri = {};

  List<CariHareket> cariHareketler(String muvekkilId) =>
      _cari.where((h) => h.muvekkilId == muvekkilId).toList()..sort((a, b) => b.tarih.compareTo(a.tarih));

  CariOzet cariOzet(String muvekkilId) => CariOzet(_cari.where((h) => h.muvekkilId == muvekkilId));

  /// Cari veya emanet hareketi olan müvekkiller.
  List<Kisi> get finansMuvekkilleri {
    final idler = {..._cari.map((h) => h.muvekkilId), ...emanet.hareketler.map((h) => h.muvekkilId)};
    return [for (final id in idler) if (kisi(id) != null) kisi(id)!]..sort((a, b) => a.ad.compareTo(b.ad));
  }

  void cariEkle({required String muvekkilId, required CariHareketTuru tur, required Para tutar, required String aciklama, String? dosyaId}) {
    _cari.add(CariHareket(
      id: yeniId('c'),
      muvekkilId: muvekkilId,
      dosyaId: dosyaId,
      tur: tur,
      tutar: tutar,
      tarih: Tarih.from(DateTime.now()),
      aciklama: aciklama,
    ));
    _kaydet(DenetimIslemi.olusturma, 'cari', muvekkilId, '${tur.ad} · ${tutar.bicimli}');
    notifyListeners();
  }

  /// Hata varsa mesajı döner.
  String? emanetEkle(EmanetHareketi h) {
    try {
      emanet.ekle(h);
      _kaydet(DenetimIslemi.olusturma, 'emanet', h.id, '${h.tur.ad} · ${h.tutar.bicimli}');
      notifyListeners();
      return null;
    } on StateError catch (e) {
      return e.message;
    } on ArgumentError catch (e) {
      return '${e.message}';
    }
  }

  String? dosyaMuvekkili(String dosyaId) {
    for (final k in _dosyaKayitlari) {
      if (k.dosyaId == dosyaId && k.sifat == TarafSifati.muvekkil) return k.kisiId;
    }
    return null;
  }

  String? dosyaKarsiTarafi(String dosyaId) {
    for (final k in _dosyaKayitlari) {
      if (k.dosyaId == dosyaId && k.sifat == TarafSifati.karsiTaraf) return k.kisiId;
    }
    return null;
  }

  List<Belge> dosyaBelgeleri(String dosyaId) => _belgeler.where((b) => b.dosyaId == dosyaId).toList();

  // ---------------------------------------------------------------------------
  // Müvekkil portalı
  // ---------------------------------------------------------------------------

  final Set<String> _portalDosyalari = {};
  final Set<String> _paylasilanBelgeler = {};
  final List<PortalMesaji> _mesajlar = [];

  bool portaldaMi(String dosyaId) => _portalDosyalari.contains(dosyaId);

  /// Sunucuya bağlıyken yazışmalar bu kancadan geçer.
  MesajUzak? mesajUzak;

  /// Yazışma işlemi: sunucu bağlıysa sunucuda, değilse yerelde. Hata varsa mesajı döner.
  Future<String?> mesajIslemi({
    required Future<void> Function(MesajUzak uzak) sunucuda,
    required String? Function() yerelde,
  }) async {
    final u = mesajUzak;
    if (u == null) return yerelde();
    try {
      await sunucuda(u);
      return null;
    } on Exception catch (e) {
      return '$e';
    }
  }

  void sunucuPortalVerisiniYukle({
    required Set<String> portalDosyalari,
    required Set<String> paylasilanBelgeler,
    required List<PortalMesaji> mesajlar,
  }) {
    _portalDosyalari
      ..clear()
      ..addAll(portalDosyalari);
    _paylasilanBelgeler
      ..clear()
      ..addAll(paylasilanBelgeler);
    _mesajlar
      ..clear()
      ..addAll(mesajlar);
    notifyListeners();
  }
  bool belgePaylasildiMi(String belgeId) => _paylasilanBelgeler.contains(belgeId);

  void portalPaylas(String dosyaId, bool paylas) {
    paylas ? _portalDosyalari.add(dosyaId) : _portalDosyalari.remove(dosyaId);
    _kaydet(DenetimIslemi.paylasim, 'dosya', dosyaId, paylas ? 'Müvekkil portalında paylaşıldı' : 'Portal paylaşımı kaldırıldı');
    notifyListeners();
  }

  void belgePaylas(String belgeId, bool paylas) {
    paylas ? _paylasilanBelgeler.add(belgeId) : _paylasilanBelgeler.remove(belgeId);
    _kaydet(DenetimIslemi.paylasim, 'belge', belgeId, paylas ? 'Müvekkille paylaşıldı' : 'Müvekkil paylaşımı kaldırıldı');
    notifyListeners();
  }

  List<PortalMesaji> dosyaMesajlari(String dosyaId) =>
      _mesajlar.where((m) => m.dosyaId == dosyaId).toList()..sort((a, b) => a.zaman.compareTo(b.zaman));

  /// Büronun okumadığı müvekkil mesajları.
  int okunmamisMuvekkilMesaji(String dosyaId) =>
      _mesajlar.where((m) => m.dosyaId == dosyaId && m.muvekkildenMi && !m.okundu).length;

  /// Hata varsa mesajı döner. Müvekkil yalnızca portalda paylaşılan kendi dosyasına yazabilir.
  String? mesajGonder({required String dosyaId, required String metin, required bool muvekkildenMi, String? muvekkilKisiId}) {
    final hata = PortalMesaji.dogrula(metin);
    if (hata != null) return hata;
    if (muvekkildenMi && (!portaldaMi(dosyaId) || dosyaMuvekkili(dosyaId) != muvekkilKisiId)) {
      return 'Bu dosyaya mesaj gönderme yetkiniz yok.';
    }
    final m = PortalMesaji(
      id: yeniId('m'),
      dosyaId: dosyaId,
      gonderen: aktifKullanici,
      muvekkildenMi: muvekkildenMi,
      metin: metin.trim(),
      zaman: DateTime.now(),
    );
    _mesajlar.add(m);
    _kaydet(DenetimIslemi.olusturma, 'mesaj', dosyaId, muvekkildenMi ? 'Müvekkil mesajı' : 'Müvekkile mesaj');
    notifyListeners();
    return null;
  }

  /// Karşı taraftan gelen mesajları okundu işaretler.
  void mesajlariOku(String dosyaId, {required bool muvekkilOkuyor}) {
    var degisti = false;
    for (var i = 0; i < _mesajlar.length; i++) {
      final m = _mesajlar[i];
      if (m.dosyaId == dosyaId && !m.okundu && m.muvekkildenMi != muvekkilOkuyor) {
        _mesajlar[i] = m.okunduIsaretle();
        degisti = true;
      }
    }
    if (degisti) notifyListeners();
  }

  Set<String> muvekkilDosyalari(String kisiId) => {
        for (final k in _dosyaKayitlari)
          if (k.kisiId == kisiId && k.sifat == TarafSifati.muvekkil) k.dosyaId,
      };

  List<MuvekkilDosyaOzeti> muvekkilOzetleri(String kisiId) => MuvekkilPortali.ozetler(
        muvekkilinDosyalari: muvekkilDosyalari(kisiId),
        portaldaPaylasilan: _portalDosyalari,
        dosyalar: _dosyalar,
        durusmalar: _durusmalar,
        belgeler: _belgeler,
        paylasilanBelgeler: _paylasilanBelgeler,
        mesajlar: _mesajlar,
        simdi: DateTime.now(),
      );

  List<Dosya> get tumDosyalar => List.unmodifiable(_dosyalar);

  // ---------------------------------------------------------------------------
  // Sunucu bağlantısı
  // ---------------------------------------------------------------------------

  /// Sunucuya bağlıyken dosya ve süre işlemleri bu kancadan geçer.
  UzakIslemler? uzak;

  void kullaniciAdlariniYukle(Map<String, String> adlar) {
    _kullaniciAdlari
      ..clear()
      ..addAll(adlar);
  }

  /// Sunucudan gelen dosya ve süreleri yerel önbelleğe yazar (öncekilerin yerine).
  void sunucuVerisiniYukle({required List<Dosya> dosyalar, required List<SureKaydi> sureler, List<Belge> belgeler = const []}) {
    _dosyalar
      ..clear()
      ..addAll(dosyalar);
    _belgeler
      ..clear()
      ..addAll(belgeler);
    _sureler
      ..clear()
      ..addAll(sureler);
    notifyListeners();
  }

  /// Sunucudan gelen kişi, finans, zaman ve icra verisini önbelleğe yazar (öncekilerin yerine).
  void sunucuIsVerisiniYukle({
    required List<Kisi> kisiler,
    List<(String, KisiIliskisi)> iliskiler = const [],
    required List<CariHareket> cari,
    required List<EmanetHareketi> emanetHareketleri,
    required List<ZamanKaydi> zamanKayitlari,
    required List<(IcraDosyasi, FaizTuru, double?)> icra,
  }) {
    _kisiler
      ..clear()
      ..addAll(kisiler);
    _iliskiler
      ..clear()
      ..addAll(iliskiler.map((e) => e.$2));
    _iliskiIdleri
      ..clear()
      ..addEntries(iliskiler.map((e) => MapEntry(e.$2, e.$1)));
    _cari
      ..clear()
      ..addAll(cari);
    emanet.yukle(emanetHareketleri);
    zaman.yukle(zamanKayitlari);
    _icra.clear();
    _icraFaizTuru.clear();
    _icraAkdiOran.clear();
    for (final (i, faiz, oran) in icra) {
      _icra.add(i);
      _icraFaizTuru[i.id] = faiz;
      if (oran != null) _icraAkdiOran[i.id] = oran;
    }
    notifyListeners();
  }

  /// Sunucudan gelen büro işleri verisini önbelleğe yazar. Eşleşmemiş tebligatlar için öneri durumu yerelde hesaplanır.
  void sunucuBuroVerisiniYukle({
    required List<DosyaTarafKaydi> taraflar,
    required List<Gorev> gorevler,
    required List<Durusma> durusmalar,
    required List<Tebligat> tebligatlar,
    required List<Vekaletname> vekaletnameler,
  }) {
    _dosyaKayitlari
      ..clear()
      ..addAll(taraflar);
    _gorevler
      ..clear()
      ..addAll(gorevler);
    _durusmalar
      ..clear()
      ..addAll(durusmalar);
    _vekaletnameler
      ..clear()
      ..addAll(vekaletnameler);
    _tebligatlar.clear();
    for (final t in tebligatlar) {
      final oneriVar = t.dosyaId == null && TebligatEslestirici.oner(t, _dosyalar, dosyaTaraflari: dosyaTaraflari).isNotEmpty;
      _tebligatlar.add(oneriVar
          ? Tebligat(
              id: t.id,
              kiraciId: t.kiraciId,
              kanal: t.kanal,
              ulasmaTarihi: t.ulasmaTarihi,
              tebligTarihi: t.tebligTarihi,
              gonderen: t.gonderen,
              konu: t.konu,
              esasNo: t.esasNo,
              taraflar: t.taraflar,
              belgeOzeti: t.belgeOzeti,
              eslesmeDurumu: EslesmeDurumu.onerildi,
            )
          : t);
    }
    notifyListeners();
  }

  /// Sunucu bağlıyken işlemi sunucuda, değilse yerelde yapar. Hata varsa kullanıcıya gösterilecek mesajı döner.
  Future<String?> sunucudaVeyaYerelde({
    required Future<void> Function(UzakIslemler uzak) sunucuda,
    required String? Function() yerelde,
  }) async {
    final u = uzak;
    if (u == null) return yerelde();
    try {
      await sunucuda(u);
      return null;
    } on Exception catch (e) {
      return '$e';
    }
  }

  // ---------------------------------------------------------------------------
  // İcra takipleri
  // ---------------------------------------------------------------------------

  final List<IcraDosyasi> _icra = [];
  final Map<String, FaizTuru> _icraFaizTuru = {};

  List<IcraDosyasi> get icraDosyalari => List.unmodifiable(_icra);

  IcraDosyasi? icraDosyasi(String id) {
    for (final i in _icra) {
      if (i.id == id) return i;
    }
    return null;
  }

  final Map<String, double> _icraAkdiOran = {};

  FaizTablosu icraFaizTablosu(String icraId) => switch (_icraFaizTuru[icraId]) {
        FaizTuru.avans => FaizTablosu.avans,
        FaizTuru.akdi => FaizTablosu.sabit(_icraAkdiOran[icraId] ?? 0),
        _ => FaizTablosu.yasal,
      };

  FaizTuru icraFaizTuru(String icraId) => _icraFaizTuru[icraId] ?? FaizTuru.yasal;

  IcraDosyasi icraEkle({
    required String dosyaId,
    required String icraDairesi,
    required String borclu,
    required TakipTalebi talep,
    FaizTuru faizTuru = FaizTuru.yasal,
    String? esasNo,
    Para? vekaletUcreti,
  }) {
    final i = IcraDosyasi(
      id: yeniId('i'),
      dosyaId: dosyaId,
      icraDairesi: icraDairesi.trim(),
      borclu: borclu.trim(),
      talep: talep,
      esasNo: esasNo,
      vekaletUcreti: vekaletUcreti,
    );
    _icra.add(i);
    _icraFaizTuru[i.id] = faizTuru;
    _kaydet(DenetimIslemi.olusturma, 'icra', i.id, '${i.borclu} · ${talep.asilAlacak.bicimli}');
    notifyListeners();
    return i;
  }

  String? icraTahsilatEkle(String icraId, Para tutar, Tarih tarih, String aciklama) {
    final i = icraDosyasi(icraId);
    if (i == null) return 'İcra dosyası bulunamadı.';
    if (tutar.kurus <= 0) return 'Tutar sıfırdan büyük olmalı.';
    if (tarih.isAfter(Tarih.from(DateTime.now()))) return 'İleri tarihli tahsilat girilemez.';
    i.tahsilatlar.add(Tahsilat(id: yeniId('th'), tarih: tarih, tutar: tutar, aciklama: aciklama));
    _kaydet(DenetimIslemi.olusturma, 'icra_tahsilat', icraId, '${tutar.bicimli} · $aciklama');
    notifyListeners();
    return null;
  }

  void icraDurumu(String icraId, IcraDurumu durum) {
    final i = icraDosyasi(icraId);
    if (i == null) return;
    i.durum = durum;
    _kaydet(DenetimIslemi.degisiklik, 'icra', icraId, 'Durum: ${durum.ad}');
    notifyListeners();
  }

  /// Geçerli satırların her biri için icra türünde dosya ve takip açar; açılan sayıyı döner.
  int topluTakipAc({
    required List<TopluTakipSatiri> satirlar,
    required String muvekkilId,
    required String icraDairesi,
    required TakipTuru tur,
    required Tarih takipTarihi,
    required String sorumlu,
    FaizTuru faizTuru = FaizTuru.yasal,
  }) {
    var n = 0;
    final muvekkilAdi = kisi(muvekkilId)?.ad ?? muvekkilId;
    for (final r in satirlar.where((r) => r.gecerli)) {
      final d = dosyaAc(tur: DosyaTuru.icra, baslik: '$muvekkilAdi - ${r.borclu}', sorumlu: sorumlu, muvekkilId: muvekkilId);
      icraEkle(
        dosyaId: d.id,
        icraDairesi: icraDairesi,
        borclu: r.borclu,
        talep: TakipTalebi(tur: tur, asilAlacak: r.alacak!, temerrutTarihi: r.temerrut!, takipTarihi: takipTarihi),
        faizTuru: faizTuru,
      );
      n++;
    }
    _kaydet(DenetimIslemi.aktarim, 'icra', '-', 'Toplu takip: $n dosya');
    notifyListeners();
    return n;
  }

  // ---------------------------------------------------------------------------
  // KVKK: saklama ve imha
  // ---------------------------------------------------------------------------

  late final SaklamaVeImha saklama =
      SaklamaVeImha(sonPeriyodikImha: Tarih.from(DateTime.now()).ayEkle(-7));

  /// Fiziksel/elektronik arşivdeki eski kayıtlar (demo verisi; gerçekte belge servisinden gelir).
  final List<SaklamaKaydi> _arsiv = [
    SaklamaKaydi(id: 'ar1', ad: '2013/45 E. Alacak davası (arşiv kutusu 12)', kategori: VeriKategorisi.davaDosyasi, kapanis: Tarih(2015, 3, 12)),
    SaklamaKaydi(id: 'ar2', ad: '2012/3 E. Tazminat davası', kategori: VeriKategorisi.davaDosyasi, kapanis: Tarih(2013, 1, 10),
        yasalSaklamaEngeli: 'Bağlı rücu davası devam ediyor'),
    SaklamaKaydi(id: 'ar3', ad: '2014 yılı serbest meslek makbuzları', kategori: VeriKategorisi.muhasebe, kapanis: Tarih(2014, 12, 31)),
    SaklamaKaydi(id: 'ar4', ad: 'Kabul edilmeyen başvuru: Yıldız Tekstil', kategori: VeriKategorisi.adayKaydi, kapanis: Tarih(2023, 5, 4)),
    SaklamaKaydi(id: 'ar5', ad: '2021/77 E. İşe iade davası', kategori: VeriKategorisi.davaDosyasi, kapanis: Tarih(2022, 9, 30)),
  ];
  final Set<String> _imhaEdilen = {};

  /// Sunucu bağlıyken kayıtlar ve tutanaklar sunucudan gelir; tutanak no → sunucu kimliği.
  List<SaklamaKaydi>? _sunucuSaklama;
  final Map<String, String> _tutanakIdleri = {};

  void sunucuSaklamaVerisiniYukle({
    required List<SaklamaKaydi> kayitlar,
    required List<(String, ImhaTutanagi)> tutanaklar,
    Tarih? sonPeriyodikImha,
  }) {
    _sunucuSaklama = kayitlar;
    _tutanakIdleri
      ..clear()
      ..addEntries(tutanaklar.map((t) => MapEntry(t.$2.no, t.$1)));
    saklama.tutanaklar
      ..clear()
      ..addAll(tutanaklar.map((t) => t.$2).toList().reversed);
    saklama.sonPeriyodikImha = sonPeriyodikImha;
    notifyListeners();
  }

  List<SaklamaKaydi> get saklamaKayitlari => _sunucuSaklama ?? [
        for (final k in _arsiv)
          if (!_imhaEdilen.contains(k.id)) k,
        for (final d in _dosyalar)
          SaklamaKaydi(
            id: d.id,
            ad: '${d.icNo} · ${d.baslik}',
            kategori: d.tur == DosyaTuru.danismanlik ? VeriKategorisi.danismanlik : VeriKategorisi.davaDosyasi,
            kapanis: d.acik ? null : d.kapanisTarihi,
          ),
      ];

  /// Hata varsa mesajı döner. Sunucuda süre, kapalılık ve engel yeniden denetlenir.
  Future<String?> imhaTutanagiHazirla(Set<String> idler, ImhaYontemi yontem) => sunucudaVeyaYerelde(
        sunucuda: (u) => u.imhaTutanagiHazirla(idler, yontem),
        yerelde: () => _imhaTutanagiHazirlaYerel(idler, yontem),
      );

  String? _imhaTutanagiHazirlaYerel(Set<String> idler, ImhaYontemi yontem) {
    try {
      final t = saklama.tutanakHazirla(
        secilen: saklamaKayitlari.where((k) => idler.contains(k.id)),
        yontem: yontem,
        hazirlayan: aktifKullanici,
        bugun: Tarih.from(DateTime.now()),
      );
      _kaydet(DenetimIslemi.olusturma, 'imha_tutanagi', t.no, '${t.kayitIdleri.length} kayıt · ${yontem.ad}');
      notifyListeners();
      return null;
    } on ArgumentError catch (e) {
      return '${e.message}';
    } on StateError catch (e) {
      return e.message;
    }
  }

  /// Onaylanan tutanaktaki kayıtlar imha edilmiş sayılır. Sunucuda dört göz kuralı veritabanında uygulanır;
  /// fiziksel silme avukat onaylı politika kesinleşene kadar yapılmaz, kayıt yalnızca işaretlenir.
  Future<String?> imhaTutanagiOnayla(ImhaTutanagi t) {
    final id = _tutanakIdleri[t.no];
    return sunucudaVeyaYerelde(
      sunucuda: (u) => id == null ? Future.error(Exception('Tutanak sunucuda bulunamadı.')) : u.imhaTutanagiOnayla(id),
      yerelde: () => _imhaTutanagiOnaylaYerel(t),
    );
  }

  String? _imhaTutanagiOnaylaYerel(ImhaTutanagi t) {
    try {
      saklama.tutanakOnayla(t, aktifKullanici, Tarih.from(DateTime.now()));
      _imhaEdilen.addAll(t.kayitIdleri);
      _kaydet(DenetimIslemi.silme, 'imha_tutanagi', t.no, '${t.kayitIdleri.length} kayıt imha edildi (${t.yontem.ad})');
      notifyListeners();
      return null;
    } on StateError catch (e) {
      return e.message;
    }
  }

  // ---------------------------------------------------------------------------
  // Zaman kaydı ve gelir paylaşımı
  // ---------------------------------------------------------------------------

  ZamanDefteri zaman = ZamanDefteri(tarife: SaatlikUcretTarifesi(kullanici: const {}, varsayilan: Para.tl(2000)));

  /// Hata varsa mesajı döner.
  String? zamanEkle({
    required String dosyaId,
    required int dakika,
    required String aciklama,
    bool faturalanabilir = true,
    Tarih? tarih,
  }) {
    final bugun = Tarih.from(DateTime.now());
    try {
      final k = zaman.ekle(
        kullanici: aktifKullanici,
        dosyaId: dosyaId,
        tarih: tarih ?? bugun,
        dakika: dakika,
        aciklama: aciklama,
        bugun: bugun,
        faturalanabilir: faturalanabilir,
      );
      _kaydet(DenetimIslemi.olusturma, 'zaman', k.id, '${dosya(dosyaId)?.icNo ?? dosyaId} · ${k.dakika} dk');
      notifyListeners();
      return null;
    } on ArgumentError catch (e) {
      return '${e.message}';
    }
  }

  String? zamanOnayla(String id) {
    try {
      zaman.onayla(id, aktifKullanici);
      _kaydet(DenetimIslemi.degisiklik, 'zaman', id, 'Onaylandı');
      notifyListeners();
      return null;
    } on StateError catch (e) {
      return e.message;
    }
  }

  String? zamanSil(String id) {
    final k = zaman.kayit(id);
    if (k == null) return 'Kayıt bulunamadı.';
    if (k.kullanici != aktifKullanici) return 'Yalnızca kendi kaydınızı silebilirsiniz.';
    try {
      zaman.sil(id);
      _kaydet(DenetimIslemi.silme, 'zaman', id, '${k.dakika} dk · ${k.aciklama}');
      notifyListeners();
      return null;
    } on StateError catch (e) {
      return e.message;
    }
  }

  ZamanFaturaTaslagi zamanFaturaOnizleme(String dosyaId) =>
      zaman.faturaTaslagi(dosyaId, yil: DateTime.now().year);

  /// Onaylı kayıtları faturalar ve müvekkil carisine vekâlet ücreti tahakkuku (KDV hariç) yazar.
  String? zamanFaturaKes(String dosyaId) {
    final muvekkil = dosyaMuvekkili(dosyaId);
    if (muvekkil == null) return 'Dosyada müvekkil kaydı yok.';
    try {
      final t = zaman.faturaTaslagi(dosyaId, yil: DateTime.now().year, kesinlestir: true);
      _cari.add(CariHareket(
        id: yeniId('c'),
        muvekkilId: muvekkil,
        dosyaId: dosyaId,
        tur: CariHareketTuru.ucretTahakkuku,
        tutar: t.toplam,
        tarih: Tarih.from(DateTime.now()),
        aciklama: 'Zaman kaydı faturası ${t.no} (${t.kalemler.length} kalem)',
        belge: t.no,
      ));
      _kaydet(DenetimIslemi.olusturma, 'zaman_fatura', t.no, '${t.toplam.bicimli} · ${dosya(dosyaId)?.icNo ?? dosyaId}');
      notifyListeners();
      return null;
    } on StateError catch (e) {
      return e.message;
    }
  }

  /// Dosyada kişi bazında çalışılan dakika (gelir paylaşımı için).
  Map<String, int> dosyaCalisanDakikalari(String dosyaId) {
    final m = <String, int>{};
    for (final k in zaman.kayitlar.where((k) => k.dosyaId == dosyaId)) {
      m[k.kullanici] = (m[k.kullanici] ?? 0) + k.dakika;
    }
    return m;
  }
  List<CariHareket> get tumCariHareketler => List.unmodifiable(_cari);

  String? belgeMetni(String belgeId) => _belgeMetinleri[belgeId];

  Belge belgeOlustur({required String dosyaId, required String ad, required String metin, required String yukleyen, BelgeTuru tur = BelgeTuru.dilekce}) {
    final b = Belge(
      id: yeniId('b'),
      kiraciId: kiraciId,
      ad: ad,
      tur: tur,
      dosyaId: dosyaId,
      ilkSurum: BelgeSurumu(
        no: 1,
        ozet: metinOzeti(metin),
        boyut: metin.length,
        yukleyen: yukleyen,
        tarih: Tarih.from(DateTime.now()),
        dosyaAdi: '$ad.txt',
      ),
    );
    _belgeler.add(b);
    _kaydet(DenetimIslemi.olusturma, 'belge', b.id, '${b.ad} · SHA-256 ${b.orijinal.ozet.substring(0, 12)}');
    _belgeMetinleri[b.id] = metin;
    notifyListeners();
    return b;
  }

  /// Şablon alanları için dosya, müvekkil, karşı taraf ve kullanıcı bilgileri.
  Map<String, String?> sablonVerisi({required String dosyaId, required String avukatAdi, required String buroAdi}) {
    final d = dosya(dosyaId);
    final m = kisi(dosyaMuvekkili(dosyaId) ?? '');
    final k = kisi(dosyaKarsiTarafi(dosyaId) ?? '');
    final bugun = Tarih.from(DateTime.now());
    Durusma? siradaki;
    for (final du in _durusmalar.where((x) => x.dosyaId == dosyaId && x.baslangic.isAfter(DateTime.now()))) {
      if (siradaki == null || du.baslangic.isBefore(siradaki.baslangic)) siradaki = du;
    }
    String? durusmaTarihi;
    if (siradaki != null) {
      final b = siradaki.baslangic;
      durusmaTarihi = '${Tarih.from(b).turkceBicim} ${b.hour.toString().padLeft(2, '0')}:${b.minute.toString().padLeft(2, '0')}';
    }
    return {
      'mahkeme': d?.mahkeme?.toUpperCase(),
      'dosya.esasNo': d?.esasNo,
      'dosya.baslik': d?.baslik,
      'muvekkil.ad': m?.ad,
      'muvekkil.kimlikNo': m?.kimlikNo,
      'karsiTaraf.ad': k?.ad,
      'karsiTaraf.adres': k?.adres,
      'avukat.ad': avukatAdi,
      'buro.ad': buroAdi,
      'durusma.tarih': durusmaTarihi,
      'bugun': bugun.turkceBicim,
    };
  }

  void _finansVeBelgeDemosu(String av1, Tarih bugun) {
    void c(String m, CariHareketTuru t, num tutar, String a, int gunOnce, {String? dosya}) => _cari.add(CariHareket(
          id: yeniId('c'),
          muvekkilId: m,
          dosyaId: dosya,
          tur: t,
          tutar: Para.tl(tutar),
          tarih: bugun.gunEkle(-gunOnce),
          aciklama: a,
        ));
    c('abc', CariHareketTuru.masrafAvansiAlindi, 10000, 'Masraf avansı', 60, dosya: 'd1');
    c('abc', CariHareketTuru.masrafYapildi, 732, 'Başvurma harcı', 58, dosya: 'd1');
    c('abc', CariHareketTuru.masrafYapildi, 1500, 'Bilirkişi ücreti', 20, dosya: 'd1');
    c('abc', CariHareketTuru.ucretTahakkuku, 120000, 'Ücret sözleşmesi 1. taksit', 60, dosya: 'd1');
    c('abc', CariHareketTuru.ucretTahsilati, 60000, 'Havale', 45, dosya: 'd1');
    c('ayse', CariHareketTuru.masrafAvansiAlindi, 2000, 'Masraf avansı', 30, dosya: 'd2');
    c('ayse', CariHareketTuru.masrafYapildi, 2100, 'Arabuluculuk ve tebligat giderleri', 10, dosya: 'd2');

    emanet.ekle(EmanetHareketi(
      id: yeniId('e'),
      muvekkilId: 'abc',
      dosyaId: 'd1',
      tur: EmanetHareketTuru.giris,
      tutar: Para.tl(250000),
      tarih: bugun.gunEkle(-20),
      aciklama: 'İcra dosyasından tahsilat',
    ));

    final dilekce = belgeOlustur(
      dosyaId: 'd1',
      ad: 'Dava dilekçesi',
      metin: 'İSTANBUL ASLİYE TİCARET MAHKEMESİNE\n\nDAVACI: ABC Gıda Sanayi ve Ticaret A.Ş.\n...',
      yukleyen: av1,
    );
    dilekce.yeniSurum(
      ozet: metinOzeti('düzeltilmiş dilekçe'),
      boyut: 20,
      yukleyen: av1,
      tarih: bugun.gunEkle(-50),
      dosyaAdi: 'Dava dilekçesi v2.docx',
      aciklama: 'Islah sonrası',
    );
    _portalDosyalari.add('d1');
    _paylasilanBelgeler.add(dilekce.id);
    final simdi = DateTime.now();
    _mesajlar.addAll([
      PortalMesaji(
        id: yeniId('m'),
        dosyaId: 'd1',
        gonderen: av1,
        muvekkildenMi: false,
        metin: 'Dava dilekçesinin son hâlini portala ekledik. Bir sonraki duruşmadan önce sizi arayacağım.',
        zaman: simdi.subtract(const Duration(days: 3)),
        okundu: true,
      ),
      PortalMesaji(
        id: yeniId('m'),
        dosyaId: 'd1',
        gonderen: 'mvk-abc',
        muvekkildenMi: true,
        metin: 'Teşekkürler. Tedarikçiyle yapılan yazışmaları da iletelim mi?',
        zaman: simdi.subtract(const Duration(days: 1)),
      ),
    ]);
    final icraTakip = icraEkle(
      dosyaId: 'd1',
      icraDairesi: 'İstanbul Anadolu 7. İcra Dairesi',
      borclu: 'Delta İnşaat Ltd. Şti.',
      esasNo: '2026/18452 E.',
      faizTuru: FaizTuru.avans,
      talep: TakipTalebi(
        tur: TakipTuru.ilamsiz,
        asilAlacak: Para.tl(480000),
        temerrutTarihi: Tarih(2026, 6, 15),
        takipTarihi: Tarih(2026, 8, 20),
        takipOncesiMasraf: Para.tl(1850),
      ),
      vekaletUcreti: Para.tl(54000),
    );
    icraTakip
      ..durum = IcraDurumu.kesinlesti
      ..tebligTarihi = Tarih(2026, 8, 28)
      ..takipSonrasiMasraf = Para.tl(410)
      ..tahsilatlar.add(Tahsilat(id: yeniId('th'), tarih: Tarih(2026, 10, 10), tutar: Para.tl(50000), aciklama: 'Borçlu ödemesi'));
    const av2 = 'demo-av2';
    const stj = 'demo-stj';
    void z(String kim, String dosyaId, int gunOnce, int dk, String aciklama) => zaman.ekle(
        kullanici: kim, dosyaId: dosyaId, tarih: bugun.gunEkle(-gunOnce), dakika: dk, aciklama: aciklama, bugun: bugun);
    z(av1, 'd1', 2, 95, 'Cevap dilekçesine karşı beyan hazırlığı');
    z(av2, 'd1', 1, 60, 'Ön inceleme duruşmasına katılım');
    z(stj, 'd1', 1, 40, 'UYAP evrak takibi ve dosya düzeni');
    z(av1, 'd2', 0, 30, 'Müvekkil görüşmesi');
    z(av2, 'd3', 3, 120, 'Birleşme hukuki inceleme raporu');
    for (final k in zaman.kayitlar.where((k) => k.dosyaId == 'd1' && k.kullanici != av1)) {
      zaman.onayla(k.id, av1);
    }
    belgeOlustur(
      dosyaId: 'd1',
      ad: 'Gerekçeli karar',
      metin: 'T.C. İSTANBUL 5. ASLİYE TİCARET MAHKEMESİ\nGEREKÇELİ KARAR\n...',
      yukleyen: av1,
      tur: BelgeTuru.karar,
    );
  }

  // ---------------------------------------------------------------------------
  // Denetim kaydı ve yeni kayıt işlemleri
  // ---------------------------------------------------------------------------

  final DenetimKaydi denetim = DenetimKaydi();

  /// İşlemleri yapan kullanıcı; oturum açılınca ayarlanır.
  String aktifKullanici = 'sistem';

  void _kaydet(DenetimIslemi islem, String nesneTuru, String nesneId, String aciklama) {
    denetim.ekle(
      kiraciId: kiraciId,
      kullaniciId: aktifKullanici,
      islem: islem,
      nesneTuru: nesneTuru,
      nesneId: nesneId,
      aciklama: aciklama,
    );
  }

  /// Görüntüleme ve indirme gibi okuma işlemlerini kaydeder.
  /// Sunucu bağlıyken olay sunucudaki zincire de yazılır; ağ hatası kullanıcının işini durdurmaz.
  void okumaKaydet(DenetimIslemi islem, String nesneTuru, String nesneId, [String aciklama = '']) {
    _kaydet(islem, nesneTuru, nesneId, aciklama);
    uzak?.denetimKaydet(islem, nesneTuru, nesneId, aciklama).catchError((Object _) {});
  }

  Map<String, String> get kullanicilar => Map.unmodifiable(_kullaniciAdlari);

  Dosya dosyaAc({
    required DosyaTuru tur,
    required String baslik,
    required String sorumlu,
    String? yedekSorumlu,
    String? muvekkilId,
    String? karsiTarafId,
    String? mahkeme,
    String? esasNo,
    bool gizli = false,
    GorevSablonu? sablon,
  }) {
    final id = yeniId('d');
    final d = Dosya(
      id: id,
      kiraciId: kiraciId,
      icNo: _dosyaSerisi.sonraki(),
      tur: tur,
      baslik: baslik.trim(),
      sorumlu: sorumlu,
      yedekSorumlu: yedekSorumlu,
      mahkeme: (mahkeme?.trim().isEmpty ?? true) ? null : mahkeme!.trim(),
      esasNo: (esasNo?.trim().isEmpty ?? true) ? null : esasNo!.trim(),
      gizli: gizli,
      acilisTarihi: Tarih.from(DateTime.now()),
    );
    _dosyalar.add(d);
    if (muvekkilId != null) {
      _dosyaKayitlari.add(DosyaTarafKaydi(
          dosyaId: id, dosyaAdi: d.baslik, kisiId: muvekkilId, sifat: TarafSifati.muvekkil, gizli: gizli));
    }
    if (karsiTarafId != null) {
      _dosyaKayitlari.add(DosyaTarafKaydi(
          dosyaId: id, dosyaAdi: d.baslik, kisiId: karsiTarafId, sifat: TarafSifati.karsiTaraf, gizli: gizli));
    }
    if (sablon != null) {
      _gorevler.addAll(sablon.uygula(
        dosyaId: id,
        baslangic: d.acilisTarihi,
        roller: {'sorumlu': sorumlu, if (yedekSorumlu != null) 'yedek': yedekSorumlu, 'stajyer': yedekSorumlu ?? sorumlu},
        idUret: () => yeniId('g'),
      ));
    }
    _kaydet(DenetimIslemi.olusturma, 'dosya', id, '${d.icNo} · ${d.baslik}');
    notifyListeners();
    return d;
  }

  /// Duruşmayı ekler ve eklenen duruşmanın dahil olduğu çakışmaları döner.
  List<Cakisma> durusmaEkle({
    required String dosyaId,
    required DateTime baslangic,
    required String yer,
    required String katilan,
    String tur = 'Duruşma',
  }) {
    final du = Durusma(id: yeniId('du'), dosyaId: dosyaId, baslangic: baslangic, yer: yer.trim(), katilan: katilan, tur: tur);
    _durusmalar.add(du);
    _kaydet(DenetimIslemi.olusturma, 'durusma', du.id, '$tur · $yer');
    notifyListeners();
    return cakismalar.where((c) => c.a.id == du.id || c.b.id == du.id).toList();
  }

  Vekaletname vekaletnameEkle({
    required String muvekkilId,
    required Set<String> avukatlar,
    required Tarih duzenlemeTarihi,
    String? noter,
    String? yevmiyeNo,
    bool genel = true,
    Set<String> dosyalar = const {},
    Set<OzelYetki> ozelYetkiler = const {},
    String? asilEvrakYeri,
  }) {
    final v = Vekaletname(
      id: yeniId('v'),
      kiraciId: kiraciId,
      muvekkilId: muvekkilId,
      avukatlar: avukatlar,
      duzenlemeTarihi: duzenlemeTarihi,
      noter: noter,
      yevmiyeNo: yevmiyeNo,
      genel: genel,
      dosyalar: dosyalar,
      ozelYetkiler: ozelYetkiler,
      asilEvrakYeri: asilEvrakYeri,
    );
    _vekaletnameler.add(v);
    _kaydet(DenetimIslemi.olusturma, 'vekaletname', v.id, '${kisi(muvekkilId)?.ad ?? muvekkilId} · ${ozelYetkiler.length} özel yetki');
    notifyListeners();
    return v;
  }

  /// Önizlemede "aktarılacak" durumundaki satırları kişi olarak ekler.
  int kisileriAktar(AktarimOnizlemesi onizleme) {
    var n = 0;
    for (final s in onizleme.satirlar.where((s) => s.durum == SatirDurumu.aktarilacak)) {
      _sayac++;
      final k = Kisi(
        id: 'akt$_sayac',
        kiraciId: kiraciId,
        tur: s.tur,
        ad: s.deger(KisiAlani.ad),
        kimlikNo: s.deger(KisiAlani.kimlikNo).isEmpty ? null : s.deger(KisiAlani.kimlikNo).replaceAll(' ', ''),
        eposta: s.deger(KisiAlani.eposta).isEmpty ? null : s.deger(KisiAlani.eposta),
        telefon: s.deger(KisiAlani.telefon).isEmpty ? null : s.deger(KisiAlani.telefon),
        adres: s.deger(KisiAlani.adres).isEmpty ? null : s.deger(KisiAlani.adres),
      );
      _kisiler.add(k);
      n++;
    }
    _kaydet(DenetimIslemi.aktarim, 'kisi', '-',
        'Okunan ${onizleme.satirlar.length}, aktarılan $n, mükerrer ${onizleme.sayi(SatirDurumu.mukerrer)}, '
        'hatalı ${onizleme.sayi(SatirDurumu.hatali)}');
    notifyListeners();
    return n;
  }
}
