import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import 'api_istemcisi.dart';
import 'veri_deposu.dart';

/// Müvekkil portalı yazışmaları için kanca (büro tarafında SunucuSenkronu, müvekkil tarafında PortalSenkronu).
abstract class MesajUzak {
  Future<void> mesajGonder(String dosyaId, String metin);

  /// Karşı taraftan gelen mesajları okundu işaretler.
  Future<void> mesajlariOku(String dosyaId);
}

/// Depodaki bazı işlemlerin sunucuda yapılması için kanca. Sunucu bağlıyken ekranlar bu yolu kullanır;
/// sonuç her işlemden sonra sunucudan yeniden yüklenir (sunucu tek doğru kaynaktır).
/// Belge içi arama sonucu; [ozet] eşleşen bölümleri «» içinde gösterir.
typedef BelgeAramaSonucu = ({String belgeId, String ad, String? dosyaId, String? dosyaNo, String ozet, bool ocr});

/// Sunucudaki denetim zincirinden bir olay (özet sunucuda hesaplanır ve doğrulanır).
class SunucuDenetimOlayi {
  const SunucuDenetimOlayi({
    required this.sira,
    required this.zaman,
    required this.kullanici,
    required this.islem,
    required this.nesneTuru,
    required this.nesneId,
    required this.aciklama,
    required this.ozet,
  });

  final int sira;
  final DateTime zaman;
  final String kullanici;
  final String islem;
  final String nesneTuru;
  final String nesneId;
  final String aciklama;
  final String ozet;

  /// Bilinen işlemler Türkçe adıyla, sunucuya özgü olanlar (ör. hesap açma) olduğu gibi.
  String get islemAdi => DenetimIslemi.values.asNameMap()[islem]?.ad ?? islem;

  factory SunucuDenetimOlayi.json(Map<String, dynamic> j) => SunucuDenetimOlayi(
        sira: (j['sira'] as num).toInt(),
        zaman: DateTime.parse(j['zaman'] as String),
        kullanici: j['kullanici'] as String? ?? '',
        islem: j['islem'] as String,
        nesneTuru: j['nesneTuru'] as String,
        nesneId: j['nesneId'] as String,
        aciklama: j['aciklama'] as String? ?? '',
        ozet: j['ozet'] as String,
      );
}

abstract class UzakIslemler {
  Future<void> yenile();

  Future<void> denetimKaydet(DenetimIslemi islem, String nesneTuru, String nesneId, String aciklama);

  /// Son olaylar (en yeniden) ve zincir doğrulaması: bozuk sıra ya da sağlamsa null. Yalnızca yöneticiler.
  Future<(List<SunucuDenetimOlayi>, int?)> denetimGetir();

  Future<void> imhaTutanagiHazirla(Set<String> dosyaIdleri, ImhaYontemi yontem);

  Future<void> imhaTutanagiOnayla(String tutanakId);

  Future<void> dosyaAc({
    required DosyaTuru tur,
    required String baslik,
    required String sorumlu,
    String? yedekSorumlu,
    bool gizli,
    String? muvekkilId,
    String? karsiTarafId,
    String? mahkeme,
    String? esasNo,
    GorevSablonu? sablon,
  });

  Future<void> gorevSablonuKaydet(String? id, GorevSablonu sablon);

  Future<void> gorevSablonuSil(String id);

  /// Süre sunucuda hesaplanır; dönen son gün.
  Future<Tarih> sureHesapla({required String dosyaId, required String kuralKodu, required Tarih tarih, String? aciklama});

  Future<void> sureTeyit(String sureId);

  Future<void> sureTamamla(String sureId, String kanit);

  Future<void> kisiEkle({required KisiTuru tur, required String ad, String? kimlikNo, String? eposta, String? telefon});

  /// Kartın tamamı; tür değişmez, ad değişirse eski ad sunucuda unvan geçmişine eklenir.
  Future<void> kisiGuncelle(Kisi kisi);

  /// Excel/CSV aktarımı (tek işlem); dönen: eklenen kayıt sayısı.
  Future<int> kisileriAktar(List<AktarimSatiri> satirlar);

  /// UYAP/Excel dosya listesi aktarımı (tek işlem); dönen: (eklenen, zaten kayıtlı olduğu için atlanan).
  Future<(int, int)> dosyalariAktar(List<DosyaAktarimSatiri> satirlar, {required String sorumlu, String? yedekSorumlu});

  /// Excel (.xlsx) dosyasının ilk sayfasını satırlar olarak okur (belge servisinde, Türkiye'de).
  Future<List<List<String>>> tabloOku(String dosyaAdi, List<int> icerik);

  Future<void> iliskiEkle({required String kisiA, required String kisiB, required IliskiTuru tur});

  Future<void> iliskiSil(String iliskiId);

  Future<void> cariEkle({required String muvekkilId, required CariHareketTuru tur, required Para tutar, required String aciklama, String? dosyaId});

  Future<void> emanetEkle(EmanetHareketi h);

  Future<void> zamanEkle({required String dosyaId, required int dakika, required String aciklama, bool faturalanabilir, Tarih? tarih});

  Future<void> zamanOnayla(String id);

  Future<void> zamanSil(String id);

  /// Dosyanın onaylı zaman kayıtlarını faturalar; fatura numarasını döner.
  Future<String> zamanFaturaKes(String dosyaId);

  /// Yeni icra dosyasının sunucudaki kimliğini döner.
  Future<String> icraEkle({
    required String dosyaId,
    required String icraDairesi,
    required String borclu,
    required TakipTalebi talep,
    required FaizTuru faizTuru,
    double? akdiOran,
    String? esasNo,
    Para? vekaletUcreti,
  });

  Future<void> icraTahsilat(String icraId, Para tutar, Tarih tarih, String aciklama);

  Future<void> icraDurumu(String icraId, IcraDurumu durum);

  /// Toplu takip; açılan takip sayısını döner. Sunucu satırları yeniden doğrular.
  Future<int> topluTakip({
    required String muvekkilId,
    required String icraDairesi,
    required TakipTuru tur,
    required List<TopluTakipSatiri> satirlar,
  });

  Future<void> gorevKapat(String gorevId, {String? kanit});

  Future<void> etikDuvarKur(String dosyaId, String kullanici, String gerekce);

  Future<void> portalPaylas(String dosyaId, bool paylas);

  /// Davetler ham JSON olarak (id, eposta, roller, olusturma, sonGecerlilik, durum).
  Future<List<Map<String, dynamic>>> davetler();

