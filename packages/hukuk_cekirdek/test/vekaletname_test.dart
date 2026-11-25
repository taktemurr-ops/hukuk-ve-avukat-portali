import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  final genel = Vekaletname(
    id: 'v1',
    kiraciId: 'b',
    muvekkilId: 'm1',
    avukatlar: const {'av1'},
    duzenlemeTarihi: Tarih(2026, 1, 10),
    noter: 'Kadıköy 5. Noterliği',
    yevmiyeNo: '01234',
    ozelYetkiler: const {OzelYetki.sulh, OzelYetki.tevkil, OzelYetki.ahzuKabz},
  );

  VekaletKontrolSonucu kontrol({
    String avukat = 'av1',
    String dosya = 'd1',
    OzelYetki? yetki,
    Tarih? tarih,
    List<Vekaletname>? liste,
    List<AltVekalet> alt = const [],
  }) =>
      VekaletKontrolu.kontrolEt(
        vekaletnameler: liste ?? [genel],
        altVekaletler: alt,
        muvekkilId: 'm1',
        avukatId: avukat,
        dosyaId: dosya,
        tarih: tarih ?? Tarih(2026, 11, 25),
        gerekenYetki: yetki,
      );

  test('Genel vekâletle sıradan işlem yapılabilir', () {
    expect(kontrol().uygun, isTrue);
  });

  test('Özel yetki yoksa feragat engellenir, sulh serbest', () {
    final feragat = kontrol(yetki: OzelYetki.feragat);
    expect(feragat.uygun, isFalse);
    expect(feragat.neden, contains('Davadan feragat'));
    expect(kontrol(yetki: OzelYetki.sulh).uygun, isTrue);
  });

  test('Vekil olmayan avukat işlem yapamaz', () {
    expect(kontrol(avukat: 'av2').uygun, isFalse);
  });

  test('Azledilen vekâletle işlem yapılamaz', () {
    final azil = genel.durumuDegistir(VekaletDurumu.azil, Tarih(2026, 6, 1));
    final s = kontrol(liste: [azil]);
    expect(s.uygun, isFalse);
    expect(s.neden, contains('azledilmiş'));
  });

  test('Özel vekâlet yalnızca kapsadığı dosyada geçerlidir', () {
    final ozel = Vekaletname(
      id: 'v2',
      kiraciId: 'b',
      muvekkilId: 'm1',
      avukatlar: const {'av1'},
      duzenlemeTarihi: Tarih(2026, 1, 10),
      genel: false,
      dosyalar: const {'d7'},
    );
    expect(kontrol(liste: [ozel], dosya: 'd7').uygun, isTrue);
    expect(kontrol(liste: [ozel], dosya: 'd1').uygun, isFalse);
  });

  test('Vekâletname tarihinden önceki işlem uygun değil', () {
    expect(kontrol(tarih: Tarih(2025, 12, 1)).uygun, isFalse);
  });

  group('Yetki belgesi (tevkil)', () {
    test('Tevkil yetkisiyle alt vekil yetkilendirilir', () {
      final alt = VekaletKontrolu.yetkiBelgesiVer(
        vekaletname: genel,
        verenAvukat: 'av1',
        alanAvukat: 'av2',
        tarih: Tarih(2026, 3, 1),
        dosyalar: const {'d1'},
        devredilenYetkiler: const {OzelYetki.ahzuKabz},
      );
      expect(kontrol(avukat: 'av2', alt: [alt]).uygun, isTrue);
      expect(kontrol(avukat: 'av2', alt: [alt], dosya: 'd9').uygun, isFalse);
      expect(kontrol(avukat: 'av2', alt: [alt], yetki: OzelYetki.ahzuKabz).uygun, isTrue);
      expect(kontrol(avukat: 'av2', alt: [alt], yetki: OzelYetki.sulh).uygun, isFalse);
    });

    test('Sahip olunmayan yetki devredilemez', () {
      expect(
        () => VekaletKontrolu.yetkiBelgesiVer(
          vekaletname: genel,
          verenAvukat: 'av1',
          alanAvukat: 'av2',
          tarih: Tarih(2026, 3, 1),
          devredilenYetkiler: const {OzelYetki.feragat},
        ),
        throwsStateError,
      );
    });

    test('Tevkil yetkisi olmayan vekâletnameyle yetki belgesi verilemez', () {
      final tevkilsiz = Vekaletname(
        id: 'v3',
        kiraciId: 'b',
        muvekkilId: 'm1',
        avukatlar: const {'av1'},
        duzenlemeTarihi: Tarih(2026, 1, 10),
      );
      expect(
        () => VekaletKontrolu.yetkiBelgesiVer(
            vekaletname: tevkilsiz, verenAvukat: 'av1', alanAvukat: 'av2', tarih: Tarih(2026, 3, 1)),
        throwsStateError,
      );
    });
  });
}
