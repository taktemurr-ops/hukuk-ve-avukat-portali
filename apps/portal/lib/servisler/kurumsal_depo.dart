import 'package:flutter/foundation.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import 'kurumsal_senkronu.dart';
import 'ornek_sozlesmeler.dart';
import 'veri_deposu.dart';

/// Kurumsal hesabın sözleşme ve hukuk talebi verileri (bellekte; sunucu gelince aynı yüzeyle değişecek).
class KurumsalDepo extends ChangeNotifier {
  KurumsalDepo({required this.depo, required this.kullaniciId, Tarih Function()? bugun})
      : _bugun = bugun ?? (() => Tarih.from(DateTime.now())),
        hesap = IsGunuHesabi(TurkiyeTatilleri.takvim(TurkiyeTatilleri.diniBayramVerisiOlanYillar)) {
    defter = TalepDefteri(
      hesap: hesap,
      yonlendirici: TalepYonlendirici({
        TalepTuru.sozlesmeInceleme: [kullaniciId, 'hu2'],
        TalepTuru.sozlesmeHazirlama: [kullaniciId, 'hu2'],
        TalepTuru.uyusmazlik: [kullaniciId],
        TalepTuru.ihtarname: ['hu2'],
        TalepTuru.kvkk: ['hu3'],
        TalepTuru.diger: ['hu3', 'hu2'],
      }),
      yil: bugunTarih.yil,
    );
  }

