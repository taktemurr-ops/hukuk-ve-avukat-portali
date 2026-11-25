import '../dosya/dosya.dart';
import '../dosya/gorev.dart';
import '../finans/finans.dart';
import '../hesaplama/para.dart';
import '../sozlesme/sozlesme.dart';
import '../sozlesme/sozlesme_tarayici.dart';
import '../sozlesme/talep.dart';
import '../sure/sure_takibi.dart';
import '../takvim/tarih.dart';

/// Kişi başı iş yükü.
class IsYukuSatiri {
  IsYukuSatiri(this.kullanici);

  final String kullanici;
  int acikDosya = 0;
  int acikSure = 0;
  int kritikSure = 0;
  int teyitBekleyen = 0;
  int acikGorev = 0;
  int gecikenGorev = 0;
  int acikTalep = 0;

  /// Sıralama için kaba yük puanı: kritik süre ve geciken iş ağır basar.
  int get yukPuani => acikDosya + acikSure * 2 + kritikSure * 5 + acikGorev + gecikenGorev * 4 + acikTalep * 2;
}

/// Kalan güne göre açık süre dağılımı.
class SureDagilimi {
  int kacan = 0;
  int bugunYarin = 0;
  int buHafta = 0;
  int buAy = 0;
  int sonra = 0;
  int teyitBekleyen = 0;
  int sahipsiz = 0;

  int get toplam => kacan + bugunYarin + buHafta + buAy + sonra;
}

/// Müvekkil bazında vekâlet ücreti alacağı yaşlandırması (ilk giren ilk çıkar) ve büronun yaptığı masraf alacağı.
class AlacakYaslandirma {
  AlacakYaslandirma(this.muvekkilId);

  static const kovaAdlari = ['0–30 gün', '31–60 gün', '61–90 gün', '90+ gün'];

  final String muvekkilId;
  final List<Para> kovalar = List.filled(4, Para.sifir);
  Para masrafAlacagi = Para.sifir;

  Para get ucretAlacagi => kovalar.fold(Para.sifir, (a, b) => a + b);
  Para get toplam => ucretAlacagi + masrafAlacagi;
  bool get geciken => kovalar[2].kurus > 0 || kovalar[3].kurus > 0;
}

class TalepPerformansi {
  int acik = 0;
  int kapanan = 0;
  int zamanindaKapanan = 0;
  int geciken = 0;
  int toplamCozumIsGunu = 0;
  final Map<TalepTuru, int> acikTurlere = {};

  /// Kapanan taleplerde SLA'ya uyum oranı (%); kapanan yoksa null.
  int? get slaUyumu => kapanan == 0 ? null : (zamanindaKapanan * 100 / kapanan).round();
  double? get ortalamaCozum => kapanan == 0 ? null : toplamCozumIsGunu / kapanan;
}

class SozlesmeOzeti {
  final Map<RiskSeviyesi, int> risk = {for (final r in RiskSeviyesi.values) r: 0};
  final Map<SozlesmeDurumu, int> durum = {for (final d in SozlesmeDurumu.values) d: 0};
  int taranmamis = 0;

  /// Önümüzdeki 12 ayda biten yürürlükteki sözleşmeler: "2027-03" → adet.
  final Map<String, int> bitisAylari = {};
}

class Raporlar {
  Raporlar._();

  static List<IsYukuSatiri> isYuku({
    required Iterable<Dosya> dosyalar,
    required Iterable<SureKaydi> sureler,
    required Iterable<Gorev> gorevler,
    Iterable<HukukTalebi> talepler = const [],
    required Tarih bugun,
  }) {
    final satirlar = <String, IsYukuSatiri>{};
    IsYukuSatiri s(String k) => satirlar.putIfAbsent(k, () => IsYukuSatiri(k));
    for (final d in dosyalar.where((d) => d.acik)) {
      s(d.sorumlu).acikDosya++;
    }
    for (final x in sureler.where((x) => x.acik && !x.sahipsiz)) {
      final satir = s(x.asilSorumlu)..acikSure++;
      if (bugun.farkGun(x.sonGun) <= 7) satir.kritikSure++;
      if (x.durum == SureDurumu.teyitBekliyor) satir.teyitBekleyen++;
    }
    for (final g in gorevler.where((g) => g.durum == GorevDurumu.acik && g.atanan.isNotEmpty)) {
      final satir = s(g.atanan)..acikGorev++;
      final son = g.sonTarih;
      if (son != null && bugun.isAfter(son)) satir.gecikenGorev++;
    }
    for (final t in talepler.where((t) => !t.durum.kapali && t.atanan.isNotEmpty)) {
      s(t.atanan).acikTalep++;
    }
    return satirlar.values.toList()..sort((a, b) => b.yukPuani.compareTo(a.yukPuani));
  }

