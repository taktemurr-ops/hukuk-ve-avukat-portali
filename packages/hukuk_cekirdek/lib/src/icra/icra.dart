import '../hesaplama/faiz.dart';
import '../hesaplama/para.dart';
import '../sure/onay_durumu.dart';
import '../takvim/tarih.dart';

enum TakipTuru {
  ilamsiz('İlamsız takip (Örnek 7)', pesinHarc: true),
  kambiyo('Kambiyo senedine dayalı takip (Örnek 10)', pesinHarc: true),
  kira('Kira alacağı takibi (Örnek 13)', pesinHarc: true),
  ilamli('İlamlı takip (Örnek 4-5)', pesinHarc: false),
  rehin('Rehnin paraya çevrilmesi', pesinHarc: true);

  const TakipTuru(this.ad, {required this.pesinHarc});
  final String ad;

  /// İlama dayanmayan takiplerde peşin harç alınır (492 s.K. m.29).
  final bool pesinHarc;
}

/// Tahsil harcının oranını belirleyen ödeme aşaması.
enum TahsilAsamasi {
  hacizdenOnce('Ödeme/icra emri tebliğinden sonra, hacizden önce'),
  hacizSonrasi('Hacizden sonra, satıştan önce'),
  satis('Satış yoluyla tahsil');

  const TahsilAsamasi(this.ad);
  final String ad;
}

/// İcra harçları (492 s.K. (1) sayılı tarife). Referans veri; avukat onayı bekler.
///
/// Tahsil harcı oranları 2010-2011'de %3,96 / %7,92 / %9,90; 1.1.2012'den beri %4,55 / %9,10 / %11,38.
/// Peşin harç (binde 5, HK m.28) ve cezaevi harcı (%2) dönem boyunca aynıdır.
class IcraHarcTarifesi {
  const IcraHarcTarifesi({
    required this.yil,
    this.baslangicAy = 1,
    this.baslangicGun = 1,
    required this.basvurmaHarci,
    required this.pesinHarcBinde,
    required this.tahsilOranlari,
    required this.cezaeviOrani,
    this.onayDurumu = OnayDurumu.taslak,
    required this.kaynak,
  });

  final int yil;
  final int baslangicAy;
  final int baslangicGun;
  final Para basvurmaHarci;
  final double pesinHarcBinde;
  final Map<TahsilAsamasi, double> tahsilOranlari;

  /// Tahsil edilen paradan alınan cezaevi harcı yüzdesi (alacaklıdan; borçluya yüklenemez).
  final double cezaeviOrani;
  final OnayDurumu onayDurumu;
  final String kaynak;

  Tarih get yururluk => Tarih(yil, baslangicAy, baslangicGun);

  static const _eskiOranlar = {
    TahsilAsamasi.hacizdenOnce: 3.96,
    TahsilAsamasi.hacizSonrasi: 7.92,
    TahsilAsamasi.satis: 9.90,
  };

  static const _oranlar = {
    TahsilAsamasi.hacizdenOnce: 4.55,
    TahsilAsamasi.hacizSonrasi: 9.10,
    TahsilAsamasi.satis: 11.38,
  };

  static const y2010 = IcraHarcTarifesi(
    yil: 2010,
    basvurmaHarci: Para.kurus(1710),
    pesinHarcBinde: 5,
    tahsilOranlari: _eskiOranlar,
    cezaeviOrani: 2,
    kaynak: 'HK Genel Tebliği (2010); icraya başvurma harcı asliye başvurma harcına eşittir',
  );

  static const y2011 = IcraHarcTarifesi(
    yil: 2011,
    basvurmaHarci: Para.kurus(1840),
    pesinHarcBinde: 5,
    tahsilOranlari: _eskiOranlar,
    cezaeviOrani: 2,
    kaynak: 'HK Genel Tebliği (2011); icraya başvurma harcı asliye başvurma harcına eşittir',
  );

  static const y2012 = IcraHarcTarifesi(
    yil: 2012,
    basvurmaHarci: Para.kurus(2115),
    pesinHarcBinde: 5,
    tahsilOranlari: _oranlar,
    cezaeviOrani: 2,
    kaynak: 'HK Genel Tebliği (2012); icraya başvurma harcı asliye başvurma harcına eşittir',
  );