  /// Demo verisi: üç sözleşme ve dört talep.
  factory KurumsalDepo.demo({required BellekVeriDeposu depo, required String kullaniciId, Tarih Function()? bugun}) {
    final k = KurumsalDepo(depo: depo, kullaniciId: kullaniciId, bugun: bugun);
    final b = k.bugunTarih;
    k.grup = GrupYapisi(const [
      Sirket(id: 'abcHolding', unvan: 'ABC Holding A.Ş.', kisaAd: 'ABC Holding', vkn: '1111111114'),
      Sirket(id: 'abcGida', unvan: 'ABC Gıda Sanayi ve Ticaret A.Ş.', kisaAd: 'ABC Gıda', vkn: '1234567890', anaSirketId: 'abcHolding'),
      Sirket(id: 'abcLojistik', unvan: 'ABC Lojistik A.Ş.', kisaAd: 'ABC Lojistik', anaSirketId: 'abcGida'),
      Sirket(id: 'abcDis', unvan: 'ABC Dış Ticaret A.Ş.', kisaAd: 'ABC Dış Ticaret', anaSirketId: 'abcHolding'),
    ]);
    final hizmet = k.sozlesmeYukle(
        baslik: 'BT destek hizmet sözleşmesi', karsiTaraf: 'Delta Bilişim Hizmetleri Ltd. Şti.',
        birim: 'Bilgi Teknolojileri', metin: ornekHizmetSozlesmesi, kaydet: false, sirketId: 'abcGida');
    hizmet
      ..baslangic = b.ayEkle(-11)
      ..bitis = b.ayEkle(3)
      ..durum = SozlesmeDurumu.yururlukte
      ..yukumlulukler.add(Yukumluluk(
          id: 'y1',
          aciklama: 'Yıllık hizmet seviyesi raporu teslimi',
          taraf: YukumlulukTarafi.karsiTaraf,
          sonTarih: b.gunEkle(12),
          sorumlu: 'hu2'));
    final kira = k.sozlesmeYukle(
        baslik: 'Genel müdürlük işyeri kirası', karsiTaraf: 'Orman Gayrimenkul Yatırım A.Ş.',
        birim: 'İdari İşler', metin: ornekKiraSozlesmesi, kaydet: false, sirketId: 'abcHolding');
    kira.durum = SozlesmeDurumu.yururlukte;
    k.sozlesmeYukle(
        baslik: 'İhracat görüşmeleri gizlilik sözleşmesi', karsiTaraf: 'Northwind Trading Limited',
        birim: 'Dış Ticaret', metin: ornekGizlilikSozlesmesi, kaydet: false, sirketId: 'abcDis')
      ..durum = SozlesmeDurumu.onayda;

    final nda = k.sozlesmeler[2];
    k.onaySurecleri[nda.id] = OnaySureci(sozlesmeId: nda.id, adimlar: k.onayPolitikasi.adimlar(nda), baslatan: 'hu2')
      ..karar('hu2', OnayKarariTuru.onay, DateTime.now().subtract(const Duration(days: 1)));

    final simdi = DateTime.now();
    final ih1 = k.ihbarKaydet(
      kanal: IhbarKanali.web,
      kategori: IhbarKategorisi.rusvetYolsuzluk,
      aciklama: 'Lojistik satın alma biriminde bir tedarikçiden değerli hediye alındığı ve ihalenin yönlendirildiği iddiası.',
      ilgiliKisiler: {'hu3'},
      zaman: simdi.subtract(const Duration(days: 9)),
    );
    k.sorusturmaAc(ih1, kullaniciId, zaman: simdi.subtract(const Duration(days: 8)));
    k.sorusturmalar.first
      ..ekipEkle('hu2', ekleyen: kullaniciId)
      ..geriBildirimVer(kullaniciId, simdi.subtract(const Duration(days: 6)))
      ..sorusturmayaAl(kullaniciId)
      ..notEkle('hu2', 'Son iki yılın satın alma ve fatura kayıtları istendi.', simdi.subtract(const Duration(days: 5)));
    final ih2 = k.ihbarKaydet(
      kanal: IhbarKanali.eposta,
      kategori: IhbarKategorisi.tacizMobbing,
      aciklama: 'Depo vardiya amirinin ekibine sürekli bağırdığı ve izinleri keyfi reddettiği bildirildi.',
      anonim: false,
      iletisim: 'çalışan e-postası (gizli)',
      zaman: simdi.subtract(const Duration(days: 2)),
    );
    k.sorusturmaAc(ih2, 'hu2', zaman: simdi.subtract(const Duration(days: 2)));
    k.ihlalKaydet('Müşteri listesi içeren e-posta yanlışlıkla dış bir alıcıya gönderildi.',
        simdi.subtract(const Duration(hours: 30)), etkilenen: 340);

    final eski = b.gunEkle(-6);
    final t1 = k.defter.olustur(
        baslik: 'Northwind gizlilik sözleşmesi incelemesi', aciklama: 'İngiliz hukuku seçilmiş, görüşünüzü rica ederiz.',
        tur: TalepTuru.sozlesmeInceleme, oncelik: Oncelik.yuksek, talepEden: 'Dış Ticaret / Burak Y.', birim: 'Dış Ticaret',
        bugun: eski, sirketId: 'abcDis');
    t1.sozlesmeId = k.sozlesmeler[2].id;
    k.defter.olustur(
        baslik: 'Bayi alacağı için ihtarname', aciklama: 'Ege bölge bayisinin 3 faturası vadesinde ödenmedi.',
        tur: TalepTuru.ihtarname, oncelik: Oncelik.normal, talepEden: 'Finans / Deniz K.', birim: 'Finans',
        bugun: b.gunEkle(-1), sirketId: 'abcGida');
    k.defter.olustur(
        baslik: 'Müşteri veri silme başvurusu', aciklama: 'KVKK m.11 kapsamında başvuru; m.13 uyarınca en geç 30 gün içinde yanıtlanmalı.',
        tur: TalepTuru.kvkk, oncelik: Oncelik.acil, talepEden: 'Müşteri Hizmetleri / Selin A.', birim: 'Müşteri Hizmetleri',
        bugun: b, sirketId: 'abcGida');
    k.disAvukatlar.addAll(const [
      DisAvukat(
          id: 'da1',
          buro: 'Kaya Hukuk Bürosu',
          sorumluAvukat: 'Av. Deniz Kaya',
          eposta: 'deniz@kayahukuk.av.tr',
          uzmanliklar: ['İş hukuku', 'Ankara davaları']),
      DisAvukat(
          id: 'da2',
          buro: 'Ege Ortak Avukatlık',
          sorumluAvukat: 'Av. Selim Ege',
          eposta: 'selim@egeortak.av.tr',
          uzmanliklar: ['İcra', 'Ticari alacak']),
    ]);
    final is1 = k.disAvukatIsiAc(
        disAvukatId: 'da1', konu: 'Bölge müdürlüğü işe iade davaları', butce: Para.tl(150000), kaydet: false);
    is1
      ..faturaOnayla(
          is1.faturaEkle(
              id: 'df1', no: 'KH-2026-311', tarih: b.gunEkle(-40), tutar: Para.tl(72000), aciklama: 'Eylül hizmet bedeli'),
          kullaniciId)
      ..faturaOnayla(
          is1.faturaEkle(
              id: 'df2', no: 'KH-2026-352', tarih: b.gunEkle(-10), tutar: Para.tl(48000), aciklama: 'Ekim hizmet bedeli'),
          kullaniciId)
      ..faturaEkle(
          id: 'df3', no: 'KH-2026-377', tarih: b.gunEkle(-2), tutar: Para.tl(41000), aciklama: 'Kasım hizmet bedeli');
    final is2 = k.disAvukatIsiAc(disAvukatId: 'da2', konu: 'Bayi alacakları icra takipleri', butce: Para.tl(90000), kaydet: false);
    is2.faturaEkle(id: 'df4', no: 'EO-1188', tarih: b.gunEkle(-5), tutar: Para.tl(18500), aciklama: 'Takip açılış ve harç');

    k.defter.olustur(
        baslik: 'Yeni tedarikçi çerçeve sözleşmesi', aciklama: 'Ambalaj tedarikçisi için standart şablonla hazırlık.',
        tur: TalepTuru.sozlesmeHazirlama, oncelik: Oncelik.dusuk, talepEden: 'Satın Alma / Emre T.', birim: 'Satın Alma',
        bugun: b, otomatikAta: false, sirketId: 'abcLojistik');
    return k;
  }