  static SureDagilimi sureDagilimi(Iterable<SureKaydi> sureler, Tarih bugun) {
    final d = SureDagilimi();
    for (final x in sureler.where((x) => x.acik)) {
      final kalan = bugun.farkGun(x.sonGun);
      if (kalan < 0) {
        d.kacan++;
      } else if (kalan <= 1) {
        d.bugunYarin++;
      } else if (kalan <= 7) {
        d.buHafta++;
      } else if (kalan <= 30) {
        d.buAy++;
      } else {
        d.sonra++;
      }
      if (x.durum == SureDurumu.teyitBekliyor) d.teyitBekleyen++;
      if (x.sahipsiz) d.sahipsiz++;
    }
    return d;
  }

  /// Tahsilatlar en eski tahakkuktan düşülür; kalan tahakkuklar yaşına göre kovalara ayrılır.
  static List<AlacakYaslandirma> alacakYaslandirma(Iterable<CariHareket> hareketler, Tarih bugun) {
    final muvekkilBazli = <String, List<CariHareket>>{};
    for (final h in hareketler) {
      muvekkilBazli.putIfAbsent(h.muvekkilId, () => []).add(h);
    }
    final sonuc = <AlacakYaslandirma>[];
    for (final e in muvekkilBazli.entries) {
      final liste = [...e.value]..sort((a, b) => a.tarih.compareTo(b.tarih));
      final acikTahakkuklar = <(Tarih, int)>[];
      var tahsilat = 0;
      for (final h in liste) {
        if (h.tur == CariHareketTuru.ucretTahakkuku) acikTahakkuklar.add((h.tarih, h.tutar.kurus));
        if (h.tur == CariHareketTuru.ucretTahsilati) tahsilat += h.tutar.kurus;
      }
      final y = AlacakYaslandirma(e.key);
      for (final (tarih, tutar) in acikTahakkuklar) {
        final dusulen = tahsilat >= tutar ? tutar : tahsilat;
        tahsilat -= dusulen;
        final kalan = tutar - dusulen;
        if (kalan == 0) continue;
        final yas = tarih.farkGun(bugun);
        final kova = yas <= 30 ? 0 : yas <= 60 ? 1 : yas <= 90 ? 2 : 3;
        y.kovalar[kova] = y.kovalar[kova] + Para.kurus(kalan);
      }
      final avans = CariOzet(liste).avansBakiyesi;
      if (avans.negatif) y.masrafAlacagi = -avans;
      if (y.toplam.kurus > 0) sonuc.add(y);
    }
    return sonuc..sort((a, b) => b.toplam.kurus.compareTo(a.toplam.kurus));
  }

  static TalepPerformansi talepPerformansi(Iterable<HukukTalebi> talepler, Tarih bugun, IsGunuHesabi hesap) {
    final p = TalepPerformansi();
    for (final t in talepler) {
      if (t.durum.kapali) {
        p.kapanan++;
        final kapanis = t.kapanis ?? bugun;
        if (!kapanis.isAfter(t.slaSonGun)) p.zamanindaKapanan++;
        p.toplamCozumIsGunu += hesap.arasinda(t.olusturma, kapanis);
      } else {
        p.acik++;
        p.acikTurlere[t.tur] = (p.acikTurlere[t.tur] ?? 0) + 1;
        if (t.slaDurumu(bugun, hesap) == SlaDurumu.gecikti) p.geciken++;
      }
    }
    return p;
  }

  static SozlesmeOzeti sozlesmeOzeti(Iterable<Sozlesme> sozlesmeler, Tarih bugun) {
    final o = SozlesmeOzeti();
    final ufuk = bugun.ayEkle(12);
    for (final s in sozlesmeler) {
      o.durum[s.durum] = o.durum[s.durum]! + 1;
      final t = s.tarama;
      if (t == null) {
        o.taranmamis++;
      } else {
        o.risk[t.genelSeviye] = o.risk[t.genelSeviye]! + 1;
      }
      final b = s.bitis;
      if (s.durum == SozlesmeDurumu.yururlukte && b != null && !b.isBefore(bugun) && !b.isAfter(ufuk)) {
        final anahtar = '${b.yil}-${b.ay.toString().padLeft(2, '0')}';
        o.bitisAylari[anahtar] = (o.bitisAylari[anahtar] ?? 0) + 1;
      }
    }
    return o;
  }

  /// Basit CSV (noktalı virgül ayraçlı; Türkçe Excel uyumlu).
  static String csv(List<String> basliklar, Iterable<List<Object?>> satirlar) {
    String hucre(Object? v) {
      final s = v?.toString() ?? '';
      return RegExp(r'[;"\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    return [basliklar, ...satirlar].map((r) => r.map(hucre).join(';')).join('\n');
  }
}
