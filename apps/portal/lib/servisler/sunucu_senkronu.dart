import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import 'api_istemcisi.dart';
import 'veri_deposu.dart';

/// Depodaki bazı işlemlerin sunucuda yapılması için kanca. Sunucu bağlıyken ekranlar bu yolu kullanır;
/// sonuç her işlemden sonra sunucudan yeniden yüklenir (sunucu tek doğru kaynaktır).
abstract class UzakIslemler {
  Future<void> yenile();

  Future<void> dosyaAc({required DosyaTuru tur, required String baslik, required String sorumlu, String? yedekSorumlu, bool gizli});

  /// Süre sunucuda hesaplanır; dönen son gün.
  Future<Tarih> sureHesapla({required String dosyaId, required String kuralKodu, required Tarih tarih, String? aciklama});

  Future<void> sureTeyit(String sureId);

  Future<void> sureTamamla(String sureId, String kanit);
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
  }

  @override
  Future<void> dosyaAc({
    required DosyaTuru tur,
    required String baslik,
    required String sorumlu,
    String? yedekSorumlu,
    bool gizli = false,
  }) async {
    await api.post('/dosyalar', {
      'tur': tur.name,
      'baslik': baslik,
      'sorumlu': sorumlu,
      if (yedekSorumlu != null) 'yedekSorumlu': yedekSorumlu,
      'gizli': gizli,
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
}