  /// Davet oluşturur; bağlantıya konacak kodu döner (yalnızca bir kez).
  Future<String> davetEt(String eposta, Set<Rol> roller, {String? kisiId});

  Future<void> davetIptal(String davetId);

  /// (lisans, dolu)
  Future<(int, int)> koltuklar();

  /// Ekip yönetimi (yalnızca yöneticiler; kurallar veritabanında).
  Future<void> kullaniciRolleri(String kullaniciId, Set<Rol> roller);

  /// Açık süre, görev ve dosyalar devralana geçer; dönen devredilen kayıt sayısı.
  Future<int> kullaniciPasiflestir(String kullaniciId, {String? devralan, required String gerekce});

  Future<void> kullaniciAktiflestir(String kullaniciId);

  Future<void> sifreDegistir(String eskiSifre, String yeniSifre);

  Future<List<Map<String, dynamic>>> oturumlar();

  /// [kimlik] null ise bu oturum dışındaki tümü kapatılır.
  Future<int> oturumKapat(String? kimlik);

  /// Takvim aboneliği: {var, olusturma, sonOkuma}.
  Future<Map<String, dynamic>> takvimDurumu();

  /// Yeni gizli bağlantı (öncekini geçersiz kılar): (https adresi, webcal adresi). Yalnızca bir kez gösterilir.
  Future<(String, String)> takvimBaglantisiOlustur();

  Future<void> takvimBaglantisiKapat();

  Future<bool> ikiAdimliAcikMi();

  /// Abonelik durumu, fiyatlar ve ödeme geçmişi (ham JSON).
  Future<Map<String, dynamic>> abonelik();

  /// Ödeme başlatır; ödeme kuruluşunun sayfa adresini döner (tutar sunucuda hesaplanır).
  Future<Uri> odemeBaslat(OdemeDonemi donem, {int? koltuk});

  Future<void> abonelikIptal(bool iptal);

  /// Kurulum: (base32 anahtar, otpauth bağlantısı). Sır sunucuda şifreli saklanır.
  Future<(String, String)> ikiAdimliBaslat();

  Future<void> ikiAdimliEtkinlestir(String kod);

  Future<void> ikiAdimliKapat(String kod);

  Future<void> belgePaylas(String belgeId, bool paylas);

  /// Belgelerin içinde Türkçe tam metin arama. Dönen: (sonuçlar, metni henüz çıkarılmamış belge sayısı).
  Future<(List<BelgeAramaSonucu>, int)> belgeAra(String sorgu);

  /// Şablondan üretilen metni sunucuda Word'e çevirip dosyaya kaydeder (eksik alan varsa reddedilir).
  Future<void> wordBelgeKaydet(
      {required String dosyaId, required String ad, required String metin, BelgeTuru tur, bool pdf});

  /// Belgeyi yükler (sürüm 1); SHA-256 özeti sunucuda hesaplanır.
  Future<void> belgeYukle({
    required String dosyaId,
    required String ad,
    required String dosyaAdi,
    required List<int> icerik,
    BelgeTuru tur,
  });

  Future<void> etikDuvarKaldir(String dosyaId, String kullanici, String gerekce);

  /// Kaydeder; varsa çakışma nedenlerini döner.
  Future<List<String>> durusmaEkle({
    required String dosyaId,
    required DateTime baslangic,
    required String yer,
    required String katilan,
    String tur,
  });

  /// Kaydedilen tebligatı döner (tebliğ tarihi sunucuda hesaplanır).
  Future<Tebligat> tebligatEkle(Tebligat t);

  Future<void> tebligatBagla(String tebligatId, String dosyaId);

  Future<void> vekaletnameEkle({
    required String muvekkilId,
    required Set<String> avukatlar,
    required Tarih duzenlemeTarihi,
    String? noter,
    String? yevmiyeNo,
    bool genel,
    Set<String> dosyalar,
    Set<OzelYetki> ozelYetkiler,
    String? asilEvrakYeri,
  });
}

class SunucuSenkronu implements UzakIslemler, MesajUzak {
  SunucuSenkronu(this.api, this.depo) {
    depo.uzak = this;
    depo.mesajUzak = this;
  }

  final ApiIstemcisi api;
  final BellekVeriDeposu depo;

  static Tarih _t(Object? v) => Tarih.parse(v! as String);

  static Dosya dosyaJson(Map<String, dynamic> j, String kiraciId) => Dosya(
        id: j['id'] as String,
        kiraciId: kiraciId,
        icNo: j['icNo'] as String,
        tur: DosyaTuru.values.byName(j['tur'] as String),
        baslik: j['baslik'] as String,
        sorumlu: j['sorumlu'] as String,
        yedekSorumlu: j['yedekSorumlu'] as String?,
        gizli: j['gizli'] == true,
        asama: DosyaAsamasi.values.any((a) => a.name == j['asama'])
            ? DosyaAsamasi.values.byName(j['asama'] as String)
            : DosyaAsamasi.onDegerlendirme,
        acilisTarihi: _t(j['acilis']),
        kapanisTarihi: j['kapanis'] == null ? null : _t(j['kapanis']),
        mahkeme: j['mahkeme'] as String?,
        esasNo: j['esasNo'] as String?,
      );

  /// Sunucudaki kayıttan süre; hesap adımları sunucuda saklanan gerekçedir.
  static SureKaydi? sureJson(Map<String, dynamic> j, String dosyaId) {
    final kural = KuralKatalogu.bul(j['kuralKodu'] as String);
    if (kural == null) return null;
    final sonGun = _t(j['sonGun']);
    final adimlar = [
      for (final a in (j['adimlar'] as List? ?? const []).cast<Map<String, dynamic>>())
        HesapAdimi(_t(a['tarih']), a['aciklama'] as String),
    ];
    return SureKaydi(
      id: j['id'] as String,
      dosyaId: dosyaId,
      aciklama: j['aciklama'] as String,
      sonuc: SureSonucu(
        kural: kural,
        baslangic: j['baslangic'] == null ? sonGun : _t(j['baslangic']),
        sonGun: sonGun,
        adimlar: adimlar,
        uyarilar: const [],
      ),
      olusturan: j['olusturan'] as String,
      olusturmaTarihi: Tarih.from(DateTime.now()),
      asilSorumlu: j['asilSorumlu'] as String,
      yedekSorumlu: j['yedekSorumlu'] as String?,
      durum: SureDurumu.values.byName(j['durum'] as String),
      teyitEden: j['teyitEden'] as String?,
      tamamlanmaKaniti: j['kanit'] as String?,
    );
  }

  static Tarih? _tn(Object? v) => v == null ? null : _t(v);