  static const y2013 = IcraHarcTarifesi(
    yil: 2013,
    basvurmaHarci: Para.kurus(2430),
    pesinHarcBinde: 5,
    tahsilOranlari: _oranlar,
    cezaeviOrani: 2,
    kaynak: 'HK Genel Tebliği (2013); icraya başvurma harcı asliye başvurma harcına eşittir',
  );

  static const y2014 = IcraHarcTarifesi(
    yil: 2014,
    basvurmaHarci: Para.kurus(2520),
    pesinHarcBinde: 5,
    tahsilOranlari: _oranlar,
    cezaeviOrani: 2,
    kaynak: 'HK Genel Tebliği (2014); icraya başvurma harcı asliye başvurma harcına eşittir',
  );

  static const y2015 = IcraHarcTarifesi(
    yil: 2015,
    basvurmaHarci: Para.kurus(2770),
    pesinHarcBinde: 5,
    tahsilOranlari: _oranlar,
    cezaeviOrani: 2,
    kaynak: 'HK Genel Tebliği (2015); icraya başvurma harcı asliye başvurma harcına eşittir',
  );

  static const y2016 = IcraHarcTarifesi(
    yil: 2016,
    basvurmaHarci: Para.kurus(2920),
    pesinHarcBinde: 5,
    tahsilOranlari: _oranlar,
    cezaeviOrani: 2,
    kaynak: 'HK Genel Tebliği (2016); icraya başvurma harcı asliye başvurma harcına eşittir',
  );

  static const y2017 = IcraHarcTarifesi(
    yil: 2017,
    basvurmaHarci: Para.kurus(3140),
    pesinHarcBinde: 5,
    tahsilOranlari: _oranlar,
    cezaeviOrani: 2,
    kaynak: 'HK Genel Tebliği (2017); icraya başvurma harcı asliye başvurma harcına eşittir',
  );

  static const y2018 = IcraHarcTarifesi(
    yil: 2018,
    basvurmaHarci: Para.kurus(3590),
    pesinHarcBinde: 5,
    tahsilOranlari: _oranlar,
    cezaeviOrani: 2,
    kaynak: 'HK Genel Tebliği (2018); icraya başvurma harcı asliye başvurma harcına eşittir',
  );

  static const y2019 = IcraHarcTarifesi(
    yil: 2019,
    basvurmaHarci: Para.kurus(4440),
    pesinHarcBinde: 5,
    tahsilOranlari: _oranlar,
    cezaeviOrani: 2,
    kaynak: 'HK Genel Tebliği (2019); icraya başvurma harcı asliye başvurma harcına eşittir',
  );

  static const y2020 = IcraHarcTarifesi(
    yil: 2020,
    basvurmaHarci: Para.kurus(5440),
    pesinHarcBinde: 5,
    tahsilOranlari: _oranlar,
    cezaeviOrani: 2,
    kaynak: 'HK Genel Tebliği (2020); icraya başvurma harcı asliye başvurma harcına eşittir',
  );

  static const y2021 = IcraHarcTarifesi(
    yil: 2021,
    basvurmaHarci: Para.kurus(5930),
    pesinHarcBinde: 5,
    tahsilOranlari: _oranlar,
    cezaeviOrani: 2,
    kaynak: 'HK Genel Tebliği (2021); icraya başvurma harcı asliye başvurma harcına eşittir',
  );

  static const y2022 = IcraHarcTarifesi(
    yil: 2022,
    basvurmaHarci: Para.kurus(8070),
    pesinHarcBinde: 5,
    tahsilOranlari: _oranlar,
    cezaeviOrani: 2,
    kaynak: 'HK Genel Tebliği (2022); icraya başvurma harcı asliye başvurma harcına eşittir',
  );

  static const y2023 = IcraHarcTarifesi(
    yil: 2023,
    basvurmaHarci: Para.kurus(17990),
    pesinHarcBinde: 5,
    tahsilOranlari: _oranlar,
    cezaeviOrani: 2,
    kaynak: 'HK Genel Tebliği (2023); icraya başvurma harcı asliye başvurma harcına eşittir',
  );

  static const y2023Temmuz = IcraHarcTarifesi(
    yil: 2023,
    baslangicAy: 7,
    baslangicGun: 15,
    basvurmaHarci: Para.kurus(26985),
    pesinHarcBinde: 5,
    tahsilOranlari: _oranlar,
    cezaeviOrani: 2,
    kaynak: 'HK Genel Tebliği (2023); icraya başvurma harcı asliye başvurma harcına eşittir',
  );