  final BellekVeriDeposu depo;
  final String kullaniciId;
  final Tarih Function() _bugun;
  final IsGunuHesabi hesap;
  late final TalepDefteri defter;
  final SozlesmeTarayici tarayici = const SozlesmeTarayici();
  final List<Sozlesme> sozlesmeler = [];
  final Map<String, String> _metinler = {};
  int _sozlesmeSira = 0;
  int _yukumlulukSira = 0;

  Tarih get bugunTarih => _bugun();

  static const hukukEkibi = {'hu2': 'Av. Selin Arslan', 'hu3': 'Hukuk Uzm. Can Öz'};
  static const yoneticiler = {'fn1': 'Finans Md. Gül Ak', 'gm1': 'Genel Müdür Ali Er'};

  String kisiAdi(String id) {
    if (id.isEmpty) return '(atanmamış)';
    if (id == kullaniciId) return 'Siz';
    return hukukEkibi[id] ?? yoneticiler[id] ?? depo.kullaniciAdi(id);
  }

  // ---------------------------------------------------------------------------
  // Uyum: ihbar, iç soruşturma, veri ihlali
  // ---------------------------------------------------------------------------

  final List<Ihbar> ihbarlar = [];
  final List<Sorusturma> sorusturmalar = [];
  final List<VeriIhlali> veriIhlalleri = [];
  int _uyumSira = 0;

  String _uyumId(String onek) => '$onek${++_uyumSira}';

  Ihbar ihbarKaydet({
    required IhbarKanali kanal,
    required IhbarKategorisi kategori,
    required String aciklama,
    bool anonim = true,
    String? iletisim,
    Set<String> ilgiliKisiler = const {},
    DateTime? zaman,
  }) {
    if (aciklama.trim().length < 20) throw ArgumentError('İhbarı en az 20 karakterle açıklayın.');
    final i = Ihbar(
      id: _uyumId('ih'),
      takipKodu: Ihbar.takipKoduUret(),
      zaman: zaman ?? DateTime.now(),
      kanal: kanal,
      kategori: kategori,
      aciklama: aciklama.trim(),
      anonim: anonim,
      ihbarciIletisim: anonim ? null : iletisim,
      ilgiliKisiler: ilgiliKisiler,
      sirketId: aktifSirketId,
    );
    ihbarlar.add(i);
    // İçerik denetim kaydına yazılmaz; yalnızca kategori.
    depo.okumaKaydet(DenetimIslemi.olusturma, 'ihbar', i.id, i.kategori.ad);
    notifyListeners();
    return i;
  }