  static Kisi kisiJson(Map<String, dynamic> j, String kiraciId) => Kisi(
        id: j['id'] as String,
        kiraciId: kiraciId,
        tur: KisiTuru.values.byName(j['tur'] as String),
        ad: j['ad'] as String,
        kimlikNo: j['kimlikNo'] as String?,
        mersisNo: j['mersisNo'] as String?,
        eposta: j['eposta'] as String?,
        telefon: j['telefon'] as String?,
        adres: j['adres'] as String?,
        iletisimTercihi: IletisimTercihi.values.asNameMap()[j['iletisimTercihi']] ?? IletisimTercihi.eposta,
        notlar: j['notlar'] as String?,
        unvanGecmisi: [
          for (final u in (j['unvanGecmisi'] as List? ?? const []).cast<Map<String, dynamic>>())
            UnvanKaydi(unvan: u['unvan'] as String, gecerlilikBitisi: _t(u['bitis'])),
        ],
      );

  static CariHareket cariJson(Map<String, dynamic> j) => CariHareket(
        id: j['id'] as String,
        muvekkilId: j['muvekkilId'] as String,
        dosyaId: j['dosyaId'] as String?,
        tur: CariHareketTuru.values.byName(j['tur'] as String),
        tutar: Para.kurus(j['tutarKurus'] as int),
        tarih: _t(j['tarih']),
        aciklama: j['aciklama'] as String,
        belge: j['belgeNo'] as String?,
      );

  static EmanetHareketi emanetJson(Map<String, dynamic> j) => EmanetHareketi(
        id: j['id'] as String,
        muvekkilId: j['muvekkilId'] as String,
        dosyaId: j['dosyaId'] as String,
        tur: EmanetHareketTuru.values.byName(j['tur'] as String),
        tutar: Para.kurus(j['tutarKurus'] as int),
        tarih: _t(j['tarih']),
        aciklama: j['aciklama'] as String,
        mahsupOnayi: j['mahsupOnayi'] as String?,
      );

  static ZamanKaydi zamanJson(Map<String, dynamic> j) => ZamanKaydi(
        id: j['id'] as String,
        kullanici: j['kullanici'] as String,
        dosyaId: j['dosyaId'] as String,
        tarih: _t(j['tarih']),
        dakika: j['dakika'] as int,
        aciklama: j['aciklama'] as String,
        saatlikUcret: Para.kurus(j['saatlikKurus'] as int),
        faturalanabilir: j['faturalanabilir'] != false,
        durum: ZamanDurumu.values.byName(j['durum'] as String),
        onaylayan: j['onaylayan'] as String?,
        faturaNo: j['faturaNo'] as String?,
      );

  static (IcraDosyasi, FaizTuru, double?) icraJson(Map<String, dynamic> j) {
    final faiz = FaizTuru.values.firstWhere((f) => f.name == j['faizTuru'], orElse: () => FaizTuru.yasal);
    final durum = IcraDurumu.values.firstWhere((d) => d.name == j['durum'], orElse: () => IcraDurumu.takipAcildi);
    final elle = j['islemisFaizElleKurus'] as int?;
    final dosya = IcraDosyasi(
      id: j['id'] as String,
      dosyaId: j['dosyaId'] as String,
      icraDairesi: j['icraDairesi'] as String,
      borclu: j['borclu'] as String,
      esasNo: j['esasNo'] as String?,
      durum: durum,
      tebligTarihi: _tn(j['tebligTarihi']),
      vekaletUcreti: Para.kurus(j['vekaletKurus'] as int? ?? 0),
      takipSonrasiMasraf: Para.kurus(j['takipSonrasiMasrafKurus'] as int? ?? 0),
      talep: TakipTalebi(
        tur: TakipTuru.values.byName(j['takipTuru'] as String),
        asilAlacak: Para.kurus(j['asilKurus'] as int),
        temerrutTarihi: _t(j['temerrut']),
        takipTarihi: _t(j['takipTarihi']),
        takipOncesiMasraf: Para.kurus(j['takipOncesiMasrafKurus'] as int? ?? 0),
        islemisFaizElle: elle == null ? null : Para.kurus(elle),
      ),
      tahsilatlar: [
        for (final t in (j['tahsilatlar'] as List? ?? const []).cast<Map<String, dynamic>>())
          Tahsilat(
            id: t['id'] as String,
            tarih: _t(t['tarih']),
            tutar: Para.kurus(t['tutarKurus'] as int),
            aciklama: t['aciklama'] as String? ?? '',
          ),
      ],
    );
    return (dosya, faiz, (j['akdiOran'] as num?)?.toDouble());
  }

  static List<Map<String, dynamic>> _liste(Object? v) => (v! as List).cast<Map<String, dynamic>>();

  static Belge? belgeJson(Map<String, dynamic> j, String dosyaId, String kiraciId) {
    BelgeSurumu surum(Map<String, dynamic> s) => BelgeSurumu(
          no: s['no'] as int,
          ozet: s['sha256'] as String,
          boyut: s['boyut'] as int,
          yukleyen: s['yukleyen'] as String,
          tarih: Tarih.from(DateTime.parse(s['zaman'] as String).toLocal()),
          dosyaAdi: s['dosyaAdi'] as String,
        );
    final surumler = _liste(j['surumler'] ?? const []);
    if (surumler.isEmpty) return null;
    final b = Belge(
      id: j['id'] as String,
      kiraciId: kiraciId,
      ad: j['ad'] as String,
      tur: BelgeTuru.values.firstWhere((t) => t.name == j['tur'], orElse: () => BelgeTuru.diger),
      dosyaId: dosyaId,
      gizli: j['gizli'] == true,
      ilkSurum: surum(surumler.first),
    );
    for (final s in surumler.skip(1)) {
      final x = surum(s);
      b.yeniSurum(ozet: x.ozet, boyut: x.boyut, yukleyen: x.yukleyen, tarih: x.tarih, dosyaAdi: x.dosyaAdi);
    }
    return b;
  }

  /// Gönderen adı sunucudan gelir; ekranda kullanıcı adı yerine doğrudan gösterilir.
  static PortalMesaji mesajJson(Map<String, dynamic> j, String dosyaId) => PortalMesaji(
        id: '${j['id']}',
        dosyaId: dosyaId,
        gonderen: j['gonderen'] as String,
        muvekkildenMi: j['muvekkilden'] == true,
        metin: j['metin'] as String,
        zaman: DateTime.parse(j['zaman'] as String).toLocal(),
        okundu: j['okundu'] != null,
      );

