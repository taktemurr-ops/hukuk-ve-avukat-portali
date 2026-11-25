import '../hesaplama/para.dart';
import 'sozlesme.dart';
import 'sozlesme_tarayici.dart';

class OnayAdimi {
  const OnayAdimi({required this.kod, required this.ad, required this.onaycilar, required this.neden});

  final String kod;
  final String ad;

  /// Bu adımı onaylayabilecek kullanıcılardan biri yeterlidir.
  final Set<String> onaycilar;

  /// Adımın neden zincire girdiği (ör. "Bedel 1.000.000 TL üzerinde").
  final String neden;
}

/// Kurumun onay politikası: hangi koşulda hangi adım eklenir. Eşikler kurum ayarıdır (varsayılanlar taslak).
class OnayPolitikasi {
  const OnayPolitikasi({
    required this.hukukEkibi,
    required this.hukukDirektoru,
    required this.finans,
    required this.genelMudur,
    this.finansEsigi = const Para.kurus(100000000),
    this.genelMudurEsigi = const Para.kurus(500000000),
  });

  final Set<String> hukukEkibi;
  final Set<String> hukukDirektoru;
  final Set<String> finans;
  final Set<String> genelMudur;

  /// Varsayılan: 1.000.000 TL ve üzeri finans onayı.
  final Para finansEsigi;

  /// Varsayılan: 5.000.000 TL ve üzeri genel müdür onayı.
  final Para genelMudurEsigi;

  List<OnayAdimi> adimlar(Sozlesme s) {
    final l = <OnayAdimi>[
      OnayAdimi(kod: 'hukuk', ad: 'Hukuk incelemesi', onaycilar: hukukEkibi, neden: 'Her sözleşme'),
    ];
    final risk = s.tarama?.genelSeviye;
    if (risk == RiskSeviyesi.yuksek || s.tarama == null) {
      l.add(OnayAdimi(
          kod: 'direktor',
          ad: 'Hukuk direktörü',
          onaycilar: hukukDirektoru,
          neden: s.tarama == null ? 'Sözleşme taranmadı' : 'Otomatik taramada yüksek risk'));
    }
    final b = s.bedel;
    // Döviz bedellerinde eşik karşılaştırması yapılamaz; finans her zaman görür.
    if (b != null && (b.birim != 'TRY' || b >= finansEsigi)) {
      l.add(OnayAdimi(
          kod: 'finans',
          ad: 'Finans',
          onaycilar: finans,
          neden: b.birim != 'TRY' ? 'Döviz cinsinden bedel' : 'Bedel ${finansEsigi.bicimli} ve üzeri'));
    }
    if (b != null && b.birim == 'TRY' && b >= genelMudurEsigi) {
      l.add(OnayAdimi(kod: 'gm', ad: 'Genel müdür', onaycilar: genelMudur, neden: 'Bedel ${genelMudurEsigi.bicimli} ve üzeri'));
    }
    return l;
  }
}

enum OnayKarariTuru {
  onay('Onaylandı'),
  ret('Reddedildi'),
  revizyon('Revizyon istendi');

  const OnayKarariTuru(this.ad);
  final String ad;
}

class OnayKarari {
  const OnayKarari({required this.adimKodu, required this.kullanici, required this.tur, required this.not, required this.zaman});
  final String adimKodu;
  final String kullanici;
  final OnayKarariTuru tur;
  final String not;
  final DateTime zaman;
}

enum OnaySurecDurumu {
  devam('Onayda'),
  onaylandi('Onaylandı'),
  reddedildi('Reddedildi'),
  revizyon('Revizyon istendi');

  const OnaySurecDurumu(this.ad);
  final String ad;
}

/// Sıralı onay süreci. Aynı kişi iki adımı onaylayamaz; ret ve revizyon gerekçe ister ve süreci bitirir.
class OnaySureci {
  OnaySureci({required this.sozlesmeId, required this.adimlar, required this.baslatan});

  final String sozlesmeId;
  final List<OnayAdimi> adimlar;
  final String baslatan;
  final List<OnayKarari> kararlar = [];
  OnaySurecDurumu durum = OnaySurecDurumu.devam;

  int get _onaylananAdim => kararlar.where((k) => k.tur == OnayKarariTuru.onay).length;

  OnayAdimi? get siradaki => durum == OnaySurecDurumu.devam && _onaylananAdim < adimlar.length ? adimlar[_onaylananAdim] : null;

  bool onaylayabilir(String kullanici) {
    final a = siradaki;
    if (a == null || !a.onaycilar.contains(kullanici)) return false;
    return !kararlar.any((k) => k.kullanici == kullanici && k.tur == OnayKarariTuru.onay);
  }

  void karar(String kullanici, OnayKarariTuru tur, DateTime zaman, {String not = ''}) {
    final a = siradaki;
    if (a == null) throw StateError('Onay süreci tamamlanmış.');
    if (!a.onaycilar.contains(kullanici)) throw StateError('${a.ad} adımında onay yetkiniz yok.');
    if (kararlar.any((k) => k.kullanici == kullanici && k.tur == OnayKarariTuru.onay)) {
      throw StateError('Aynı kişi birden fazla adımı onaylayamaz.');
    }
    if (tur != OnayKarariTuru.onay && not.trim().length < 5) throw ArgumentError('${tur.ad} için gerekçe yazılmalı.');
    kararlar.add(OnayKarari(adimKodu: a.kod, kullanici: kullanici, tur: tur, not: not.trim(), zaman: zaman));
    durum = switch (tur) {
      OnayKarariTuru.ret => OnaySurecDurumu.reddedildi,
      OnayKarariTuru.revizyon => OnaySurecDurumu.revizyon,
      OnayKarariTuru.onay => _onaylananAdim == adimlar.length ? OnaySurecDurumu.onaylandi : OnaySurecDurumu.devam,
    };
  }
}