  Sorusturma? sorusturmaOf(String ihbarId) {
    for (final s in sorusturmalar) {
      if (s.ihbar.id == ihbarId) return s;
    }
    return null;
  }

  String? sorusturmaAc(Ihbar ihbar, String sorumlu, {DateTime? zaman}) {
    if (sorusturmaOf(ihbar.id) != null) return 'Bu ihbar için soruşturma zaten açık.';
    try {
      final s = Sorusturma(id: _uyumId('so'), ihbar: ihbar, sorumlu: sorumlu, acilis: zaman ?? DateTime.now());
      sorusturmalar.add(s);
      depo.okumaKaydet(DenetimIslemi.olusturma, 'sorusturma', s.id, 'Sorumlu: ${kisiAdi(sorumlu)}');
      notifyListeners();
      return null;
    } on StateError catch (e) {
      return e.message;
    }
  }

  String? uyumIslemi(String aciklama, String nesneId, void Function() islem) {
    try {
      islem();
      depo.okumaKaydet(DenetimIslemi.degisiklik, 'uyum', nesneId, aciklama);
      notifyListeners();
      return null;
    } on StateError catch (e) {
      return e.message;
    } on ArgumentError catch (e) {
      return '${e.message}';
    }
  }

  VeriIhlali ihlalKaydet(String aciklama, DateTime ogrenilme, {int? etkilenen}) {
    final v = VeriIhlali(id: _uyumId('vi'), ogrenilme: ogrenilme, aciklama: aciklama.trim(), etkilenenKisiSayisi: etkilenen);
    veriIhlalleri.add(v);
    depo.okumaKaydet(DenetimIslemi.olusturma, 'veri_ihlali', v.id, 'Öğrenilme ${ogrenilme.toIso8601String()}');
    notifyListeners();
    return v;
  }

  // ---------------------------------------------------------------------------
  // Grup şirketleri
  // ---------------------------------------------------------------------------

  GrupYapisi grup = GrupYapisi(const []);

  /// Seçili şirket (alt şirketleriyle); null ise tüm grup.
  String? aktifSirketId;

  Sirket? get aktifSirket => aktifSirketId == null ? null : grup.sirket(aktifSirketId!);

  bool kapsamda(String? sirketId) {
    final a = aktifSirketId;
    if (a == null) return true;
    return sirketId != null && grup.kapsam(a).contains(sirketId);
  }

  List<Sozlesme> get gorunurSozlesmeler => [for (final s in sozlesmeler) if (kapsamda(s.sirketId)) s];

  List<HukukTalebi> get gorunurTalepler => [for (final t in defter.talepler) if (kapsamda(t.sirketId)) t];

  String sirketAdi(String? id) => id == null ? '—' : grup.sirket(id)?.gorunenAd ?? id;

  void sirketSec(String? id) {
    aktifSirketId = id;
    notifyListeners();
  }

  /// Hata varsa mesajı döner.
  String? sirketEkle({required String unvan, String? vkn, String? anaSirketId, String? kisaAd}) {
    if (unvan.trim().length < 3) return 'Unvan zorunludur.';
    final v = vkn?.trim();
    if (v != null && v.isNotEmpty && !Dogrulayicilar.vknGecerli(v)) return 'Vergi kimlik numarası geçersiz.';
    try {
      final id = 'sirket${grup.tumu.length + 1}';
      grup = grup.ekle(Sirket(
        id: id,
        unvan: unvan.trim(),
        vkn: v == null || v.isEmpty ? null : v,
        anaSirketId: anaSirketId,
        kisaAd: kisaAd == null || kisaAd.trim().isEmpty ? null : kisaAd.trim(),
      ));
      depo.okumaKaydet(DenetimIslemi.olusturma, 'sirket', id, unvan.trim());
      notifyListeners();
      return null;
    } on ArgumentError catch (e) {
      return '${e.message}';
    }
  }

