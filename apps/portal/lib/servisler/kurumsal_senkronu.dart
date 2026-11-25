import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import 'api_istemcisi.dart';
import 'kurumsal_depo.dart';

/// Kurumsal depodaki işlemlerin sunucuda yapılması için kanca. Her işlemden sonra veri sunucudan yeniden yüklenir.
abstract class KurumsalUzak {
  Future<void> yenile();

  Future<void> sirketEkle({required String unvan, String? vkn, String? anaSirketId, String? kisaAd});

  /// Metin sunucuda taranır; yeni sözleşmenin kimliğini döner.
  Future<String> sozlesmeEkle({
    required String baslik,
    required String karsiTaraf,
    required String metin,
    String birim,
    SozlesmeTuru? tur,
    String? sirketId,
  });

  Future<void> sozlesmeDurumu(String sozlesmeId, SozlesmeDurumu hedef, {Tarih? baslangic});

  Future<void> onayKarari(String sozlesmeId, OnayKarariTuru tur, {String not});

  Future<void> yukumlulukEkle(String sozlesmeId, String aciklama, YukumlulukTarafi taraf, Tarih sonTarih);

  Future<void> yukumlulukTamamla(String yukumlulukId);

  Future<void> talepOlustur({
    required String baslik,
    required String aciklama,
    required TalepTuru tur,
    required Oncelik oncelik,
    required String birim,
    String? sozlesmeId,
    String? sirketId,
  });

  Future<void> talepDurumu(String talepId, TalepDurumu hedef, {String not});

  Future<void> talepAta(String talepId, String kisi);

  /// İhbarı kaydeder; ihbarcıya iletilecek takip kodunu döner (sunucuda yalnızca özeti tutulur).
  Future<String> ihbarKaydet({required IhbarKanali kanal, required IhbarKategorisi kategori, required String aciklama, String? iletisim});

  Future<void> sorusturmaAc(String ihbarId, String sorumlu);

  /// [islem]: sorusturmayaAl, raporlamayaGec, reddet, kapat, geriBildirim, not.
  Future<void> sorusturmaIslemi(String sorusturmaId, String islem, {String metin, SorusturmaSonucu? sonuc});

  Future<void> ihlalKaydet(String aciklama, DateTime ogrenilme, {int? etkilenen});

  /// [hedef]: kurul veya ilgililer.
  Future<void> ihlalBildirim(String ihlalId, String hedef);
}

class KurumsalSenkronu implements KurumsalUzak {
  KurumsalSenkronu(this.api, this.kurumsal) {
    kurumsal.uzak = this;
  }

  final ApiIstemcisi api;
  final KurumsalDepo kurumsal;

  static Tarih? _t(Object? v) => v is String ? Tarih.parse(v) : null;
  static List<Map<String, dynamic>> _liste(Object? v) => (v! as List).cast<Map<String, dynamic>>();

  static const _hukukRolleri = {'hukukDirektoru', 'sirketAvukati', 'hukukUzmani'};

  static Sirket sirketJson(Map<String, dynamic> j) => Sirket(
        id: j['id'] as String,
        unvan: j['unvan'] as String,
        vkn: j['vkn'] as String?,
        anaSirketId: j['anaSirketId'] as String?,
        kisaAd: j['kisaAd'] as String?,
      );

  static Sozlesme sozlesmeJson(Map<String, dynamic> j) {
    final bedel = j['bedelKurus'] as int?;
    final tarama = j['tarama'];
    return Sozlesme(
      id: j['id'] as String,
      no: j['no'] as String,
      sirketId: j['sirketId'] as String?,
      baslik: j['baslik'] as String,
      tur: SozlesmeTuru.values.firstWhere((t) => t.name == j['tur'], orElse: () => SozlesmeTuru.diger),
      karsiTaraf: j['karsiTaraf'] as String? ?? '',
      sorumlu: j['sorumlu'] as String,
      birim: j['birim'] as String? ?? '',
      durum: SozlesmeDurumu.values.firstWhere((d) => d.name == j['durum'], orElse: () => SozlesmeDurumu.taslak),
      baslangic: _t(j['baslangic']),
      bitis: _t(j['bitis']),
      otomatikYenileme: j['otomatikYenileme'] == true,
      yenilemeSuresiAy: j['yenilemeSuresiAy'] as int? ?? 12,
      ihbarSuresiGun: j['ihbarSuresiGun'] as int?,
      bedel: bedel == null ? null : Para.kurus(bedel, birim: j['paraBirimi'] as String? ?? 'TRY'),
      tarama: tarama is Map<String, dynamic> ? TaramaSonucu.fromJson(tarama) : null,
      yukumlulukler: [
        for (final y in (j['yukumlulukler'] as List? ?? const []).cast<Map<String, dynamic>>())
          Yukumluluk(
            id: y['id'] as String,
            aciklama: y['aciklama'] as String,
            taraf: YukumlulukTarafi.values.firstWhere((t) => t.name == y['taraf'], orElse: () => YukumlulukTarafi.biz),
            sonTarih: _t(y['sonTarih'])!,
            sorumlu: y['sorumlu'] as String? ?? '',
            tamamlandi: y['tamamlandi'] == true,
          ),
      ],
    );
  }

