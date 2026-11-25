import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  test('Her hesap türünün varsayılan profili var', () {
    for (final tur in HesapTuru.values) {
      expect(LisansProfili.varsayilan(tur).hesapTuru, tur);
    }
  });

  test('Hukuk Bürosu, Avukatlık Bürosu modüllerinin hepsini içerir', () {
    expect(
      LisansProfili.hukukBurosu.moduller.containsAll(LisansProfili.avukatlikBurosu.moduller),
      isTrue,
    );
  });

  test('Ekip modülleri yalnızca Hukuk Bürosu paketinde', () {
    expect(LisansProfili.avukatlikBurosu.modulAcik(Modul.etikDuvar), isFalse);
    expect(LisansProfili.hukukBurosu.modulAcik(Modul.etikDuvar), isTrue);
  });

  test('Kurumsal pakette sözleşme yönetimi ve iç talepler açık', () {
    expect(LisansProfili.kurumsal.modulAcik(Modul.sozlesmeYonetimi), isTrue);
    expect(LisansProfili.kurumsal.modulAcik(Modul.icTalepler), isTrue);
    expect(LisansProfili.kurumsal.roller, contains(Rol.talepEden));
  });
}