  // ---------------------------------------------------------------------------
  // Sözleşme onay zinciri
  // ---------------------------------------------------------------------------

  late final OnayPolitikasi onayPolitikasi = OnayPolitikasi(
    hukukEkibi: hukukEkibi.keys.toSet(),
    hukukDirektoru: {kullaniciId},
    finans: const {'fn1'},
    genelMudur: const {'gm1'},
  );

  final Map<String, OnaySureci> onaySurecleri = {};

  OnaySureci? onaySureci(String sozlesmeId) => onaySurecleri[sozlesmeId];

  /// Taslak veya müzakeredeki sözleşmeyi politikaya göre oluşan onay zincirine gönderir.
  String? onayaGonder(Sozlesme s) {
    if (s.durum != SozlesmeDurumu.taslak && s.durum != SozlesmeDurumu.muzakere) {
      return 'Yalnızca taslak veya müzakeredeki sözleşme onaya gönderilir.';
    }
    final adimlar = onayPolitikasi.adimlar(s);
    onaySurecleri[s.id] = OnaySureci(sozlesmeId: s.id, adimlar: adimlar, baslatan: kullaniciId);
    s.durumDegistir(SozlesmeDurumu.onayda);
    depo.okumaKaydet(DenetimIslemi.degisiklik, 'sozlesme', s.id, 'Onaya gönderildi: ${adimlar.map((a) => a.ad).join(' → ')}');
    notifyListeners();
    return null;
  }

  /// Onay tamamlanınca sözleşme imzaya geçer; ret veya revizyonda müzakereye döner.
  String? onayKarari(Sozlesme s, OnayKarariTuru tur, {String not = ''}) {
    final p = onaySurecleri[s.id];
    if (p == null) return 'Onay süreci yok.';
    try {
      p.karar(kullaniciId, tur, DateTime.now(), not: not);
    } on StateError catch (e) {
      return e.message;
    } on ArgumentError catch (e) {
      return '${e.message}';
    }
    switch (p.durum) {
      case OnaySurecDurumu.onaylandi:
        s.durumDegistir(SozlesmeDurumu.imzada);
      case OnaySurecDurumu.reddedildi || OnaySurecDurumu.revizyon:
        s.durumDegistir(SozlesmeDurumu.muzakere);
      case OnaySurecDurumu.devam:
        break;
    }
    depo.okumaKaydet(DenetimIslemi.kararKaydi, 'sozlesme', s.id, '${tur.ad}${not.isEmpty ? '' : ': $not'}');
    notifyListeners();
    return null;
  }

  List<Sozlesme> get onayimiBekleyenler =>
      [for (final s in sozlesmeler) if (onaySurecleri[s.id]?.onaylayabilir(kullaniciId) ?? false) s];

  List<String> get ekip => _sunucuEkibi ?? [kullaniciId, ...hukukEkibi.keys];

  // ---------------------------------------------------------------------------
  // Sunucu bağlantısı
  // ---------------------------------------------------------------------------

  /// Sunucuya bağlıyken şirket, sözleşme ve talep işlemleri bu kancadan geçer (sunucu tek doğru kaynaktır).
  KurumsalUzak? uzak;
  List<String>? _sunucuEkibi;

  /// Sunucudan gelen veriyle önbelleği değiştirir.
  void sunucuVerisiniYukle({
    required List<Sirket> sirketler,
    required List<Sozlesme> sozlesmeListesi,
    required List<HukukTalebi> talepler,
    required Map<String, OnaySureci> surecler,
    required List<String> ekip,
  }) {
    grup = GrupYapisi(sirketler);
    if (aktifSirketId != null && grup.sirket(aktifSirketId!) == null) aktifSirketId = null;
    sozlesmeler
      ..clear()
      ..addAll(sozlesmeListesi);
    defter.talepler
      ..clear()
      ..addAll(talepler);
    onaySurecleri
      ..clear()
      ..addAll(surecler);
    _sunucuEkibi = ekip;
    notifyListeners();
  }

