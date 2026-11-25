import '../hesaplama/para.dart';
import '../takvim/tarih.dart';
import 'sozlesme_tarayici.dart';

enum SozlesmeTuru {
  hizmet('Hizmet'),
  satis('Satış / tedarik'),
  kira('Kira'),
  gizlilik('Gizlilik'),
  isSozlesmesi('İş'),
  lisans('Lisans / yazılım'),
  distributorluk('Distribütörlük / bayilik'),
  diger('Diğer');

  const SozlesmeTuru(this.ad);
  final String ad;
}

enum SozlesmeDurumu {
  taslak('Taslak'),
  muzakere('Müzakere'),
  onayda('Onayda'),
  imzada('İmzada'),
  yururlukte('Yürürlükte'),
  sonaErdi('Sona erdi'),
  feshedildi('Feshedildi');

  const SozlesmeDurumu(this.ad);
  final String ad;

  /// İzin verilen durum geçişleri. Geri dönüşler (ör. onaydan müzakereye) bilinçli olarak serbest.
  static const gecisler = <SozlesmeDurumu, Set<SozlesmeDurumu>>{
    taslak: {muzakere, onayda},
    muzakere: {taslak, onayda},
    onayda: {muzakere, imzada},
    imzada: {onayda, yururlukte},
    yururlukte: {sonaErdi, feshedildi},
    sonaErdi: {},
    feshedildi: {},
  };

  bool gecebilir(SozlesmeDurumu hedef) => gecisler[this]!.contains(hedef);
}

enum YukumlulukTarafi { biz, karsiTaraf }

class Yukumluluk {
  const Yukumluluk({
    required this.id,
    required this.aciklama,
    required this.taraf,
    required this.sonTarih,
    this.sorumlu = '',
    this.tamamlandi = false,
  });

  final String id;
  final String aciklama;
  final YukumlulukTarafi taraf;
  final Tarih sonTarih;
  final String sorumlu;
  final bool tamamlandi;

  Yukumluluk tamamla() => Yukumluluk(
      id: id, aciklama: aciklama, taraf: taraf, sonTarih: sonTarih, sorumlu: sorumlu, tamamlandi: true);
}

enum SozlesmeUyariTuru { ihbarYaklasiyor, ihbarKacti, bitisYaklasiyor, yukumlulukYaklasiyor, yukumlulukGecikti }

class SozlesmeUyarisi {
  const SozlesmeUyarisi(this.tur, this.tarih, this.mesaj);
  final SozlesmeUyariTuru tur;
  final Tarih tarih;
  final String mesaj;
}

class Sozlesme {
  Sozlesme({
    required this.id,
    required this.no,
    required this.baslik,
    required this.tur,
    required this.karsiTaraf,
    required this.sorumlu,
    this.birim = '',
    this.durum = SozlesmeDurumu.taslak,
    this.baslangic,
    this.bitis,
    this.otomatikYenileme = false,
    this.yenilemeSuresiAy = 12,
    this.ihbarSuresiGun,
    this.bedel,
    this.belgeId,
    this.tarama,
    List<Yukumluluk>? yukumlulukler,
  }) : yukumlulukler = yukumlulukler ?? [];

  final String id;
  final String no;
  String baslik;
  SozlesmeTuru tur;
  String karsiTaraf;
  String sorumlu;
  String birim;
  SozlesmeDurumu durum;
  Tarih? baslangic;
  Tarih? bitis;
  bool otomatikYenileme;
  int yenilemeSuresiAy;
  int? ihbarSuresiGun;
  Para? bedel;
  String? belgeId;
  TaramaSonucu? tarama;
  final List<Yukumluluk> yukumlulukler;

  /// Yenilemeyi durdurmak veya feshi bildirmek için son gün (bitişten ihbar süresi kadar önce).
  Tarih? get ihbarSonGunu {
    final b = bitis;
    final i = ihbarSuresiGun;
    if (b == null || i == null) return null;
    return b.gunEkle(-i);
  }