  static const y2024 = IcraHarcTarifesi(
    yil: 2024,
    basvurmaHarci: Para.kurus(42760),
    pesinHarcBinde: 5,
    tahsilOranlari: _oranlar,
    cezaeviOrani: 2,
    kaynak: 'HK Genel Tebliği (2024); icraya başvurma harcı asliye başvurma harcına eşittir',
  );

  static const y2025 = IcraHarcTarifesi(
    yil: 2025,
    basvurmaHarci: Para.kurus(61540),
    pesinHarcBinde: 5,
    tahsilOranlari: _oranlar,
    cezaeviOrani: 2,
    kaynak: 'HK Genel Tebliği (2025); icraya başvurma harcı asliye başvurma harcına eşittir',
  );

  static const y2026 = IcraHarcTarifesi(
    yil: 2026,
    basvurmaHarci: Para.kurus(73200),
    pesinHarcBinde: 5,
    tahsilOranlari: _oranlar,
    cezaeviOrani: 2,
    kaynak: 'Harçlar Kanunu Genel Tebliği Seri No: 98 (RG 31.12.2025/33124 5. mük.)',
  );

  static const List<IcraHarcTarifesi> tumu = [
    y2010,
    y2011,
    y2012,
    y2013,
    y2014,
    y2015,
    y2016,
    y2017,
    y2018,
    y2019,
    y2020,
    y2021,
    y2022,
    y2023,
    y2023Temmuz,
    y2024,
    y2025,
    y2026,
  ];

  /// Verilen tarihte yürürlükte olan icra harç tarifesi; 2010 öncesi için 2010 tarifesi döner.
  static IcraHarcTarifesi gecerli(Tarih tarih) {
    var sonuc = tumu.first;
    for (final t in tumu) {
      if (!t.yururluk.isAfter(tarih)) sonuc = t;
    }
    return sonuc;
  }
}

class TakipTalebi {
  const TakipTalebi({
    required this.tur,
    required this.asilAlacak,
    required this.temerrutTarihi,
    required this.takipTarihi,
    this.takipOncesiMasraf = Para.sifir,
    this.islemisFaizElle,
  });

  final TakipTuru tur;
  final Para asilAlacak;

  /// Faizin işlemeye başladığı tarih (bu gün hariç).
  final Tarih temerrutTarihi;
  final Tarih takipTarihi;

  /// İhtarname, protesto gibi takipten önceki giderler.
  final Para takipOncesiMasraf;

  /// Talepte işlemiş faiz elle yazıldıysa (ör. sözleşmeye göre); null ise tablodan hesaplanır.
  final Para? islemisFaizElle;
}

class AcilisHarclari {
  const AcilisHarclari(this.basvurma, this.pesin);
  final Para basvurma;
  final Para pesin;
  Para get toplam => basvurma + pesin;
}

class Tahsilat {
  const Tahsilat({required this.id, required this.tarih, required this.tutar, this.aciklama = ''});
  final String id;
  final Tarih tarih;
  final Para tutar;
  final String aciklama;
}

/// Bir tahsilatın nereye mahsup edildiği.
class Mahsup {
  const Mahsup({required this.tahsilat, required this.masrafa, required this.faize, required this.anaparaya, required this.fazla});
  final Tahsilat tahsilat;
  final Para masrafa;
  final Para faize;
  final Para anaparaya;

  /// Borçtan fazla ödenen ve iade edilecek kısım.
  final Para fazla;
}

/// Dosya hesabı (kapak hesabı).
class KapakHesabi {
  const KapakHesabi({
    required this.hesapTarihi,
    required this.asilAlacak,
    required this.islemisFaiz,
    required this.takipSonrasiFaiz,
    required this.masraflar,
    required this.vekaletUcreti,
    required this.tahsilEdilen,
    required this.kalanAnapara,
    required this.kalanFaiz,
    required this.kalanMasraf,
    required this.tahsilHarci,
    required this.pesinHarcMahsubu,
    required this.cezaeviHarci,
    required this.mahsuplar,
    required this.uyarilar,
  });

  final Tarih hesapTarihi;
  final Para asilAlacak;
  final Para islemisFaiz;
  final Para takipSonrasiFaiz;