  static Gorev gorevJson(Map<String, dynamic> j) => Gorev(
        id: j['id'] as String,
        baslik: j['baslik'] as String,
        atanan: j['atanan'] as String,
        dosyaId: j['dosyaId'] as String?,
        yedek: j['yedek'] as String?,
        sonTarih: _tn(j['sonTarih']),
        oncelik: GorevOnceligi.values.firstWhere((x) => x.name == j['oncelik'], orElse: () => GorevOnceligi.normal),
        durum: GorevDurumu.values.firstWhere((x) => x.name == j['durum'], orElse: () => GorevDurumu.acik),
        kaynakSureId: j['kaynakSureId'] as String?,
        kanitGerekir: j['kanitGerekir'] == true,
        kapanisKaniti: j['kapanisKaniti'] as String?,
      );

  static Durusma durusmaJson(Map<String, dynamic> j) => Durusma(
        id: j['id'] as String,
        dosyaId: j['dosyaId'] as String,
        baslangic: DateTime.parse(j['baslangic'] as String).toLocal(),
        yer: j['yer'] as String,
        katilan: j['katilan'] as String,
        sureDakika: j['sureDakika'] as int? ?? 60,
        tur: j['tur'] as String? ?? 'Duruşma',
      );

  static Tebligat tebligatJson(Map<String, dynamic> j, String kiraciId) => Tebligat(
        id: j['id'] as String,
        kiraciId: kiraciId,
        kanal: TebligatKanali.values.firstWhere((x) => x.name == j['kanal'], orElse: () => TebligatKanali.fiziki),
        ulasmaTarihi: _t(j['ulasmaTarihi']),
        tebligTarihi: _t(j['tebligTarihi']),
        gonderen: j['gonderen'] as String,
        konu: j['konu'] as String,
        esasNo: j['esasNo'] as String?,
        taraflar: [for (final x in (j['taraflar'] as List? ?? const [])) '$x'],
        belgeOzeti: j['belgeOzeti'] as String?,
        dosyaId: j['dosyaId'] as String?,
        eslesmeDurumu: j['dosyaId'] == null ? EslesmeDurumu.eslesmedi : EslesmeDurumu.eslesti,
      );

  static Vekaletname vekaletnameJson(Map<String, dynamic> j, String kiraciId) => Vekaletname(
        id: j['id'] as String,
        kiraciId: kiraciId,
        muvekkilId: j['muvekkilId'] as String,
        avukatlar: {for (final x in (j['avukatlar'] as List? ?? const [])) '$x'},
        duzenlemeTarihi: _t(j['duzenlemeTarihi']),
        noter: j['noter'] as String?,
        yevmiyeNo: j['yevmiyeNo'] as String?,
        genel: j['genel'] != false,
        ozelYetkiler: {
          for (final x in (j['ozelYetkiler'] as List? ?? const []))
            ...OzelYetki.values.where((y) => y.name == x),
        },
        dosyalar: {for (final x in (j['dosyalar'] as List? ?? const [])) '$x'},
        bitisTarihi: _tn(j['bitisTarihi']),
        durum: VekaletDurumu.values.firstWhere((x) => x.name == j['durum'], orElse: () => VekaletDurumu.gecerli),
        durumTarihi: _tn(j['durumTarihi']),
        asilEvrakYeri: j['asilEvrakYeri'] as String?,
      );

  static DosyaTarafKaydi tarafJson(Map<String, dynamic> j) => DosyaTarafKaydi(
        dosyaId: j['dosyaId'] as String,
        dosyaAdi: j['dosyaAdi'] as String? ?? '',
        kisiId: j['kisiId'] as String,
        sifat: TarafSifati.values.firstWhere((x) => x.name == j['sifat'], orElse: () => TarafSifati.diger),
        gizli: j['gizli'] == true,
        kapali: j['kapali'] == true,
      );

  /// Taraf, görev, duruşma, tebligat ve vekâletname verisini yükler.
  @override
  Future<void> gorevSablonuKaydet(String? id, GorevSablonu sablon) async {
    if (id == null) {
      await api.post('/gorev-sablonlari', sablon.toJson());
    } else {
      await api.put('/gorev-sablonlari/$id', sablon.toJson());
    }
    await _sablonlariYenile();
  }

  @override
  Future<void> gorevSablonuSil(String id) async {
    await api.delete('/gorev-sablonlari/$id');
    await _sablonlariYenile();
  }

  Future<void> _sablonlariYenile() async {
    depo.sunucuSablonlariniYukle([
      for (final j in _liste(await api.get('/gorev-sablonlari'))) (j['id'] as String, GorevSablonu.json(j)),
    ]);
  }

  Future<void> _buroVerisiniYenile() async {
    await _sablonlariYenile();
    final taraflar = _liste(await api.get('/taraflar'));
    final gorevler = _liste(await api.get('/gorevler'));
    final durusmalar = _liste(await api.get('/durusmalar'));
    final tebligatlar = _liste(await api.get('/tebligatlar'));
    final vekaletnameler = _liste(await api.get('/vekaletnameler'));
    final duvarlar = _liste(await api.get('/etik-duvarlar'));
    final paylasim = await api.get('/portal-paylasimlari') as Map<String, dynamic>;
    final portalDosyalari = {for (final x in (paylasim['dosyalar'] as List? ?? const [])) '$x'};
    final mesajlar = <PortalMesaji>[];
    for (final d in portalDosyalari) {
      for (final m in _liste(await api.get('/dosyalar/$d/mesajlar'))) {
        mesajlar.add(mesajJson(m, d));
      }
    }
    depo.sunucuPortalVerisiniYukle(
      portalDosyalari: portalDosyalari,
      paylasilanBelgeler: {for (final x in (paylasim['belgeler'] as List? ?? const [])) '$x'},
      mesajlar: mesajlar,
    );
    depo.etikDuvar.yukle([
      for (final j in duvarlar)
        EtikDuvarKaydi(
          dosyaId: j['dosyaId'] as String,
          kullanici: j['kullanici'] as String,
          gerekce: j['gerekce'] as String,
          kuran: j['kuran'] as String,
          tarih: _t(j['tarih']),
        )
          ..kaldiran = j['kaldiran'] as String?
          ..kaldirmaGerekcesi = j['kaldirmaGerekcesi'] as String?
          ..kaldirmaTarihi = _tn(j['kaldirmaTarihi']),
    ]);
    depo.sunucuBuroVerisiniYukle(
      taraflar: [for (final j in taraflar) tarafJson(j)],
      gorevler: [for (final j in gorevler) gorevJson(j)],
      durusmalar: [for (final j in durusmalar) durusmaJson(j)],
      tebligatlar: [for (final j in tebligatlar) tebligatJson(j, depo.kiraciId)],
      vekaletnameler: [for (final j in vekaletnameler) vekaletnameJson(j, depo.kiraciId)],
    );
  }

