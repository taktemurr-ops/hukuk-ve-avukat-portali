import '../takvim/tarih.dart';
import '../takvim/tatil_takvimi.dart';

/// Şirket içinden hukuk birimine gelen talep türleri ve varsayılan hizmet süreleri (iş günü).
enum TalepTuru {
  sozlesmeInceleme('Sözleşme inceleme', 3),
  sozlesmeHazirlama('Sözleşme hazırlama', 5),
  hukukiGorus('Hukuki görüş', 5),
  uyusmazlik('Uyuşmazlık / dava', 2),
  ihtarname('İhtarname', 2),
  kvkk('KVKK / veri talebi', 3),
  diger('Diğer', 5);

  const TalepTuru(this.ad, this.slaIsGunu);
  final String ad;
  final int slaIsGunu;
}

enum Oncelik {
  dusuk('Düşük'),
  normal('Normal'),
  yuksek('Yüksek'),
  acil('Acil');

  const Oncelik(this.ad);
  final String ad;

  /// Önceliğe göre iş günü: acil 1 gün, yüksek yarıya iner, düşükte iki katına çıkar.
  int slaIsGunu(TalepTuru tur) => switch (this) {
        acil => 1,
        yuksek => (tur.slaIsGunu / 2).ceil(),
        normal => tur.slaIsGunu,
        dusuk => tur.slaIsGunu * 2,
      };
}

enum TalepDurumu {
  yeni('Yeni'),
  atandi('Atandı'),
  bilgiBekleniyor('Bilgi bekleniyor'),
  incelemede('İncelemede'),
  onayda('Onayda'),
  tamamlandi('Tamamlandı'),
  reddedildi('Reddedildi');

  const TalepDurumu(this.ad);
  final String ad;

  bool get kapali => this == tamamlandi || this == reddedildi;

  static const gecisler = <TalepDurumu, Set<TalepDurumu>>{
    yeni: {atandi, reddedildi},
    atandi: {incelemede, bilgiBekleniyor, reddedildi},
    incelemede: {bilgiBekleniyor, onayda, tamamlandi},
    bilgiBekleniyor: {incelemede},
    onayda: {incelemede, tamamlandi},
    tamamlandi: {},
    reddedildi: {},
  };
}

enum SlaDurumu {
  zamaninda('Zamanında'),
  riskli('Süre doluyor'),
  gecikti('Gecikti'),
  durduruldu('Bilgi bekleniyor');

  const SlaDurumu(this.ad);
  final String ad;
}

class TalepOlayi {
  const TalepOlayi(this.tarih, this.kullanici, this.aciklama);
  final Tarih tarih;
  final String kullanici;
  final String aciklama;
}

/// İş günü hesabı: hafta sonu ve tam gün resmî tatiller sayılmaz (yarım gün çalışma günüdür).
class IsGunuHesabi {
  const IsGunuHesabi(this.takvim);
  final TatilTakvimi takvim;

  bool isGunu(Tarih t) {
    if (t.haftaSonu) return false;
    final tatil = takvim.tatil(t);
    return tatil == null || !tatil.tamGun;
  }

  Tarih ekle(Tarih baslangic, int gunSayisi) {
    var t = baslangic;
    var kalan = gunSayisi;
    while (kalan > 0) {
      t = t.gunEkle(1);
      if (isGunu(t)) kalan--;
    }
    return t;
  }

  /// [bas] hariç, [son] dahil aradaki iş günü sayısı.
  int arasinda(Tarih bas, Tarih son) {
    var n = 0;
    for (var t = bas.gunEkle(1); !t.isAfter(son); t = t.gunEkle(1)) {
      if (isGunu(t)) n++;
    }
    return n;
  }
}

class HukukTalebi {
  HukukTalebi({
    required this.id,
    required this.no,
    required this.baslik,
    required this.aciklama,
    required this.tur,
    required this.oncelik,
    required this.talepEden,
    required this.birim,
    required this.olusturma,
    required this.slaSonGun,
    this.sozlesmeId,
    this.sirketId,
    Tarih? beklemeBaslangici,
  }) : _beklemeBaslangici = beklemeBaslangici;

  final String id;
  final String no;
  final String baslik;
  final String aciklama;
  final TalepTuru tur;
  final Oncelik oncelik;
  final String talepEden;
  final String birim;
  final Tarih olusturma;
  String? sozlesmeId;

  /// Talebin geldiği grup şirketi.
  String? sirketId;
  String atanan = '';
  TalepDurumu durum = TalepDurumu.yeni;
  Tarih slaSonGun;
  Tarih? _beklemeBaslangici;