  /// Takip öncesi ve sonrası giderler, harçlar (vekâlet ücreti hariç).
  final Para masraflar;
  final Para vekaletUcreti;
  final Para tahsilEdilen;
  final Para kalanAnapara;
  final Para kalanFaiz;

  /// Kalan masraf ve vekâlet ücreti.
  final Para kalanMasraf;

  /// Kalan borç üzerinden borçludan ayrıca alınacak tahsil harcı (peşin harç mahsup edilmiş).
  final Para tahsilHarci;
  final Para pesinHarcMahsubu;

  /// Tahsil edilen paradan alacaklıya düşen cezaevi harcı (bilgi).
  final Para cezaeviHarci;
  final List<Mahsup> mahsuplar;
  final List<String> uyarilar;

  Para get kalanBorc => kalanAnapara + kalanFaiz + kalanMasraf;
  Para get borcluyaToplam => kalanBorc + tahsilHarci;
  Para get toplamAlacak => asilAlacak + islemisFaiz + takipSonrasiFaiz + masraflar + vekaletUcreti;
  bool get kapandi => kalanBorc.kurus <= 0;
}

class IcraHesabi {
  IcraHesabi._();

  static AcilisHarclari acilisHarclari(TakipTalebi t, Para islemisFaiz, {IcraHarcTarifesi? tarife}) {
    tarife ??= IcraHarcTarifesi.gecerli(t.takipTarihi);
    final takipMiktari = t.asilAlacak + islemisFaiz;
    final pesin = t.tur.pesinHarc ? takipMiktari.carp(tarife.pesinHarcBinde / 1000) : Para.sifir;
    return AcilisHarclari(tarife.basvurmaHarci, pesin);
  }

  static Para islemisFaiz(TakipTalebi t, FaizTablosu tablo) =>
      t.islemisFaizElle ??
      (t.takipTarihi.isAfter(t.temerrutTarihi)
          ? FaizHesaplayici.hesapla(anapara: t.asilAlacak, baslangic: t.temerrutTarihi, bitis: t.takipTarihi, tablo: tablo)
              .toplamFaiz
          : Para.sifir);