  /// Kişi, cari, emanet, zaman (son bir yıl) ve icra verisini yükler.
  Future<void> _isVerisiniYenile() async {
    final bugun = Tarih.from(DateTime.now());
    final kisiler = _liste(await api.get('/kisiler'));
    final cari = _liste(await api.get('/cari'));
    final emanet = _liste(await api.get('/emanet'));
    final zaman = _liste(await api.get('/zaman?bas=${bugun.gunEkle(-365).isoBicim}&son=${bugun.isoBicim}'));
    final icra = _liste(await api.get('/icra'));
    depo.sunucuIsVerisiniYukle(
      kisiler: [for (final j in kisiler) kisiJson(j, depo.kiraciId)],
      iliskiler: [for (final j in _liste(await api.get('/kisi-iliskileri'))) iliskiJson(j)],
      cari: [for (final j in cari) cariJson(j)],
      emanetHareketleri: [for (final j in emanet) emanetJson(j)],
      zamanKayitlari: [for (final j in zaman) zamanJson(j)],
      icra: [for (final j in icra) icraJson(j)],
    );
  }

  @override
  Future<void> yenile() async {
    final kullanicilar = (await api.get('/kullanicilar') as List).cast<Map<String, dynamic>>();
    depo.kullaniciAdlariniYukle({for (final u in kullanicilar) u['id'] as String: u['adSoyad'] as String});
    depo.kullaniciBilgileriniYukle([
      for (final u in kullanicilar)
        KullaniciBilgisi(
          id: u['id'] as String,
          adSoyad: u['adSoyad'] as String,
          aktif: u['aktif'] != false,
          roller: {for (final r in (u['roller'] as List? ?? const [])) ...Rol.values.where((x) => x.name == r)},
          eposta: u['eposta'] as String?,
        ),
    ]);
    final liste = (await api.get('/dosyalar') as List).cast<Map<String, dynamic>>();
    final dosyalar = [for (final j in liste) dosyaJson(j, depo.kiraciId)];
    final sureler = <SureKaydi>[];
    final belgeler = <Belge>[];
    for (final d in dosyalar) {
      for (final j in _liste(await api.get('/dosyalar/${d.id}/belgeler'))) {
        final b = belgeJson(j, d.id, depo.kiraciId);
        if (b != null) belgeler.add(b);
      }
      final sj = (await api.get('/dosyalar/${d.id}/sureler') as List).cast<Map<String, dynamic>>();
      for (final j in sj) {
        final s = sureJson(j, d.id);
        if (s != null) sureler.add(s);
      }
    }
    depo.sunucuVerisiniYukle(dosyalar: dosyalar, sureler: sureler, belgeler: belgeler);
    await _isVerisiniYenile();
    await _buroVerisiniYenile();
    await _saklamaVerisiniYenile();
  }

  Future<void> _saklamaVerisiniYenile() async {
    final Map<String, dynamic> j;
    try {
      j = (await api.get('/kvkk/saklama') as Map).cast<String, dynamic>();
    } on Exception {
      return; // yetkisi olmayan ya da eski sunucu: yerel görünüm kalır
    }
    final son = j['sonPeriyodikImha'] as String?;
    depo.sunucuSaklamaVerisiniYukle(
      sonPeriyodikImha: son == null ? null : Tarih.parse(son),
      kayitlar: [for (final k in _liste(j['kayitlar'])) saklamaKaydiJson(k)],
      tutanaklar: [
        for (final t in _liste(j['tutanaklar']))
          (
            t['id'] as String,
            ImhaTutanagi(
              no: t['no'] as String,
              tarih: Tarih.parse(t['tarih'] as String),
              kayitIdleri: [for (final d in (t['dosyalar'] as List? ?? const [])) '$d'],
              yontem: ImhaYontemi.values.byName(t['yontem'] as String),
              hazirlayan: t['hazirlayan'] as String,
            )
              ..onaylayan = t['onaylayan'] as String?
              ..onayTarihi = t['onayTarihi'] == null ? null : Tarih.parse(t['onayTarihi'] as String),
          ),
      ],
    );
  }

  static SaklamaKaydi saklamaKaydiJson(Map<String, dynamic> j) => SaklamaKaydi(
        id: j['id'] as String,
        ad: j['ad'] as String,
        kategori: VeriKategorisi.values.byName(j['kategori'] as String),
        kapanis: j['kapanis'] == null ? null : Tarih.parse(j['kapanis'] as String),
        yasalSaklamaEngeli: j['saklamaEngeli'] as String?,
      );

  @override
  Future<void> denetimKaydet(DenetimIslemi islem, String nesneTuru, String nesneId, String aciklama) async {
    await api.post('/denetim/kayit', {'islem': islem.name, 'nesneTuru': nesneTuru, 'nesneId': nesneId, 'aciklama': aciklama});
  }

  @override
  Future<(List<SunucuDenetimOlayi>, int?)> denetimGetir() async {
    final liste = [for (final j in _liste(await api.get('/denetim'))) SunucuDenetimOlayi.json(j)];
    final d = (await api.get('/denetim/dogrula') as Map).cast<String, dynamic>();
    return (liste, d['saglam'] == true ? null : (d['bozukSira'] as num?)?.toInt());
  }

  @override
  Future<void> imhaTutanagiHazirla(Set<String> dosyaIdleri, ImhaYontemi yontem) async {
    await api.post('/kvkk/imha-tutanagi', {'dosyalar': dosyaIdleri.toList(), 'yontem': yontem.name});
    await _saklamaVerisiniYenile();
  }

  @override
  Future<void> imhaTutanagiOnayla(String tutanakId) async {
    await api.post('/kvkk/imha-tutanagi/$tutanakId/onay', const {});
    await _saklamaVerisiniYenile();
  }

  @override
  Future<void> dosyaAc({
    required DosyaTuru tur,
    required String baslik,
    required String sorumlu,
    String? yedekSorumlu,
    bool gizli = false,
    String? muvekkilId,
    String? karsiTarafId,
    String? mahkeme,
    String? esasNo,
    GorevSablonu? sablon,
  }) async {
    await api.post('/dosyalar', {
      'tur': tur.name,
      'baslik': baslik,
      'sorumlu': sorumlu,
      if (yedekSorumlu != null) 'yedekSorumlu': yedekSorumlu,
      'gizli': gizli,
      if (mahkeme != null && mahkeme.trim().isNotEmpty) 'mahkeme': mahkeme.trim(),
      if (esasNo != null && esasNo.trim().isNotEmpty) 'esasNo': esasNo.trim(),
      if (sablon != null) 'gorevSablonu': sablon.toJson(),
      'taraflar': [
        if (muvekkilId != null) {'kisiId': muvekkilId, 'sifat': 'muvekkil'},
        if (karsiTarafId != null) {'kisiId': karsiTarafId, 'sifat': 'karsiTaraf'},
      ],
    });
    await yenile();
  }

