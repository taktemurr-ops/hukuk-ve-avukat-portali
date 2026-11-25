import 'package:flutter/foundation.dart';
import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

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
    final hizmet = k.sozlesmeYukle(
        baslik: 'BT destek hizmet sözleşmesi', karsiTaraf: 'Delta Bilişim Hizmetleri Ltd. Şti.',
        birim: 'Bilgi Teknolojileri', metin: ornekHizmetSozlesmesi, kaydet: false);
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
        birim: 'İdari İşler', metin: ornekKiraSozlesmesi, kaydet: false);
    kira.durum = SozlesmeDurumu.yururlukte;
    k.sozlesmeYukle(
        baslik: 'İhracat görüşmeleri gizlilik sözleşmesi', karsiTaraf: 'Northwind Trading Limited',
        birim: 'Dış Ticaret', metin: ornekGizlilikSozlesmesi, kaydet: false)
      ..durum = SozlesmeDurumu.onayda;

    final eski = b.gunEkle(-6);
    final t1 = k.defter.olustur(
        baslik: 'Northwind gizlilik sözleşmesi incelemesi', aciklama: 'İngiliz hukuku seçilmiş, görüşünüzü rica ederiz.',
        tur: TalepTuru.sozlesmeInceleme, oncelik: Oncelik.yuksek, talepEden: 'Dış Ticaret / Burak Y.', birim: 'Dış Ticaret',
        bugun: eski);
    t1.sozlesmeId = k.sozlesmeler[2].id;
    k.defter.olustur(
        baslik: 'Bayi alacağı için ihtarname', aciklama: 'Ege bölge bayisinin 3 faturası vadesinde ödenmedi.',
        tur: TalepTuru.ihtarname, oncelik: Oncelik.normal, talepEden: 'Finans / Deniz K.', birim: 'Finans',
        bugun: b.gunEkle(-1));
    k.defter.olustur(
        baslik: 'Müşteri veri silme başvurusu', aciklama: 'KVKK m.11 kapsamında başvuru; m.13 uyarınca en geç 30 gün içinde yanıtlanmalı.',
        tur: TalepTuru.kvkk, oncelik: Oncelik.acil, talepEden: 'Müşteri Hizmetleri / Selin A.', birim: 'Müşteri Hizmetleri',
        bugun: b);
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
        bugun: b, otomatikAta: false);
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

  String kisiAdi(String id) {
    if (id.isEmpty) return '(atanmamış)';
    if (id == kullaniciId) return 'Siz';
    return hukukEkibi[id] ?? depo.kullaniciAdi(id);
  }

  List<String> get ekip => [kullaniciId, ...hukukEkibi.keys];

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
      for (final s in sozlesmeler)
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