  /// Bilgi beklemesinin başladığı gün (sunucuda saklanır; SLA bu kadar iş günü ötelenir).
  Tarih? get beklemeBaslangici => _beklemeBaslangici;
  Tarih? kapanis;
  final List<TalepOlayi> gecmis = [];

  /// SLA durumu. Bilgi beklenirken süre işlemez; son 1 iş günü "riskli" sayılır.
  SlaDurumu slaDurumu(Tarih bugun, IsGunuHesabi hesap) {
    if (durum == TalepDurumu.bilgiBekleniyor) return SlaDurumu.durduruldu;
    final kontrol = durum.kapali ? (kapanis ?? bugun) : bugun;
    if (kontrol.isAfter(slaSonGun)) return SlaDurumu.gecikti;
    if (durum.kapali) return SlaDurumu.zamaninda;
    return hesap.arasinda(bugun, slaSonGun) <= 1 ? SlaDurumu.riskli : SlaDurumu.zamaninda;
  }

  void durumDegistir(TalepDurumu hedef, {required String kullanici, required Tarih bugun, required IsGunuHesabi hesap,
      String not = ''}) {
    if (!TalepDurumu.gecisler[durum]!.contains(hedef)) {
      throw StateError('${durum.ad} durumundan ${hedef.ad} durumuna geçilemez.');
    }
    if (hedef == TalepDurumu.reddedildi && not.trim().isEmpty) {
      throw ArgumentError('Ret gerekçesi yazılmalıdır.');
    }
    if (hedef == TalepDurumu.bilgiBekleniyor) _beklemeBaslangici = bugun;
    final bekleme = _beklemeBaslangici;
    if (durum == TalepDurumu.bilgiBekleniyor && bekleme != null) {
      // Beklenen iş günü kadar SLA ileri kayar.
      final duran = hesap.arasinda(bekleme, bugun);
      slaSonGun = hesap.ekle(slaSonGun, duran);
      _beklemeBaslangici = null;
    }
    if (hedef.kapali) kapanis = bugun;
    durum = hedef;
    gecmis.add(TalepOlayi(bugun, kullanici, '${hedef.ad}${not.isEmpty ? '' : ': $not'}'));
  }
}

/// Atama kuralı: talep türüne göre aday ekip; adaylar arasında açık işi en az olana atanır.
class TalepYonlendirici {
  const TalepYonlendirici(this.kurallar);

  final Map<TalepTuru, List<String>> kurallar;

  String? atanacak(HukukTalebi talep, Iterable<HukukTalebi> tumTalepler) {
    final adaylar = kurallar[talep.tur] ?? kurallar[TalepTuru.diger] ?? const [];
    if (adaylar.isEmpty) return null;
    int yuk(String kisi) => tumTalepler.where((t) => t.atanan == kisi && !t.durum.kapali).length;
    return adaylar.reduce((a, b) => yuk(b) < yuk(a) ? b : a);
  }
}

class TalepDefteri {
  TalepDefteri({required this.hesap, required this.yonlendirici, int yil = 2026}) : _yil = yil;

  final IsGunuHesabi hesap;
  final TalepYonlendirici yonlendirici;
  final List<HukukTalebi> talepler = [];
  final int _yil;
  int _sira = 0;

  HukukTalebi olustur({
    required String baslik,
    required String aciklama,
    required TalepTuru tur,
    required Oncelik oncelik,
    required String talepEden,
    required String birim,
    required Tarih bugun,
    String? sozlesmeId,
    String? sirketId,
    bool otomatikAta = true,
  }) {
    if (baslik.trim().isEmpty) throw ArgumentError('Başlık zorunludur.');
    _sira++;
    final t = HukukTalebi(
      id: 'tlp$_sira',
      no: 'HT-$_yil-${_sira.toString().padLeft(4, '0')}',
      baslik: baslik.trim(),
      aciklama: aciklama.trim(),
      tur: tur,
      oncelik: oncelik,
      talepEden: talepEden,
      birim: birim,
      olusturma: bugun,
      slaSonGun: hesap.ekle(bugun, oncelik.slaIsGunu(tur)),
      sozlesmeId: sozlesmeId,
      sirketId: sirketId,
    );
    t.gecmis.add(TalepOlayi(bugun, talepEden, 'Talep oluşturuldu'));
    if (otomatikAta) {
      final kisi = yonlendirici.atanacak(t, talepler);
      if (kisi != null) {
        t.atanan = kisi;
        t.durumDegistir(TalepDurumu.atandi, kullanici: 'sistem', bugun: bugun, hesap: hesap, not: kisi);
      }
    }
    talepler.add(t);
    return t;
  }
}