  @override
  Future<Tarih> sureHesapla({required String dosyaId, required String kuralKodu, required Tarih tarih, String? aciklama}) async {
    final y = await api.post('/dosyalar/$dosyaId/sureler', {
      'kuralKodu': kuralKodu,
      'tarih': tarih.isoBicim,
      if (aciklama != null) 'aciklama': aciklama,
    }) as Map<String, dynamic>;
    await yenile();
    return _t(y['sonGun']);
  }

  @override
  Future<void> sureTeyit(String sureId) async {
    await api.post('/sureler/$sureId/teyit');
    await yenile();
  }

  @override
  Future<void> sureTamamla(String sureId, String kanit) async {
    await api.post('/sureler/$sureId/tamamla', {'kanit': kanit});
    await yenile();
  }

  @override
  Future<void> kisiEkle({required KisiTuru tur, required String ad, String? kimlikNo, String? eposta, String? telefon}) async {
    await api.post('/kisiler', {
      'tur': tur.name,
      'ad': ad.trim(),
      if (kimlikNo != null && kimlikNo.trim().isNotEmpty) 'kimlikNo': kimlikNo.trim(),
      if (eposta != null && eposta.trim().isNotEmpty) 'eposta': eposta.trim(),
      if (telefon != null && telefon.trim().isNotEmpty) 'telefon': telefon.trim(),
    });
    await _isVerisiniYenile();
  }

  @override
  Future<int> kisileriAktar(List<AktarimSatiri> satirlar) async {
    String? d(AktarimSatiri s, KisiAlani a) => s.deger(a).trim().isEmpty ? null : s.deger(a).trim();
    final y = await api.post('/kisiler/toplu', {
      'kisiler': [
        for (final s in satirlar)
          {
            'satirNo': s.satirNo,
            'tur': s.tur.name,
            'ad': s.deger(KisiAlani.ad).trim(),
            'kimlikNo': d(s, KisiAlani.kimlikNo),
            'eposta': d(s, KisiAlani.eposta),
            'telefon': d(s, KisiAlani.telefon),
            'adres': d(s, KisiAlani.adres),
          },
      ],
    }) as Map<String, dynamic>;
    await _isVerisiniYenile();
    return (y['eklenen'] as num).toInt();
  }

  @override
  Future<(int, int)> dosyalariAktar(List<DosyaAktarimSatiri> satirlar, {required String sorumlu, String? yedekSorumlu}) async {
    final y = await api.post('/dosyalar/toplu', {
      'sorumlu': sorumlu,
      if (yedekSorumlu != null) 'yedekSorumlu': yedekSorumlu,
      'dosyalar': [
        for (final s in satirlar)
          {
            'satirNo': s.satirNo,
            'tur': s.tur.name,
            'baslik': s.baslik,
            'mahkeme': s.mahkeme,
            'esasNo': s.esasNo,
            if (s.acilis != null) 'acilis': s.acilis!.isoBicim,
          },
      ],
    }) as Map<String, dynamic>;
    await yenile();
    return ((y['eklenen'] as num).toInt(), (y['atlanan'] as num).toInt());
  }

  @override
  Future<List<List<String>>> tabloOku(String dosyaAdi, List<int> icerik) async {
    final y = await api.postBayt('/aktarim/tablo', icerik, {'x-dosya-adi': Uri.encodeComponent(dosyaAdi)})
        as Map<String, dynamic>;
    return [for (final s in (y['satirlar'] as List)) [for (final h in (s as List)) '${h ?? ''}']];
  }

  @override
  Future<void> kisiGuncelle(Kisi kisi) async {
    await api.put('/kisiler/${kisi.id}', {
      'ad': kisi.ad,
      'kimlikNo': kisi.kimlikNo,
      'mersisNo': kisi.mersisNo,
      'eposta': kisi.eposta,
      'telefon': kisi.telefon,
      'adres': kisi.adres,
      'iletisimTercihi': kisi.iletisimTercihi.name,
      'notlar': kisi.notlar,
    });
    await _isVerisiniYenile();
  }

  @override
  Future<void> iliskiEkle({required String kisiA, required String kisiB, required IliskiTuru tur}) async {
    await api.post('/kisi-iliskileri', {'kisiA': kisiA, 'kisiB': kisiB, 'tur': tur.name});
    await _isVerisiniYenile();
  }

  @override
  Future<void> iliskiSil(String iliskiId) async {
    await api.delete('/kisi-iliskileri/$iliskiId');
    await _isVerisiniYenile();
  }

  static (String, KisiIliskisi) iliskiJson(Map<String, dynamic> j) => (
        j['id'] as String,
        KisiIliskisi(kisiA: j['kisiA'] as String, kisiB: j['kisiB'] as String, tur: IliskiTuru.values.byName(j['tur'] as String)),
      );

  @override
  Future<void> cariEkle({
    required String muvekkilId,
    required CariHareketTuru tur,
    required Para tutar,
    required String aciklama,
    String? dosyaId,
  }) async {
    await api.post('/cari', {
      'muvekkilId': muvekkilId,
      if (dosyaId != null) 'dosyaId': dosyaId,
      'tur': tur.name,
      'tutarKurus': tutar.kurus,
      'aciklama': aciklama,
    });
    await _isVerisiniYenile();
  }

  @override
  Future<void> emanetEkle(EmanetHareketi h) async {
    await api.post('/emanet', {
      'muvekkilId': h.muvekkilId,
      'dosyaId': h.dosyaId,
      'tur': h.tur.name,
      'tutarKurus': h.tutar.kurus,
      'tarih': h.tarih.isoBicim,
      'aciklama': h.aciklama,
      if (h.mahsupOnayi != null) 'mahsupOnayi': h.mahsupOnayi,
    });
    await _isVerisiniYenile();
  }

  @override
  Future<void> zamanEkle({
    required String dosyaId,
    required int dakika,
    required String aciklama,
    bool faturalanabilir = true,
    Tarih? tarih,
  }) async {
    await api.post('/zaman', {
      'dosyaId': dosyaId,
      'dakika': dakika,
      'aciklama': aciklama,
      'faturalanabilir': faturalanabilir,
      if (tarih != null) 'tarih': tarih.isoBicim,
    });
    await _isVerisiniYenile();
  }