  /// Sunucu bağlıyken işlemi sunucuda, değilse yerelde yapar. Hata varsa kullanıcıya gösterilecek mesajı döner.
  Future<String?> sunucudaVeyaYerelde({
    required Future<void> Function(KurumsalUzak uzak) sunucuda,
    required String? Function() yerelde,
  }) async {
    final u = uzak;
    if (u == null) {
      try {
        return yerelde();
      } on StateError catch (e) {
        return e.message;
      } on ArgumentError catch (e) {
        return '${e.message}';
      }
    }
    try {
      await sunucuda(u);
      return null;
    } on Exception catch (e) {
      return '$e';
    }
  }

  String? metin(String sozlesmeId) => _metinler[sozlesmeId];

  Sozlesme? sozlesme(String id) {
    for (final s in sozlesmeler) {
      if (s.id == id) return s;
    }
    return null;
  }

  TaramaSonucu tara(String metin) => tarayici.tara(metin);

  /// Metni tarar, bulunan alanları uygular ve sözleşmeyi taslak olarak kaydeder.
  Sozlesme sozlesmeYukle({
    required String baslik,
    required String karsiTaraf,
    required String metin,
    String birim = '',
    SozlesmeTuru? tur,
    bool kaydet = true,
    String? sirketId,
  }) {
    if (baslik.trim().isEmpty) throw ArgumentError('Sözleşme başlığı zorunludur.');
    _sozlesmeSira++;
    final s = Sozlesme(
      id: 'sz$_sozlesmeSira',
      no: 'SZ-${bugunTarih.yil}-${_sozlesmeSira.toString().padLeft(4, '0')}',
      baslik: baslik.trim(),
      tur: tur ?? SozlesmeTuru.diger,
      karsiTaraf: karsiTaraf.trim(),
      sorumlu: kullaniciId,
      birim: birim.trim(),
      sirketId: sirketId ?? aktifSirketId,
    );
    if (metin.trim().isNotEmpty) {
      s.taramayiUygula(tara(metin));
      _metinler[s.id] = metin;
    }
    sozlesmeler.add(s);
    if (kaydet) {
      depo.okumaKaydet(DenetimIslemi.olusturma, 'sozlesme', s.id,
          '${s.no} · ${s.baslik} · risk ${s.tarama?.riskPuani ?? 0}');
      notifyListeners();
    }
    return s;
  }

  void sozlesmeDurumu(Sozlesme s, SozlesmeDurumu hedef) {
    s.durumDegistir(hedef);
    depo.okumaKaydet(DenetimIslemi.degisiklik, 'sozlesme', s.id, 'Durum: ${hedef.ad}');
    notifyListeners();
  }

  void yukumlulukEkle(Sozlesme s, String aciklama, YukumlulukTarafi taraf, Tarih sonTarih) {
    _yukumlulukSira++;
    s.yukumlulukler.add(Yukumluluk(
        id: 'yk$_yukumlulukSira', aciklama: aciklama.trim(), taraf: taraf, sonTarih: sonTarih, sorumlu: kullaniciId));
    depo.okumaKaydet(DenetimIslemi.olusturma, 'yukumluluk', s.id, aciklama);
    notifyListeners();
  }

  void yukumlulukTamamla(Sozlesme s, Yukumluluk y) {
    final i = s.yukumlulukler.indexOf(y);
    if (i < 0) return;
    s.yukumlulukler[i] = y.tamamla();
    depo.okumaKaydet(DenetimIslemi.degisiklik, 'yukumluluk', s.id, 'Tamamlandı: ${y.aciklama}');
    notifyListeners();
  }

  /// Tüm sözleşmelerin uyarıları, tarihe göre.
  List<(Sozlesme, SozlesmeUyarisi)> uyarilar({int ufukGun = 60}) {
    final l = [
      for (final s in gorunurSozlesmeler)
        for (final u in s.uyarilar(bugunTarih, ufukGun: ufukGun)) (s, u),
    ]..sort((a, b) => a.$2.tarih.compareTo(b.$2.tarih));
    return l;
  }

