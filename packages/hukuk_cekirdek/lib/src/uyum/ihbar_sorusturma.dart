import 'dart:math';

enum IhbarKategorisi {
  rusvetYolsuzluk('Rüşvet ve yolsuzluk'),
  dolandiricilik('Dolandırıcılık ve suistimal'),
  cikarCatismasi('Çıkar çatışması'),
  tacizMobbing('Taciz ve mobbing'),
  veriIhlali('Kişisel veri ihlali'),
  rekabet('Rekabet hukuku'),
  isSagligi('İş sağlığı ve güvenliği'),
  diger('Diğer');

  const IhbarKategorisi(this.ad);
  final String ad;
}

enum IhbarKanali {
  web('Web formu'),
  eposta('E-posta'),
  telefon('Telefon hattı'),
  yuzYuze('Yüz yüze');

  const IhbarKanali(this.ad);
  final String ad;
}

/// Etik/uyum ihbarı. Anonim ihbarcı, takip koduyla durumu izleyip ek bilgi verebilir.
class Ihbar {
  const Ihbar({
    required this.id,
    required this.takipKodu,
    required this.zaman,
    required this.kanal,
    required this.kategori,
    required this.aciklama,
    this.anonim = true,
    this.ihbarciIletisim,
    this.ilgiliKisiler = const {},
    this.sirketId,
  });

  final String id;
  final String takipKodu;
  final DateTime zaman;
  final IhbarKanali kanal;
  final IhbarKategorisi kategori;
  final String aciklama;
  final bool anonim;

  /// Anonim ihbarda tutulmaz.
  final String? ihbarciIletisim;

  /// İhbar edilen kişiler (kullanıcı kimlikleri); bu kişiler soruşturma ekibinde olamaz.
  final Set<String> ilgiliKisiler;
  final String? sirketId;

  /// Karışabilecek karakterler (0/O, 1/I) çıkarılmış 10 karakterlik kod.
  static String takipKoduUret([Random? r]) {
    const alfabe = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rr = r ?? Random.secure();
    return List.generate(10, (_) => alfabe[rr.nextInt(alfabe.length)]).join();
  }
}

enum SorusturmaDurumu {
  onInceleme('Ön inceleme'),
  sorusturma('Soruşturma'),
  raporlama('Raporlama'),
  kapandi('Kapandı'),
  reddedildi('Ön incelemede reddedildi');

  const SorusturmaDurumu(this.ad);
  final String ad;

  bool get acik => this != kapandi && this != reddedildi;
}

enum SorusturmaSonucu {
  dogrulandi('Doğrulandı'),
  kismen('Kısmen doğrulandı'),
  dogrulanamadi('Doğrulanamadı'),
  asilsiz('Asılsız');

  const SorusturmaSonucu(this.ad);
  final String ad;
}

class SorusturmaNotu {
  const SorusturmaNotu(this.zaman, this.kullanici, this.metin);
  final DateTime zaman;
  final String kullanici;
  final String metin;
}

/// İç soruşturma dosyası. Yalnızca sorumlu ve ekip erişir; ihbar edilen kişi ekipte olamaz.
class Sorusturma {
  Sorusturma({required this.id, required this.ihbar, required this.sorumlu, required this.acilis}) {
    if (ihbar.ilgiliKisiler.contains(sorumlu)) {
      throw StateError('İhbar edilen kişi soruşturmayı yürütemez.');
    }
  }

  /// Kurum politikası (taslak): ihbarcıya ilk geri bildirim 7 gün, sonuç 90 gün içinde.
  static const geriBildirimGunu = 7;
  static const sonucGunu = 90;

  final String id;
  final Ihbar ihbar;
  final String sorumlu;
  final DateTime acilis;
  final Set<String> ekip = {};
  final List<SorusturmaNotu> notlar = [];
  SorusturmaDurumu durum = SorusturmaDurumu.onInceleme;
  SorusturmaSonucu? sonuc;
  String? sonucOzeti;
  DateTime? ilkGeriBildirim;

  DateTime get geriBildirimSonu => acilis.add(const Duration(days: geriBildirimGunu));
  DateTime get sonucSonu => acilis.add(const Duration(days: sonucGunu));