  static HukukTalebi talepJson(Map<String, dynamic> j) {
    final t = HukukTalebi(
      id: j['id'] as String,
      no: j['no'] as String,
      sirketId: j['sirketId'] as String?,
      baslik: j['baslik'] as String,
      aciklama: j['aciklama'] as String? ?? '',
      tur: TalepTuru.values.firstWhere((x) => x.name == j['tur'], orElse: () => TalepTuru.diger),
      oncelik: Oncelik.values.firstWhere((x) => x.name == j['oncelik'], orElse: () => Oncelik.normal),
      talepEden: j['talepEden'] as String,
      birim: j['birim'] as String,
      olusturma: _t(j['olusturma'])!,
      slaSonGun: _t(j['slaSonGun'])!,
      sozlesmeId: j['sozlesmeId'] as String?,
      beklemeBaslangici: _t(j['beklemeBaslangici']),
    )
      ..atanan = j['atanan'] as String? ?? ''
      ..durum = TalepDurumu.values.firstWhere((x) => x.name == j['durum'], orElse: () => TalepDurumu.yeni)
      ..kapanis = _t(j['kapanis']);
    for (final o in (j['gecmis'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      t.gecmis.add(TalepOlayi(_t(o['tarih'])!, o['kullanici'] as String, o['aciklama'] as String));
    }
    return t;
  }

  /// Sunucudaki onay turu: adımlar, kararlar ve durum.
  static OnaySureci? surecJson(String sozlesmeId, String baslatan, Map<String, dynamic> j) {
    if ((j['tur'] as int? ?? 0) == 0) return null;
    final surec = OnaySureci(
      sozlesmeId: sozlesmeId,
      baslatan: baslatan,
      adimlar: [
        for (final a in (j['adimlar'] as List? ?? const []).cast<Map<String, dynamic>>())
          OnayAdimi(
            kod: a['kod'] as String,
            ad: a['ad'] as String,
            neden: a['neden'] as String? ?? '',
            onaycilar: {for (final o in (a['onaycilar'] as List? ?? const [])) '$o'},
          ),
      ],
    );
    for (final k in (j['kararlar'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      surec.kararlar.add(OnayKarari(
        adimKodu: k['adimKodu'] as String,
        kullanici: k['kullanici'] as String,
        tur: OnayKarariTuru.values.byName(k['karar'] as String),
        not: k['not'] as String? ?? '',
        zaman: DateTime.parse(k['zaman'] as String),
      ));
    }
    surec.durum = OnaySurecDurumu.values.firstWhere((d) => d.name == j['durum'], orElse: () => OnaySurecDurumu.devam);
    return surec;
  }

  static DateTime? _z(Object? v) => v is String ? DateTime.parse(v).toLocal() : null;

  /// Sunucudan gelen ihbar (soruşturmasıyla birlikte). Takip kodu sunucuda tutulmadığından boştur.
  static (Ihbar, Sorusturma?) ihbarJson(Map<String, dynamic> j) {
    final ihbar = Ihbar(
      id: j['id'] as String,
      takipKodu: '',
      zaman: _z(j['zaman'])!,
      kanal: IhbarKanali.values.firstWhere((x) => x.name == j['kanal'], orElse: () => IhbarKanali.web),
      kategori: IhbarKategorisi.values.firstWhere((x) => x.name == j['kategori'], orElse: () => IhbarKategorisi.diger),
      aciklama: j['aciklama'] as String,
      anonim: j['anonim'] != false,
      ihbarciIletisim: j['iletisim'] as String?,
      ilgiliKisiler: {for (final x in (j['ilgiliKisiler'] as List? ?? const [])) '$x'},
      sirketId: j['sirketId'] as String?,
    );
    final sj = j['sorusturma'];
    if (sj is! Map<String, dynamic>) return (ihbar, null);
    final s = Sorusturma(id: sj['id'] as String, ihbar: ihbar, sorumlu: sj['sorumlu'] as String, acilis: _z(sj['acilis'])!)
      ..durum = SorusturmaDurumu.values.firstWhere((d) => d.name == sj['durum'], orElse: () => SorusturmaDurumu.onInceleme)
      ..sonuc = SorusturmaSonucu.values.where((x) => x.name == sj['sonuc']).firstOrNull
      ..sonucOzeti = sj['sonucOzeti'] as String?
      ..ilkGeriBildirim = _z(sj['ilkGeriBildirim']);
    s.ekip.addAll([for (final x in (sj['ekip'] as List? ?? const [])) '$x']);
    for (final n in (sj['notlar'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      s.notlar.add(SorusturmaNotu(_z(n['zaman'])!, n['kullanici'] as String, n['metin'] as String));
    }
    return (ihbar, s);
  }

  static VeriIhlali ihlalJson(Map<String, dynamic> j) => VeriIhlali(
        id: j['id'] as String,
        ogrenilme: _z(j['ogrenilme'])!,
        aciklama: j['aciklama'] as String,
        etkilenenKisiSayisi: j['etkilenenKisiSayisi'] as int?,
      )
        ..kurulaBildirim = _z(j['kurulaBildirim'])
        ..ilgililereBildirim = _z(j['ilgililereBildirim']);

  Future<void> _uyumYenile() async {
    final ihbarlar = [for (final j in _liste(await api.get('/ihbarlar'))) ihbarJson(j)];
    final ihlaller = [for (final j in _liste(await api.get('/veri-ihlalleri'))) ihlalJson(j)];
    kurumsal.sunucuUyumVerisiniYukle(
      ihbarlar: [for (final (i, _) in ihbarlar) i],
      sorusturmalar: [for (final (_, s) in ihbarlar) if (s != null) s],
      ihlaller: ihlaller,
    );
  }

  @override
  Future<void> yenile() async {
    final sirketler = _liste(await api.get('/sirketler'));
    final sozlesmeler = [for (final j in _liste(await api.get('/sozlesmeler'))) sozlesmeJson(j)];
    final talepler = _liste(await api.get('/talepler'));
    final kullanicilar = _liste(await api.get('/kullanicilar'));
    final surecler = <String, OnaySureci>{};
    for (final s in sozlesmeler.where((s) => s.durum == SozlesmeDurumu.onayda)) {
      final j = await api.get('/sozlesmeler/${s.id}/onay') as Map<String, dynamic>;
      final p = surecJson(s.id, s.sorumlu, j);
      if (p != null) surecler[s.id] = p;
    }
    kurumsal.sunucuVerisiniYukle(
      sirketler: [for (final j in sirketler) sirketJson(j)],
      sozlesmeListesi: sozlesmeler,
      talepler: [for (final j in talepler) talepJson(j)],
      surecler: surecler,
      ekip: [
        for (final u in kullanicilar)
          if (u['aktif'] != false && (u['roller'] as List? ?? const []).any(_hukukRolleri.contains)) u['id'] as String,
      ],
    );
    await _uyumYenile();
  }

  @override
  Future<void> sirketEkle({required String unvan, String? vkn, String? anaSirketId, String? kisaAd}) async {
    await api.post('/sirketler', {
      'unvan': unvan.trim(),
      if (vkn != null && vkn.trim().isNotEmpty) 'vkn': vkn.trim(),
      if (anaSirketId != null) 'anaSirketId': anaSirketId,
      if (kisaAd != null && kisaAd.trim().isNotEmpty) 'kisaAd': kisaAd.trim(),
    });
    await yenile();
  }

  @override
  Future<String> sozlesmeEkle({
    required String baslik,
    required String karsiTaraf,
    required String metin,
    String birim = '',
    SozlesmeTuru? tur,
    String? sirketId,
  }) async {
    final y = await api.post('/sozlesmeler', {
      'baslik': baslik.trim(),
      'karsiTaraf': karsiTaraf.trim(),
      'metin': metin,
      'birim': birim.trim(),
      'tur': (tur ?? SozlesmeTuru.diger).name,
      if (sirketId != null) 'sirketId': sirketId,
    }) as Map<String, dynamic>;
    await yenile();
    return y['id'] as String;
  }

  @override
  Future<void> sozlesmeDurumu(String sozlesmeId, SozlesmeDurumu hedef, {Tarih? baslangic}) async {
    await api.post('/sozlesmeler/$sozlesmeId/durum', {
      'durum': hedef.name,
      if (baslangic != null) 'baslangic': baslangic.isoBicim,
    });
    await yenile();
  }

  @override
  Future<void> onayKarari(String sozlesmeId, OnayKarariTuru tur, {String not = ''}) async {
    await api.post('/sozlesmeler/$sozlesmeId/onay', {'karar': tur.name, 'not': not});
    await yenile();
  }

  @override
  Future<void> yukumlulukEkle(String sozlesmeId, String aciklama, YukumlulukTarafi taraf, Tarih sonTarih) async {
    await api.post('/sozlesmeler/$sozlesmeId/yukumlulukler',
        {'aciklama': aciklama.trim(), 'taraf': taraf.name, 'sonTarih': sonTarih.isoBicim});
    await yenile();
  }

  @override
  Future<void> yukumlulukTamamla(String yukumlulukId) async {
    await api.post('/yukumlulukler/$yukumlulukId/tamamla');
    await yenile();
  }

  @override
  Future<void> talepOlustur({
    required String baslik,
    required String aciklama,
    required TalepTuru tur,
    required Oncelik oncelik,
    required String birim,
    String? sozlesmeId,
    String? sirketId,
  }) async {
    await api.post('/talepler', {
      'baslik': baslik,
      'aciklama': aciklama,
      'tur': tur.name,
      'oncelik': oncelik.name,
      'birim': birim,
      if (sozlesmeId != null) 'sozlesmeId': sozlesmeId,
      if (sirketId != null) 'sirketId': sirketId,
    });
    await yenile();
  }

  @override
  Future<void> talepDurumu(String talepId, TalepDurumu hedef, {String not = ''}) async {
    await api.post('/talepler/$talepId/durum', {'durum': hedef.name, 'not': not});
    await yenile();
  }

  @override
  Future<void> talepAta(String talepId, String kisi) async {
    await api.post('/talepler/$talepId/ata', {'kullaniciId': kisi});
    await yenile();
  }

  @override
  Future<String> ihbarKaydet({
    required IhbarKanali kanal,
    required IhbarKategorisi kategori,
    required String aciklama,
    String? iletisim,
  }) async {
    final y = await api.post('/ihbarlar', {
      'kanal': kanal.name,
      'kategori': kategori.name,
      'aciklama': aciklama.trim(),
      if (iletisim != null && iletisim.trim().isNotEmpty) 'iletisim': iletisim.trim(),
      if (kurumsal.aktifSirketId != null) 'sirketId': kurumsal.aktifSirketId,
    }) as Map<String, dynamic>;
    await _uyumYenile();
    return y['takipKodu'] as String;
  }

  @override
  Future<void> sorusturmaAc(String ihbarId, String sorumlu) async {
    await api.post('/ihbarlar/$ihbarId/sorusturma', {'sorumlu': sorumlu});
    await _uyumYenile();
  }

  @override
  Future<void> sorusturmaIslemi(String sorusturmaId, String islem, {String metin = '', SorusturmaSonucu? sonuc}) async {
    switch (islem) {
      case 'geriBildirim':
        await api.post('/sorusturmalar/$sorusturmaId/geri-bildirim');
      case 'not':
        await api.post('/sorusturmalar/$sorusturmaId/not', {'metin': metin});
      default:
        await api.post('/sorusturmalar/$sorusturmaId/durum', {
          'islem': islem,
          'gerekce': metin,
          if (sonuc != null) 'sonuc': sonuc.name,
        });
    }
    await _uyumYenile();
  }

  @override
  Future<void> ihlalKaydet(String aciklama, DateTime ogrenilme, {int? etkilenen}) async {
    await api.post('/veri-ihlalleri', {
      'aciklama': aciklama.trim(),
      'ogrenilme': ogrenilme.toUtc().toIso8601String(),
      if (etkilenen != null) 'etkilenenKisiSayisi': etkilenen,
    });
    await _uyumYenile();
  }

  @override
  Future<void> ihlalBildirim(String ihlalId, String hedef) async {
    await api.post('/veri-ihlalleri/$ihlalId/bildirim', {'hedef': hedef});
    await _uyumYenile();
  }
}
