import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import 'api_istemcisi.dart';
import 'veri_deposu.dart';

/// Depodaki bazı işlemlerin sunucuda yapılması için kanca. Sunucu bağlıyken ekranlar bu yolu kullanır;
/// sonuç her işlemden sonra sunucudan yeniden yüklenir (sunucu tek doğru kaynaktır).
abstract class UzakIslemler {
  Future<void> yenile();

  Future<void> dosyaAc({
    required DosyaTuru tur,
    required String baslik,
    required String sorumlu,
    String? yedekSorumlu,
    bool gizli,
    String? muvekkilId,
    String? karsiTarafId,
  });

  /// Süre sunucuda hesaplanır; dönen son gün.
  Future<Tarih> sureHesapla({required String dosyaId, required String kuralKodu, required Tarih tarih, String? aciklama});

  Future<void> sureTeyit(String sureId);

  Future<void> sureTamamla(String sureId, String kanit);

  Future<void> kisiEkle({required KisiTuru tur, required String ad, String? kimlikNo, String? eposta});

  Future<void> cariEkle({required String muvekkilId, required CariHareketTuru tur, required Para tutar, required String aciklama, String? dosyaId});

  Future<void> emanetEkle(EmanetHareketi h);

  Future<void> zamanEkle({required String dosyaId, required int dakika, required String aciklama, bool faturalanabilir, Tarih? tarih});

  Future<void> zamanOnayla(String id);

  Future<void> zamanSil(String id);

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

  Future<void> gorevKapat(String gorevId, {String? kanit});

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

class SunucuSenkronu implements UzakIslemler {
  SunucuSenkronu(this.api, this.depo) {
    depo.uzak = this;
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
        eposta: j['eposta'] as String?,
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
  Future<void> _buroVerisiniYenile() async {
    final taraflar = _liste(await api.get('/taraflar'));
    final gorevler = _liste(await api.get('/gorevler'));
    final durusmalar = _liste(await api.get('/durusmalar'));
    final tebligatlar = _liste(await api.get('/tebligatlar'));
    final vekaletnameler = _liste(await api.get('/vekaletnameler'));
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
    final liste = (await api.get('/dosyalar') as List).cast<Map<String, dynamic>>();
    final dosyalar = [for (final j in liste) dosyaJson(j, depo.kiraciId)];
    final sureler = <SureKaydi>[];
    for (final d in dosyalar) {
      final sj = (await api.get('/dosyalar/${d.id}/sureler') as List).cast<Map<String, dynamic>>();
      for (final j in sj) {
        final s = sureJson(j, d.id);
        if (s != null) sureler.add(s);
      }
    }
    depo.sunucuVerisiniYukle(dosyalar: dosyalar, sureler: sureler);
    await _isVerisiniYenile();
    await _buroVerisiniYenile();
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
  }) async {
    await api.post('/dosyalar', {
      'tur': tur.name,
      'baslik': baslik,
      'sorumlu': sorumlu,
      if (yedekSorumlu != null) 'yedekSorumlu': yedekSorumlu,
      'gizli': gizli,
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
  Future<void> kisiEkle({required KisiTuru tur, required String ad, String? kimlikNo, String? eposta}) async {
    await api.post('/kisiler', {
      'tur': tur.name,
      'ad': ad.trim(),
      if (kimlikNo != null && kimlikNo.trim().isNotEmpty) 'kimlikNo': kimlikNo.trim(),
      if (eposta != null && eposta.trim().isNotEmpty) 'eposta': eposta.trim(),
    });
    await _isVerisiniYenile();
  }

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
}
