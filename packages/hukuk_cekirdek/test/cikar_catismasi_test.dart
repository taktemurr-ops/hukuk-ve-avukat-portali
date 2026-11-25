import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  final kisiler = [
    const Kisi(id: 'abc', kiraciId: 'b', tur: KisiTuru.tuzel, ad: 'ABC Gıda San. ve Tic. A.Ş.', kimlikNo: '1234567890'),
    const Kisi(id: 'abcHolding', kiraciId: 'b', tur: KisiTuru.tuzel, ad: 'ABC Holding A.Ş.'),
    const Kisi(id: 'demirci', kiraciId: 'b', tur: KisiTuru.gercek, ad: 'Mehmet Demirci'),
    const Kisi(id: 'gizliKisi', kiraciId: 'b', tur: KisiTuru.tuzel, ad: 'Orman Enerji A.Ş.'),
  ];
  final iliskiler = [
    const KisiIliskisi(kisiA: 'abcHolding', kisiB: 'abc', tur: IliskiTuru.istirak),
  ];
  final kayitlar = [
    const DosyaTarafKaydi(dosyaId: 'd1', dosyaAdi: 'ABC - Tedarik alacağı', kisiId: 'abc', sifat: TarafSifati.muvekkil),
    const DosyaTarafKaydi(
        dosyaId: 'd2', dosyaAdi: 'Demirci işçilik davası', kisiId: 'demirci', sifat: TarafSifati.karsiTaraf),
    const DosyaTarafKaydi(
        dosyaId: 'd3', dosyaAdi: 'Holding birleşme', kisiId: 'abcHolding', sifat: TarafSifati.muvekkil),
    const DosyaTarafKaydi(
        dosyaId: 'd4', dosyaAdi: 'Orman Enerji gizli soruşturma', kisiId: 'gizliKisi', sifat: TarafSifati.muvekkil,
        gizli: true),
  ];
  final tarayici = CikarCatismasiTarayici(kisiler: kisiler, iliskiler: iliskiler, dosyaKayitlari: kayitlar);

  test('Mevcut müvekkile karşı dava almak çatışmadır', () {
    final r = tarayici.tara([const AdayTaraf(ad: 'ABC GIDA SANAYİ TİCARET AŞ', sifat: TarafSifati.karsiTaraf)]);
    expect(r.catismaVar, isTrue);
    expect(r.enYuksekSeviye, RiskSeviyesi.catisma);
    final dogrudan = r.eslesmeler.firstWhere((e) => e.tur == EslesmeTuru.tamIsim);
    expect(dogrudan.dosya?.dosyaId, 'd1');
  });

  test('Kimlik numarasıyla eşleşme isim farklı olsa da bulunur', () {
    final r = tarayici.tara(
        [const AdayTaraf(ad: 'Tamamen Farklı Unvan', kimlikNo: '1234567890', sifat: TarafSifati.karsiTaraf)]);
    expect(r.eslesmeler.first.tur, EslesmeTuru.kimlikNo);
    expect(r.catismaVar, isTrue);
  });

  test('İlişkili şirketin müvekkil olduğu dosya dikkat uyarısı verir', () {
    final r = tarayici.tara([const AdayTaraf(ad: 'ABC Gıda A.Ş.', sifat: TarafSifati.karsiTaraf)]);
    final dolayli = r.eslesmeler.where((e) => e.tur == EslesmeTuru.iliskiliKisi).toList();
    expect(dolayli, hasLength(1));
    expect(dolayli.single.seviye, RiskSeviyesi.dikkat);
    expect(dolayli.single.iliski, IliskiTuru.istirak);
  });

  test('Benzer isimde çatışma dikkat seviyesine iner', () {
    final r = tarayici.tara([const AdayTaraf(ad: 'Mehmet Demir', sifat: TarafSifati.muvekkil)]);
    expect(r.eslesmeler.single.tur, EslesmeTuru.benzerIsim);
    expect(r.eslesmeler.single.seviye, RiskSeviyesi.dikkat);
    expect(r.catismaVar, isFalse);
    expect(r.kararGerekir, isTrue);
  });

  test('Aynı tarafta yer almak yalnızca bilgidir', () {
    final r = tarayici.tara([const AdayTaraf(ad: 'Mehmet Demirci', sifat: TarafSifati.karsiTaraf)]);
    expect(r.eslesmeler.single.seviye, RiskSeviyesi.bilgi);
    expect(r.kararGerekir, isFalse);
  });

  test('Gizli dosyanın adı ve kimliği gösterilmez', () {
    final r = tarayici.tara([const AdayTaraf(ad: 'Orman Enerji', sifat: TarafSifati.karsiTaraf)]);
    final e = r.eslesmeler.single;
    expect(e.dosya?.dosyaId, isNull);
    expect(e.dosya?.dosyaAdi, DosyaOzeti.korumaliAd);
    expect(e.seviye, RiskSeviyesi.catisma);
  });

  test('Eşleşme yoksa rapor boştur', () {
    final r = tarayici.tara([const AdayTaraf(ad: 'Zeytin Turizm', sifat: TarafSifati.muvekkil)]);
    expect(r.eslesmeler, isEmpty);
    expect(r.enYuksekSeviye, isNull);
  });

  group('Karar', () {
    final catismali = tarayici.tara([const AdayTaraf(ad: 'ABC Gıda', sifat: TarafSifati.karsiTaraf)]);

    test('Gerekçe zorunlu', () {
      const k = CikarCatismasiKarari(tur: KararTuru.ret, gerekce: 'kısa', kararVeren: 'a1');
      expect(k.dogrula(catismali), isNotNull);
    });

    test('Çatışmada kabul için farklı kişiden yönetici onayı gerekir', () {
      const onaysiz = CikarCatismasiKarari(
          tur: KararTuru.kosulluKabul, gerekce: 'Müvekkil yazılı muvafakat verdi', kararVeren: 'a1', kosullar: 'Etik duvar');
      expect(onaysiz.dogrula(catismali), contains('yönetici onayı'));

      const kendiOnayi = CikarCatismasiKarari(
          tur: KararTuru.kosulluKabul,
          gerekce: 'Müvekkil yazılı muvafakat verdi',
          kararVeren: 'a1',
          yoneticiOnayi: 'a1',
          kosullar: 'Etik duvar');
      expect(kendiOnayi.dogrula(catismali), isNotNull);

      const gecerli = CikarCatismasiKarari(
          tur: KararTuru.kosulluKabul,
          gerekce: 'Müvekkil yazılı muvafakat verdi',
          kararVeren: 'a1',
          yoneticiOnayi: 'ortak1',
          kosullar: 'Etik duvar');
      expect(gecerli.dogrula(catismali), isNull);
    });

    test('Ret kararı yönetici onayı istemez', () {
      const k = CikarCatismasiKarari(tur: KararTuru.ret, gerekce: 'Mevcut müvekkile karşı iş alınmaz', kararVeren: 'a1');
      expect(k.dogrula(catismali), isNull);
    });
  });
}
