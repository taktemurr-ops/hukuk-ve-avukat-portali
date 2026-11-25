/// Müşterinin kayıt olurken seçtiği hesap türü.
enum HesapTuru {
  avukatlikBurosu('Avukatlık Bürosu', 'Tek başına çalışan avukat'),
  hukukBurosu('Hukuk Bürosu', 'Birden çok avukatlı büro veya avukatlık ortaklığı'),
  kurumsal('Kurumsal', 'Şirket hukuk müşavirliği veya hukuk birimi');

  const HesapTuru(this.ad, this.aciklama);

  final String ad;
  final String aciklama;
}

/// Platform modülleri. Lisans profili hangi modüllerin açık olacağını belirler.
enum Modul {
  musteriVeTaraf('Müvekkil ve taraf'),
  cikarCatismasi('Çıkar çatışması ve iş kabulü'),
  vekalet('Vekâlet ve temsil'),
  dosya('Dava ve dosya'),
  icra('İcra ve tahsilat'),
  sureVeTakvim('Süre, duruşma ve takvim'),
  gorev('Görev ve iş akışı'),
  tebligat('Tebligat ve resmî yazışma'),
  belge('Belge, delil ve arşiv'),
  sablon('Dilekçe ve şablon'),
  hesaplamaAraclari('Hesaplama araçları'),
  buroFinansi('Büro finansı ve e-SMM'),
  zamanKaydi('Zaman kaydı'),
  muvekkilPortali('Müvekkil portalı'),
  ekipVeGelirPaylasimi('Ekip ve gelir paylaşımı'),
  etikDuvar('Etik duvar'),
  topluIcra('Toplu icra işlemleri'),
  organizasyon('Organizasyon ve grup şirketleri'),
  icTalepler('İç hukuk talepleri'),
  sozlesmeYonetimi('Sözleşme yönetimi ve otomatik tarama'),
  disAvukat('Dış avukat yönetimi'),
  kurumsalFinans('Kurumsal hukuk finansı ve karşılık'),
  kurumsalYonetim('Kurumsal yönetim'),
  uyum('Uyum, KVKK ve soruşturma'),
  fikriMulkiyet('Fikrî mülkiyet'),
  isBirimiPortali('İş birimi portalı'),
  raporlar('Raporlar ve göstergeler'),
  yapayZeka('Yapay zekâ asistanı');

  const Modul(this.ad);

  final String ad;
}

/// Hazır rol şablonları.
enum Rol {
  buroSahibi('Büro sahibi'),
  yoneticiOrtak('Yönetici ortak'),
  ortak('Ortak'),
  avukat('Avukat'),
  stajyer('Stajyer avukat'),
  sekreter('Sekreter / asistan'),
  muhasebe('Muhasebe'),
  muvekkil('Müvekkil'),
  muhabirAvukat('Muhabir avukat'),
  hukukDirektoru('Hukuk direktörü'),
  sirketAvukati('Şirket avukatı'),
  hukukUzmani('Hukuk uzmanı'),
  talepEden('Talep eden çalışan'),
  onayci('Onaycı'),
  finansVeSatinAlma('Finans ve satın alma'),
  disAvukat('Dış avukat'),
  btYoneticisi('BT yöneticisi'),
  denetci('Denetçi');

  const Rol(this.ad);

  final String ad;
}

/// Hesap türünün lisans profili: açık modüller ve hazır roller.
///
/// Canlıda profiller yönetim panelinden düzenlenir; buradaki değerler varsayılandır.
class LisansProfili {
  const LisansProfili({required this.hesapTuru, required this.moduller, required this.roller});

  final HesapTuru hesapTuru;
  final Set<Modul> moduller;
  final List<Rol> roller;

  bool modulAcik(Modul modul) => moduller.contains(modul);

  static const Set<Modul> _buroTemel = {
    Modul.musteriVeTaraf,
    Modul.cikarCatismasi,
    Modul.vekalet,
    Modul.dosya,
    Modul.icra,
    Modul.sureVeTakvim,
    Modul.gorev,
    Modul.tebligat,
    Modul.belge,
    Modul.sablon,
    Modul.hesaplamaAraclari,
    Modul.buroFinansi,
    Modul.raporlar,
  };

  static const avukatlikBurosu = LisansProfili(
    hesapTuru: HesapTuru.avukatlikBurosu,
    moduller: _buroTemel,
    roller: [Rol.buroSahibi, Rol.sekreter, Rol.stajyer, Rol.muvekkil],
  );

  static const hukukBurosu = LisansProfili(
    hesapTuru: HesapTuru.hukukBurosu,
    moduller: {
      ..._buroTemel,
      Modul.zamanKaydi,
      Modul.muvekkilPortali,
      Modul.ekipVeGelirPaylasimi,
      Modul.etikDuvar,
      Modul.topluIcra,
    },
    roller: [
      Rol.yoneticiOrtak,
      Rol.ortak,
      Rol.avukat,
      Rol.stajyer,
      Rol.sekreter,
      Rol.muhasebe,
      Rol.muvekkil,
      Rol.muhabirAvukat,
    ],
  );

  static const kurumsal = LisansProfili(
    hesapTuru: HesapTuru.kurumsal,
    moduller: {
      Modul.organizasyon,
      Modul.musteriVeTaraf,
      Modul.vekalet,
      Modul.dosya,
      Modul.icra,
      Modul.sureVeTakvim,
      Modul.gorev,
      Modul.tebligat,
      Modul.belge,
      Modul.sablon,
      Modul.hesaplamaAraclari,
      Modul.icTalepler,
      Modul.sozlesmeYonetimi,
      Modul.disAvukat,
      Modul.kurumsalFinans,
      Modul.kurumsalYonetim,
      Modul.uyum,
      Modul.fikriMulkiyet,
      Modul.isBirimiPortali,
      Modul.raporlar,
    },
    roller: [
      Rol.hukukDirektoru,
      Rol.sirketAvukati,
      Rol.hukukUzmani,
      Rol.talepEden,
      Rol.onayci,
      Rol.finansVeSatinAlma,
      Rol.disAvukat,
      Rol.btYoneticisi,
      Rol.denetci,
    ],
  );

  static LisansProfili varsayilan(HesapTuru tur) => switch (tur) {
        HesapTuru.avukatlikBurosu => avukatlikBurosu,
        HesapTuru.hukukBurosu => hukukBurosu,
        HesapTuru.kurumsal => kurumsal,
      };
}