  void durumDegistir(SozlesmeDurumu hedef) {
    if (!durum.gecebilir(hedef)) {
      throw StateError('${durum.ad} durumundan ${hedef.ad} durumuna geçilemez.');
    }
    if (hedef == SozlesmeDurumu.yururlukte && baslangic == null) {
      throw StateError('Yürürlüğe almak için başlangıç tarihi girilmelidir.');
    }
    durum = hedef;
  }

  /// Otomatik yenilenen sözleşmede ihbar günü geçtiyse bitiş bir dönem uzar (gece işi).
  bool kendiligindenUzat(Tarih bugun) {
    final mevcut = bitis;
    if (!otomatikYenileme || durum != SozlesmeDurumu.yururlukte || mevcut == null || yenilemeSuresiAy < 1) {
      return false;
    }
    var b = mevcut;
    var uzadi = false;
    while (bugun.isAfter(b)) {
      b = b.ayEkle(yenilemeSuresiAy);
      uzadi = true;
    }
    bitis = b;
    return uzadi;
  }

  /// [ufukGun] içindeki uyarılar. İhbar uyarısı yalnızca yürürlükteki sözleşmeler için üretilir.
  List<SozlesmeUyarisi> uyarilar(Tarih bugun, {int ufukGun = 60}) {
    final sonuc = <SozlesmeUyarisi>[];
    final ufuk = bugun.gunEkle(ufukGun);
    if (durum == SozlesmeDurumu.yururlukte) {
      final ihbar = ihbarSonGunu;
      final b = bitis;
      if (ihbar != null && b != null && !bugun.isAfter(b)) {
        if (bugun.isAfter(ihbar)) {
          sonuc.add(SozlesmeUyarisi(
              SozlesmeUyariTuru.ihbarKacti,
              ihbar,
              otomatikYenileme
                  ? 'İhbar süresi kaçtı; sözleşme ${b.turkceBicim} sonrasında $yenilemeSuresiAy ay uzayacak.'
                  : 'İhbar süresi geçti.'));
        } else if (!ihbar.isAfter(ufuk)) {
          sonuc.add(SozlesmeUyarisi(SozlesmeUyariTuru.ihbarYaklasiyor, ihbar,
              'Yenilememe/fesih ihbarı için son gün ${ihbar.turkceBicim}.'));
        }
      } else if (b != null && !bugun.isAfter(b) && !b.isAfter(ufuk)) {
        sonuc.add(SozlesmeUyarisi(SozlesmeUyariTuru.bitisYaklasiyor, b, 'Sözleşme ${b.turkceBicim} tarihinde sona eriyor.'));
      }
    }
    for (final y in yukumlulukler.where((y) => !y.tamamlandi)) {
      if (bugun.isAfter(y.sonTarih)) {
        sonuc.add(SozlesmeUyarisi(SozlesmeUyariTuru.yukumlulukGecikti, y.sonTarih, 'Gecikti: ${y.aciklama}'));
      } else if (!y.sonTarih.isAfter(ufuk)) {
        sonuc.add(SozlesmeUyarisi(SozlesmeUyariTuru.yukumlulukYaklasiyor, y.sonTarih, y.aciklama));
      }
    }
    sonuc.sort((a, b) => a.tarih.compareTo(b.tarih));
    return sonuc;
  }

  /// Tarama sonucundaki alanları boş olan alanlara uygular; kullanıcının girdiği değerin üstüne yazmaz.
  void taramayiUygula(TaramaSonucu t) {
    tarama = t;
    baslangic ??= t.baslangic;
    bitis ??= t.bitis ?? (t.baslangic != null && t.sureAy != null ? t.baslangic!.ayEkle(t.sureAy!).gunEkle(-1) : null);
    ihbarSuresiGun ??= t.ihbarSuresiGun;
    bedel ??= t.bedel;
    if (t.otomatikYenileme) otomatikYenileme = true;
    if (tur == SozlesmeTuru.diger && t.tur != null) tur = t.tur!;
  }
}