  @override
  Future<void> zamanOnayla(String id) async {
    await api.post('/zaman/$id/onayla');
    await _isVerisiniYenile();
  }

  @override
  Future<void> zamanSil(String id) async {
    await api.delete('/zaman/$id');
    await _isVerisiniYenile();
  }

  @override
  Future<String> icraEkle({
    required String dosyaId,
    required String icraDairesi,
    required String borclu,
    required TakipTalebi talep,
    required FaizTuru faizTuru,
    double? akdiOran,
    String? esasNo,
    Para? vekaletUcreti,
  }) async {
    final y = await api.post('/icra', {
      'dosyaId': dosyaId,
      'icraDairesi': icraDairesi,
      'borclu': borclu,
      if (esasNo != null && esasNo.trim().isNotEmpty) 'esasNo': esasNo.trim(),
      'takipTuru': talep.tur.name,
      'faizTuru': faizTuru.name,
      if (akdiOran != null) 'akdiOran': akdiOran,
      'asilKurus': talep.asilAlacak.kurus,
      'temerrut': talep.temerrutTarihi.isoBicim,
      'takipTarihi': talep.takipTarihi.isoBicim,
      'takipOncesiMasrafKurus': talep.takipOncesiMasraf.kurus,
      if (vekaletUcreti != null) 'vekaletKurus': vekaletUcreti.kurus,
    }) as Map<String, dynamic>;
    await _isVerisiniYenile();
    return y['id'] as String;
  }

  @override
  Future<void> icraTahsilat(String icraId, Para tutar, Tarih tarih, String aciklama) async {
    await api.post('/icra/$icraId/tahsilat', {'tutarKurus': tutar.kurus, 'tarih': tarih.isoBicim, 'aciklama': aciklama});
    await _isVerisiniYenile();
  }

  @override
  Future<void> icraDurumu(String icraId, IcraDurumu durum) async {
    await api.post('/icra/$icraId/durum', {'durum': durum.name});
    await _isVerisiniYenile();
  }

  @override
  Future<void> gorevKapat(String gorevId, {String? kanit}) async {
    await api.post('/gorevler/$gorevId/kapat', {if (kanit != null) 'kanit': kanit});
    await _buroVerisiniYenile();
  }

  @override
  Future<List<String>> durusmaEkle({
    required String dosyaId,
    required DateTime baslangic,
    required String yer,
    required String katilan,
    String tur = 'Duruşma',
  }) async {
    final y = await api.post('/durusmalar', {
      'dosyaId': dosyaId,
      'baslangic': baslangic.toUtc().toIso8601String(),
      'yer': yer,
      'katilan': katilan,
      'tur': tur,
    }) as Map<String, dynamic>;
    await _buroVerisiniYenile();
    return [for (final c in _liste(y['cakismalar'] ?? const [])) c['neden'] as String];
  }

  @override
  Future<Tebligat> tebligatEkle(Tebligat t) async {
    final y = await api.post('/tebligatlar', {
      'kanal': t.kanal.name,
      'ulasmaTarihi': t.ulasmaTarihi.isoBicim,
      'tebligTarihi': t.tebligTarihi.isoBicim,
      'gonderen': t.gonderen,
      'konu': t.konu,
      if (t.esasNo != null) 'esasNo': t.esasNo,
      'taraflar': t.taraflar,
      if (t.belgeOzeti != null) 'belgeOzeti': t.belgeOzeti,
      if (t.dosyaId != null) 'dosyaId': t.dosyaId,
    }) as Map<String, dynamic>;
    await _buroVerisiniYenile();
    return tebligatJson(y, depo.kiraciId);
  }

  @override
  Future<void> tebligatBagla(String tebligatId, String dosyaId) async {
    await api.post('/tebligatlar/$tebligatId/bagla', {'dosyaId': dosyaId});
    await _buroVerisiniYenile();
  }

  @override
  Future<void> vekaletnameEkle({
    required String muvekkilId,
    required Set<String> avukatlar,
    required Tarih duzenlemeTarihi,
    String? noter,
    String? yevmiyeNo,
    bool genel = true,
    Set<String> dosyalar = const {},
    Set<OzelYetki> ozelYetkiler = const {},
    String? asilEvrakYeri,
  }) async {
    await api.post('/vekaletnameler', {
      'muvekkilId': muvekkilId,
      'avukatlar': avukatlar.toList(),
      'duzenlemeTarihi': duzenlemeTarihi.isoBicim,
      if (noter != null) 'noter': noter,
      if (yevmiyeNo != null) 'yevmiyeNo': yevmiyeNo,
      'genel': genel,
      'dosyalar': dosyalar.toList(),
      'ozelYetkiler': [for (final y in ozelYetkiler) y.name],
      if (asilEvrakYeri != null) 'asilEvrakYeri': asilEvrakYeri,
    });
    await _buroVerisiniYenile();
  }

  @override
  Future<void> etikDuvarKur(String dosyaId, String kullanici, String gerekce) async {
    await api.post('/dosyalar/$dosyaId/etik-duvar', {'kullaniciId': kullanici, 'gerekce': gerekce.trim()});
    await yenile();
  }

  @override
  Future<void> etikDuvarKaldir(String dosyaId, String kullanici, String gerekce) async {
    await api.post('/dosyalar/$dosyaId/etik-duvar/kaldir', {'kullaniciId': kullanici, 'gerekce': gerekce.trim()});
    await yenile();
  }

  @override
  Future<void> belgeYukle({
    required String dosyaId,
    required String ad,
    required String dosyaAdi,
    required List<int> icerik,
    BelgeTuru tur = BelgeTuru.diger,
  }) async {
    await api.postBayt('/dosyalar/$dosyaId/belgeler', icerik, {
      'x-dosya-adi': Uri.encodeComponent(dosyaAdi),
      'x-belge-adi': Uri.encodeComponent(ad),
      'x-belge-turu': tur.name,
    });
    await yenile();
  }