  bool erisebilir(String kullanici) => kullanici == sorumlu || ekip.contains(kullanici);

  void _yetki(String kullanici) {
    if (!erisebilir(kullanici)) throw StateError('Bu soruşturmaya erişim yetkiniz yok.');
  }

  void ekipEkle(String kullanici, {required String ekleyen}) {
    _yetki(ekleyen);
    if (ihbar.ilgiliKisiler.contains(kullanici)) throw StateError('İhbar edilen kişi soruşturma ekibine eklenemez.');
    ekip.add(kullanici);
  }

  void notEkle(String kullanici, String metin, DateTime zaman) {
    _yetki(kullanici);
    if (metin.trim().isEmpty) throw ArgumentError('Not boş olamaz.');
    notlar.add(SorusturmaNotu(zaman, kullanici, metin.trim()));
  }

  void geriBildirimVer(String kullanici, DateTime zaman) {
    _yetki(kullanici);
    ilkGeriBildirim ??= zaman;
  }

  bool geriBildirimGecikti(DateTime simdi) => ilkGeriBildirim == null && durum.acik && simdi.isAfter(geriBildirimSonu);

  bool sonucGecikti(DateTime simdi) => durum.acik && simdi.isAfter(sonucSonu);

  void sorusturmayaAl(String kullanici) {
    _yetki(kullanici);
    if (durum != SorusturmaDurumu.onInceleme) throw StateError('Yalnızca ön incelemedeki ihbar soruşturmaya alınır.');
    durum = SorusturmaDurumu.sorusturma;
  }

  void raporlamayaGec(String kullanici) {
    _yetki(kullanici);
    if (durum != SorusturmaDurumu.sorusturma) throw StateError('Önce soruşturma aşamasında olmalı.');
    durum = SorusturmaDurumu.raporlama;
  }

  void reddet(String kullanici, String gerekce) {
    _yetki(kullanici);
    if (durum != SorusturmaDurumu.onInceleme) throw StateError('Yalnızca ön incelemede reddedilebilir.');
    if (gerekce.trim().length < 10) throw ArgumentError('Ret gerekçesi en az 10 karakter olmalı.');
    durum = SorusturmaDurumu.reddedildi;
    sonucOzeti = gerekce.trim();
  }

  void kapat(String kullanici, SorusturmaSonucu s, String ozet) {
    _yetki(kullanici);
    if (durum != SorusturmaDurumu.raporlama) throw StateError('Kapatmak için raporlama aşamasında olmalı.');
    if (ozet.trim().length < 20) throw ArgumentError('Sonuç özeti en az 20 karakter olmalı.');
    sonuc = s;
    sonucOzeti = ozet.trim();
    durum = SorusturmaDurumu.kapandi;
  }
}

/// Kişisel veri ihlali. KVKK Kurulu'nun 24.01.2019 tarihli ve 2019/10 sayılı kararı uyarınca
/// ihlal, öğrenilmesinden itibaren en geç 72 saat içinde Kurul'a bildirilir.
class VeriIhlali {
  VeriIhlali({required this.id, required this.ogrenilme, required this.aciklama, this.etkilenenKisiSayisi});

  static const kurulBildirimSuresi = Duration(hours: 72);

  final String id;
  final DateTime ogrenilme;
  final String aciklama;
  final int? etkilenenKisiSayisi;
  DateTime? kurulaBildirim;
  DateTime? ilgililereBildirim;

  DateTime get kurulSonZaman => ogrenilme.add(kurulBildirimSuresi);

  Duration kalan(DateTime simdi) => kurulSonZaman.difference(simdi);

  bool gecikti(DateTime simdi) => kurulaBildirim == null ? simdi.isAfter(kurulSonZaman) : kurulaBildirim!.isAfter(kurulSonZaman);

  void kurulaBildirildi(DateTime zaman) {
    if (zaman.isBefore(ogrenilme)) throw ArgumentError('Bildirim, öğrenilmeden önce olamaz.');
    kurulaBildirim = zaman;
  }
}