  /// Takip sonrası faiz yalnızca kalan asıl alacak üzerinden işler (işlemiş faize faiz yürütülmez).
  /// Kısmi ödemeler sırasıyla masraf ve vekâlet ücretine, faize, sonra asıl alacağa mahsup edilir (TBK m.100).
  static KapakHesabi hesapla({
    required TakipTalebi talep,
    required FaizTablosu tablo,
    required Tarih hesapTarihi,
    List<Tahsilat> tahsilatlar = const [],
    Para takipSonrasiMasraf = Para.sifir,
    Para vekaletUcreti = Para.sifir,
    TahsilAsamasi asama = TahsilAsamasi.hacizdenOnce,
    IcraHarcTarifesi? tarife,
  }) {
    if (hesapTarihi.isBefore(talep.takipTarihi)) throw ArgumentError('Hesap tarihi takip tarihinden önce olamaz.');
    // Tarife verilmezse: açılış harçları takip tarihindeki, tahsil harcı hesap tarihindeki tarifeyle.
    final acilisTarifesi = tarife ?? IcraHarcTarifesi.gecerli(talep.takipTarihi);
    final tahsilTarifesi = tarife ?? IcraHarcTarifesi.gecerli(hesapTarihi);
    final uyarilar = <String>[
      if (tablo.onayDurumu != OnayDurumu.onayli) 'Faiz oranları avukat onayı bekliyor.',
      if (tahsilTarifesi.onayDurumu != OnayDurumu.onayli) '${tahsilTarifesi.yil} icra harç tarifesi avukat onayı bekliyor.',
      if (tarife != null && hesapTarihi.yil != tarife.yil)
        'Hesap yılı (${hesapTarihi.yil}) harç tarifesi yılından (${tarife.yil}) farklı.',
    ];
    final islemis = islemisFaiz(talep, tablo);
    final acilis = acilisHarclari(talep, islemis, tarife: acilisTarifesi);
    final toplamMasraf = talep.takipOncesiMasraf + acilis.toplam + takipSonrasiMasraf;

    var anapara = talep.asilAlacak.kurus;
    var faizBorcu = islemis.kurus;
    var masrafBorcu = (toplamMasraf + vekaletUcreti).kurus;
    var takipSonrasiFaiz = 0;
    var tahsilEdilen = 0;
    var son = talep.takipTarihi;
    final mahsuplar = <Mahsup>[];

    int faizIslet(Tarih bas, Tarih bit) {
      if (anapara <= 0 || !bit.isAfter(bas)) return 0;
      return FaizHesaplayici.hesapla(anapara: Para.kurus(anapara), baslangic: bas, bitis: bit, tablo: tablo)
          .toplamFaiz
          .kurus;
    }

    final sirali = tahsilatlar.where((x) => !x.tarih.isAfter(hesapTarihi)).toList()
      ..sort((a, b) => a.tarih.compareTo(b.tarih));
    for (final t in sirali) {
      if (t.tarih.isBefore(talep.takipTarihi)) {
        uyarilar.add('${t.tarih.turkceBicim} tarihli tahsilat takip tarihinden önce; takip tarihinde mahsup edildi.');
      }
      final tarih = t.tarih.isBefore(son) ? son : t.tarih;
      final f = faizIslet(son, tarih);
      faizBorcu += f;
      takipSonrasiFaiz += f;
      son = tarih;

      var kalan = t.tutar.kurus;
      tahsilEdilen += kalan;
      int dus(int borc) {
        final d = kalan < borc ? kalan : borc;
        kalan -= d;
        return d;
      }

      final m = dus(masrafBorcu);
      masrafBorcu -= m;
      final fz = dus(faizBorcu);
      faizBorcu -= fz;
      final a = dus(anapara);
      anapara -= a;
      mahsuplar.add(Mahsup(
          tahsilat: t,
          masrafa: Para.kurus(m),
          faize: Para.kurus(fz),
          anaparaya: Para.kurus(a),
          fazla: Para.kurus(kalan)));
      if (kalan > 0) uyarilar.add('${t.tarih.turkceBicim} tarihli tahsilatta ${Para.kurus(kalan).bicimli} fazla ödeme var.');
    }
    final fSon = faizIslet(son, hesapTarihi);
    faizBorcu += fSon;
    takipSonrasiFaiz += fSon;

    final kalanBorc = anapara + faizBorcu + masrafBorcu;
    final oran = tahsilTarifesi.tahsilOranlari[asama]!;
    final brutTahsilHarci = (kalanBorc * oran / 100).round();
    // Peşin harç, tahsil harcına mahsup edilir (492 s.K. m.29/2); tahsilatlarda kullanılan kısım düşülür.
    final kullanilanHarc = (tahsilEdilen * oran / 100).round();
    final pesinKalan = acilis.pesin.kurus - kullanilanHarc;
    final mahsup = pesinKalan <= 0 ? 0 : (pesinKalan < brutTahsilHarci ? pesinKalan : brutTahsilHarci);

    return KapakHesabi(
      hesapTarihi: hesapTarihi,
      asilAlacak: talep.asilAlacak,
      islemisFaiz: islemis,
      takipSonrasiFaiz: Para.kurus(takipSonrasiFaiz),
      masraflar: toplamMasraf,
      vekaletUcreti: vekaletUcreti,
      tahsilEdilen: Para.kurus(tahsilEdilen),
      kalanAnapara: Para.kurus(anapara),
      kalanFaiz: Para.kurus(faizBorcu),
      kalanMasraf: Para.kurus(masrafBorcu),
      tahsilHarci: Para.kurus(brutTahsilHarci - mahsup),
      pesinHarcMahsubu: Para.kurus(mahsup),
      cezaeviHarci: Para.kurus((tahsilEdilen * tahsilTarifesi.cezaeviOrani / 100).round()),
      mahsuplar: mahsuplar,
      uyarilar: uyarilar,
    );
  }
}

enum IcraDurumu {
  takipAcildi('Takip açıldı'),
  odemeEmriTebligEdildi('Ödeme emri tebliğ edildi'),
  itirazEdildi('İtiraz edildi'),
  kesinlesti('Kesinleşti'),
  haciz('Haciz aşaması'),
  satis('Satış aşaması'),
  kapandi('Kapandı');

  const IcraDurumu(this.ad);
  final String ad;

  TahsilAsamasi get tahsilAsamasi => switch (this) {
        haciz => TahsilAsamasi.hacizSonrasi,
        satis => TahsilAsamasi.satis,
        _ => TahsilAsamasi.hacizdenOnce,
      };
}