  @override
  Future<(List<BelgeAramaSonucu>, int)> belgeAra(String sorgu) async {
    final y = await api.get('/belgeler/ara?q=${Uri.encodeQueryComponent(sorgu)}') as Map<String, dynamic>;
    return (
      [
        for (final j in _liste(y['sonuclar']))
          (
            belgeId: j['belgeId'] as String,
            ad: j['ad'] as String,
            dosyaId: j['dosyaId'] as String?,
            dosyaNo: j['dosyaNo'] as String?,
            ozet: j['ozet'] as String? ?? '',
            ocr: j['ocr'] == true,
          ),
      ],
      (y['bekleyen'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> wordBelgeKaydet(
      {required String dosyaId, required String ad, required String metin, BelgeTuru tur = BelgeTuru.diger, bool pdf = false}) async {
    await api.post('/dosyalar/$dosyaId/belgeler/word', {'ad': ad, 'metin': metin, 'tur': tur.name, 'bicim': pdf ? 'pdf' : 'docx'});
    await yenile();
  }

  @override
  Future<void> portalPaylas(String dosyaId, bool paylas) async {
    await api.post('/dosyalar/$dosyaId/portal', {'paylas': paylas});
    await _buroVerisiniYenile();
  }

  @override
  Future<void> belgePaylas(String belgeId, bool paylas) async {
    await api.post('/belgeler/$belgeId/portal', {'paylas': paylas});
    await _buroVerisiniYenile();
  }

  @override
  Future<void> mesajGonder(String dosyaId, String metin) async {
    await api.post('/dosyalar/$dosyaId/mesajlar', {'metin': metin.trim()});
    await _buroVerisiniYenile();
  }

  @override
  Future<void> mesajlariOku(String dosyaId) async {
    await api.post('/dosyalar/$dosyaId/mesajlar/okundu');
    await _buroVerisiniYenile();
  }

  @override
  Future<List<Map<String, dynamic>>> davetler() async => _liste(await api.get('/davetler'));

  @override
  Future<String> davetEt(String eposta, Set<Rol> roller, {String? kisiId}) async {
    final y = await api.post('/davetler', {
      'eposta': eposta.trim().toLowerCase(),
      'roller': [for (final r in roller) r.name],
      if (kisiId != null) 'kisiId': kisiId,
    }) as Map<String, dynamic>;
    return y['kod'] as String;
  }

  @override
  Future<void> davetIptal(String davetId) async {
    await api.post('/davetler/$davetId/iptal');
  }

  @override
  Future<void> kullaniciRolleri(String kullaniciId, Set<Rol> roller) async {
    await api.put('/kullanicilar/$kullaniciId/roller', {'roller': [for (final r in roller) r.name]});
    await yenile();
  }

  @override
  Future<int> kullaniciPasiflestir(String kullaniciId, {String? devralan, required String gerekce}) async {
    final y = await api.post('/kullanicilar/$kullaniciId/pasif', {'devralan': devralan, 'gerekce': gerekce}) as Map<String, dynamic>;
    await yenile();
    return (y['devredilen'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> kullaniciAktiflestir(String kullaniciId) async {
    await api.post('/kullanicilar/$kullaniciId/aktif');
    await yenile();
  }

  @override
  Future<void> sifreDegistir(String eskiSifre, String yeniSifre) async {
    await api.post('/ben/sifre', {'eskiSifre': eskiSifre, 'yeniSifre': yeniSifre});
  }

  @override
  Future<List<Map<String, dynamic>>> oturumlar() async => _liste(await api.get('/ben/oturumlar'));

  @override
  Future<int> oturumKapat(String? kimlik) async {
    final y = await api.post(kimlik == null ? '/ben/oturumlar/digerlerini-kapat' : '/ben/oturumlar/$kimlik/kapat')
        as Map<String, dynamic>;
    return (y['kapatilan'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<Map<String, dynamic>> takvimDurumu() async => (await api.get('/ben/takvim') as Map).cast<String, dynamic>();

  @override
  Future<(String, String)> takvimBaglantisiOlustur() async {
    final y = (await api.post('/ben/takvim') as Map).cast<String, dynamic>();
    return (y['adres'] as String, y['webcal'] as String);
  }

  @override
  Future<void> takvimBaglantisiKapat() async {
    await api.delete('/ben/takvim');
  }

  @override
  Future<(int, int)> koltuklar() async {
    final y = await api.get('/koltuklar') as Map<String, dynamic>;
    return (y['lisans'] as int, y['dolu'] as int);
  }

  @override
  Future<bool> ikiAdimliAcikMi() async => (await api.get('/ben') as Map<String, dynamic>)['ikiAdimli'] == true;

  @override
  Future<(String, String)> ikiAdimliBaslat() async {
    final y = await api.post('/ben/iki-adimli/baslat') as Map<String, dynamic>;
    return (y['sir'] as String, y['otpauth'] as String);
  }

  @override
  Future<void> ikiAdimliEtkinlestir(String kod) async {
    await api.post('/ben/iki-adimli/etkinlestir', {'kod': kod.trim()});
  }

  @override
  Future<void> ikiAdimliKapat(String kod) async {
    await api.post('/ben/iki-adimli/kapat', {'kod': kod.trim()});
  }

  @override
  Future<Map<String, dynamic>> abonelik() async => await api.get('/abonelik') as Map<String, dynamic>;

  @override
  Future<Uri> odemeBaslat(OdemeDonemi donem, {int? koltuk}) async {
    final y = await api.post('/abonelik/odeme', {'donem': donem.name, if (koltuk != null) 'koltuk': koltuk}) as Map<String, dynamic>;
    return Uri.parse(y['odemeAdresi'] as String);
  }

  @override
  Future<void> abonelikIptal(bool iptal) async {
    await api.post('/abonelik/iptal', {'iptal': iptal});
  }

  @override
  Future<int> topluTakip({
    required String muvekkilId,
    required String icraDairesi,
    required TakipTuru tur,
    required List<TopluTakipSatiri> satirlar,
  }) async {
    String tarih(Tarih t) => '${t.gun.toString().padLeft(2, '0')}.${t.ay.toString().padLeft(2, '0')}.${t.yil}';
    String tutar(Para p) => '${p.kurus ~/ 100},${(p.kurus % 100).toString().padLeft(2, '0')}';
    final y = await api.post('/icra/toplu', {
      'muvekkilId': muvekkilId,
      'icraDairesi': icraDairesi,
      'takipTuru': tur.name,
      'satirlar': [
        for (final s in satirlar) [s.borclu, s.kimlikNo ?? '', tutar(s.alacak!), tarih(s.temerrut!)],
      ],
    }) as Map<String, dynamic>;
    await yenile();
    return y['acilan'] as int;
  }

  @override
  Future<String> zamanFaturaKes(String dosyaId) async {
    final y = await api.post('/dosyalar/$dosyaId/zaman-faturasi') as Map<String, dynamic>;
    await _isVerisiniYenile();
    return y['faturaNo'] as String;
  }
}