  HukukTalebi talepOlustur({
    required String baslik,
    required String aciklama,
    required TalepTuru tur,
    required Oncelik oncelik,
    required String birim,
    String? talepEden,
    String? sozlesmeId,
    String? sirketId,
  }) {
    final t = defter.olustur(
      baslik: baslik,
      aciklama: aciklama,
      tur: tur,
      oncelik: oncelik,
      talepEden: talepEden ?? kisiAdi(kullaniciId),
      birim: birim,
      bugun: bugunTarih,
      sozlesmeId: sozlesmeId,
      sirketId: sirketId ?? aktifSirketId,
    );
    depo.okumaKaydet(DenetimIslemi.olusturma, 'talep', t.id, '${t.no} · ${t.baslik}');
    notifyListeners();
    return t;
  }

  void talepDurumu(HukukTalebi t, TalepDurumu hedef, {String not = ''}) {
    t.durumDegistir(hedef, kullanici: kullaniciId, bugun: bugunTarih, hesap: hesap, not: not);
    depo.okumaKaydet(DenetimIslemi.degisiklik, 'talep', t.id, '${hedef.ad}${not.isEmpty ? '' : ': $not'}');
    notifyListeners();
  }

  void talepAta(HukukTalebi t, String kisi) {
    t.atanan = kisi;
    if (t.durum == TalepDurumu.yeni) {
      t.durumDegistir(TalepDurumu.atandi, kullanici: kullaniciId, bugun: bugunTarih, hesap: hesap, not: kisiAdi(kisi));
    } else {
      t.gecmis.add(TalepOlayi(bugunTarih, kullaniciId, 'Yeniden atandı: ${kisiAdi(kisi)}'));
    }
    depo.okumaKaydet(DenetimIslemi.degisiklik, 'talep', t.id, 'Atandı: ${kisiAdi(kisi)}');
    notifyListeners();
  }

  SlaDurumu sla(HukukTalebi t) => t.slaDurumu(bugunTarih, hesap);

  // ---------------------------------------------------------------------------
  // Dış avukat yönetimi
  // ---------------------------------------------------------------------------

  final List<DisAvukat> disAvukatlar = [];
  final List<DisAvukatIsi> disAvukatIsleri = [];
  int _disSira = 0;

  DisAvukat? disAvukat(String id) {
    for (final a in disAvukatlar) {
      if (a.id == id) return a;
    }
    return null;
  }

  DisAvukatIsi? disAvukatIsi(String id) {
    for (final i in disAvukatIsleri) {
      if (i.id == id) return i;
    }
    return null;
  }

  DisAvukatIsi disAvukatIsiAc({
    required String disAvukatId,
    required String konu,
    required Para butce,
    String? talepId,
    bool kaydet = true,
  }) {
    if (konu.trim().isEmpty) throw ArgumentError('Konu zorunludur.');
    if (butce.kurus <= 0) throw ArgumentError('Bütçe sıfırdan büyük olmalı.');
    _disSira++;
    final i = DisAvukatIsi(
        id: 'dis$_disSira', disAvukatId: disAvukatId, konu: konu.trim(), ilkButce: butce, baslangic: bugunTarih, talepId: talepId);
    disAvukatIsleri.add(i);
    if (kaydet) {
      depo.okumaKaydet(DenetimIslemi.olusturma, 'dis_avukat_isi', i.id, '${disAvukat(disAvukatId)?.buro} · ${butce.bicimli}');
      notifyListeners();
    }
    return i;
  }

  /// İşlem sonucu hata mesajı veya null.
  String? disAvukatIslemi(String aciklama, String nesneId, void Function() islem) {
    try {
      islem();
      depo.okumaKaydet(DenetimIslemi.degisiklik, 'dis_avukat_isi', nesneId, aciklama);
      notifyListeners();
      return null;
    } on StateError catch (e) {
      return e.message;
    } on ArgumentError catch (e) {
      return '${e.message}';
    }
  }

  List<DisAvukatOzeti> get disAvukatOzetleri => DisAvukatOzeti.hesapla(disAvukatlar, disAvukatIsleri);
}
