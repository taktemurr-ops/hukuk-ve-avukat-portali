import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  const denetci = YetkiDenetcisi();
  const dosya = KorunanNesne(kiraciId: 'buro1', atananKullanicilar: {'avukat1', 'muvekkil1'});

  const sahip = Aktor(kullaniciId: 'sahip', kiraciId: 'buro1', roller: {Rol.buroSahibi});
  const avukat = Aktor(kullaniciId: 'avukat1', kiraciId: 'buro1', roller: {Rol.avukat});
  const stajyer = Aktor(kullaniciId: 'stajyer1', kiraciId: 'buro1', roller: {Rol.stajyer});
  const muvekkil = Aktor(kullaniciId: 'muvekkil1', kiraciId: 'buro1', roller: {Rol.muvekkil});
  const baskaMuvekkil = Aktor(kullaniciId: 'muvekkil2', kiraciId: 'buro1', roller: {Rol.muvekkil});

  test('Farklı müşteri ortamındaki kullanıcı hiçbir şey göremez', () {
    const yabanci = Aktor(kullaniciId: 'x', kiraciId: 'buro2', roller: {Rol.buroSahibi});
    expect(denetci.izinVarMi(yabanci, Islem.goruntule, dosya), isFalse);
  });

  test('Aktif olmayan (ayrılan) kullanıcı erişemez', () {
    const ayrilan = Aktor(kullaniciId: 'avukat1', kiraciId: 'buro1', roller: {Rol.avukat}, aktif: false);
    expect(denetci.izinVarMi(ayrilan, Islem.goruntule, dosya), isFalse);
  });

  test('Etik duvar büro sahibini bile engeller', () {
    const duvarli = KorunanNesne(kiraciId: 'buro1', etikDuvar: {'sahip'});
    final k = denetci.karar(sahip, Islem.goruntule, duvarli);
    expect(k.izin, isFalse);
    expect(k.neden, 'Etik duvar');
  });

  test('Müvekkil yalnızca kendisine atanan dosyayı görür', () {
    expect(denetci.izinVarMi(muvekkil, Islem.goruntule, dosya), isTrue);
    expect(denetci.izinVarMi(baskaMuvekkil, Islem.goruntule, dosya), isFalse);
    expect(denetci.izinVarMi(muvekkil, Islem.duzenle, dosya), isFalse);
  });

  test('Stajyer süre teyit edemez ve imza atamaz', () {
    expect(denetci.izinVarMi(stajyer, Islem.duzenle, dosya), isTrue);
    expect(denetci.izinVarMi(stajyer, Islem.sureTeyitEt, dosya), isFalse);
    expect(denetci.izinVarMi(stajyer, Islem.imzala, dosya), isFalse);
    expect(denetci.izinVarMi(avukat, Islem.sureTeyitEt, dosya), isTrue);
  });

  test('Gizli dosyayı yalnızca ekip ve yöneticiler görür', () {
    const gizli = KorunanNesne(kiraciId: 'buro1', gizli: true, atananKullanicilar: {'avukat1'});
    const digerAvukat = Aktor(kullaniciId: 'avukat2', kiraciId: 'buro1', roller: {Rol.avukat});
    expect(denetci.izinVarMi(avukat, Islem.goruntule, gizli), isTrue);
    expect(denetci.izinVarMi(digerAvukat, Islem.goruntule, gizli), isFalse);
    expect(denetci.izinVarMi(sahip, Islem.goruntule, gizli), isTrue);
  });

  test('Riskli işlem ikinci onay ister', () {
    final silme = denetci.karar(sahip, Islem.sil, dosya);
    expect(silme.izin, isTrue);
    expect(silme.ikinciOnayGerekir, isTrue);
    expect(denetci.karar(sahip, Islem.goruntule, dosya).ikinciOnayGerekir, isFalse);
  });

  test('Liste ve aramada görülemeyen nesne sonuçtan çıkar', () {
    final dosyalar = <String, KorunanNesne>{
      'acik': dosya,
      'duvarli': const KorunanNesne(kiraciId: 'buro1', etikDuvar: {'avukat1'}),
      'baskaBuro': const KorunanNesne(kiraciId: 'buro2'),
    };
    final gorunen = denetci.gorunurOlanlar(avukat, dosyalar.keys, (k) => dosyalar[k]!);
    expect(gorunen.toList(), ['acik']);
  });
}