/// İcra dosyası: takip talebi, borçlu, durum ve tahsilatlar.
class IcraDosyasi {
  IcraDosyasi({
    required this.id,
    required this.dosyaId,
    required this.icraDairesi,
    required this.borclu,
    required this.talep,
    this.esasNo,
    this.durum = IcraDurumu.takipAcildi,
    this.tebligTarihi,
    Para? vekaletUcreti,
    List<Tahsilat>? tahsilatlar,
    this.takipSonrasiMasraf = Para.sifir,
  })  : vekaletUcreti = vekaletUcreti ?? Para.sifir,
        tahsilatlar = tahsilatlar ?? [];

  final String id;
  final String dosyaId;
  final String icraDairesi;
  final String borclu;
  final TakipTalebi talep;
  String? esasNo;
  IcraDurumu durum;
  Tarih? tebligTarihi;
  Para vekaletUcreti;
  Para takipSonrasiMasraf;
  final List<Tahsilat> tahsilatlar;

  KapakHesabi hesap(Tarih hesapTarihi, FaizTablosu tablo, {IcraHarcTarifesi? tarife}) =>
      IcraHesabi.hesapla(
        talep: talep,
        tablo: tablo,
        hesapTarihi: hesapTarihi,
        tahsilatlar: tahsilatlar,
        takipSonrasiMasraf: takipSonrasiMasraf,
        vekaletUcreti: vekaletUcreti,
        asama: durum.tahsilAsamasi,
        tarife: tarife,
      );
}

/// Toplu takip satırı (Excel/CSV'den): borçlu, alacak, temerrüt tarihi.
class TopluTakipSatiri {
  const TopluTakipSatiri({required this.satir, required this.borclu, this.kimlikNo, this.alacak, this.temerrut, this.hatalar = const []});
  final int satir;
  final String borclu;
  final String? kimlikNo;
  final Para? alacak;
  final Tarih? temerrut;
  final List<String> hatalar;
  bool get gecerli => hatalar.isEmpty;
}

class TopluTakip {
  TopluTakip._();

  /// Satırları doğrular: borçlu adı, pozitif alacak, takip tarihinden sonra olmayan temerrüt tarihi; aynı kimlik no tekrarı.
  static List<TopluTakipSatiri> dogrula(List<List<String>> satirlar, Tarih takipTarihi,
      {bool Function(String)? kimlikGecerli}) {
    final sonuc = <TopluTakipSatiri>[];
    final gorulen = <String>{};
    for (var i = 0; i < satirlar.length; i++) {
      final r = [...satirlar[i], '', '', '', ''];
      final hatalar = <String>[];
      final ad = r[0].trim();
      if (ad.isEmpty) hatalar.add('Borçlu adı boş.');
      final no = r[1].trim().isEmpty ? null : r[1].trim();
      if (no != null) {
        if (kimlikGecerli != null && !kimlikGecerli(no)) hatalar.add('Kimlik/vergi no geçersiz.');
        if (!gorulen.add(no)) hatalar.add('Aynı borçlu listede birden fazla.');
      }
      final tutarMetin = r[2].trim().replaceAll(' ', '').replaceAll('TL', '');
      final tutar = double.tryParse(
          tutarMetin.contains(',') ? tutarMetin.replaceAll('.', '').replaceAll(',', '.') : tutarMetin.replaceAll('.', ''));
      if (tutar == null || tutar <= 0) hatalar.add('Alacak tutarı geçersiz.');
      Tarih? temerrut;
      final tm = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{4})$').firstMatch(r[3].trim());
      if (tm == null) {
        hatalar.add('Temerrüt tarihi GG.AA.YYYY biçiminde olmalı.');
      } else {
        try {
          temerrut = Tarih(int.parse(tm[3]!), int.parse(tm[2]!), int.parse(tm[1]!));
          if (temerrut.isAfter(takipTarihi)) hatalar.add('Temerrüt tarihi takip tarihinden sonra olamaz.');
        } on ArgumentError {
          hatalar.add('Temerrüt tarihi geçersiz.');
        }
      }
      sonuc.add(TopluTakipSatiri(
        satir: i + 1,
        borclu: ad,
        kimlikNo: no,
        alacak: tutar == null || tutar <= 0 ? null : Para.tl(tutar),
        temerrut: temerrut,
        hatalar: hatalar,
      ));
    }
    return sonuc;
  }
}
