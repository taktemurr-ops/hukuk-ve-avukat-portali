import 'dart:convert';
import 'dart:math';

import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  group('TOTP (RFC 6238 test vektörleri)', () {
    final sir = utf8.encode('12345678901234567890');
    DateTime t(int saniye) => DateTime.fromMillisecondsSinceEpoch(saniye * 1000, isUtc: true);

    test('8 haneli resmi test vektörleri', () {
      final beklenen = {
        59: '94287082',
        1111111109: '07081804',
        1111111111: '14050471',
        1234567890: '89005924',
        2000000000: '69279037',
        20000000000: '65353130',
      };
      beklenen.forEach((saniye, kod) => expect(Totp.kod(sir, t(saniye), hane: 8), kod, reason: '$saniye'));
    });

    test('6 haneli kod ve doğrulama penceresi', () {
      expect(Totp.kod(sir, t(59)), '287082');
      expect(Totp.dogrula(sir, '287082', t(59)), isTrue);
      expect(Totp.dogrula(sir, '287 082', t(80)), isTrue, reason: 'bir sonraki adımda da kabul');
      expect(Totp.dogrula(sir, '287082', t(200)), isFalse);
      expect(Totp.dogrula(sir, 'abc', t(59)), isFalse);
    });

    test('Base32 (RFC 4648)', () {
      expect(Totp.base32Kodla(sir), 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
      expect(Totp.base32Kodla(utf8.encode('f')), 'MY');
      expect(Totp.base32Kodla(utf8.encode('foobar')), 'MZXW6YTBOI');
      expect(Totp.base32Coz('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'), sir);
      expect(() => Totp.base32Coz('1!'), throwsFormatException);
    });

    test('Sır üretimi ve otpauth bağlantısı', () {
      final s = Totp.sirUret(Random(1));
      expect(s, hasLength(20));
      final uri = Totp.otpauthUri(yayinci: 'Hukuk Portalı', hesap: 'ayse@buro.com.tr', sir: s);
      expect(uri, startsWith('otpauth://totp/'));
      expect(uri, contains('secret=${Totp.base32Kodla(s)}'));
    });
  });

  group('Denetim kaydı', () {
    DenetimKaydi doldur() {
      final k = DenetimKaydi();
      final z = DateTime.utc(2026, 11, 25, 9);
      k.ekle(kiraciId: 'b', kullaniciId: 'a1', islem: DenetimIslemi.girisBasarili, nesneTuru: 'oturum', nesneId: '-', zaman: z);
      k.ekle(kiraciId: 'b', kullaniciId: 'a1', islem: DenetimIslemi.goruntuleme, nesneTuru: 'dosya', nesneId: 'd1', zaman: z);
      k.ekle(kiraciId: 'b', kullaniciId: 'a1', islem: DenetimIslemi.indirme, nesneTuru: 'belge', nesneId: 'b1', zaman: z);
      return k;
    }

    test('Zincir sağlam; her olay öncekinin özetini taşır', () {
      final k = doldur();
      expect(k.dogrula(), isNull);
      expect(k.olaylar.first.oncekiOzet, DenetimOlayi.baslangicOzeti);
      expect(k.olaylar[1].oncekiOzet, k.olaylar[0].ozet);
    });

    test('Bir kayıt değiştirilirse veya silinirse zincir kırılır', () {
      final o = doldur().olaylar;
      final degismis = [
        o[0],
        DenetimOlayi(
          sira: o[1].sira,
          zaman: o[1].zaman,
          kiraciId: o[1].kiraciId,
          kullaniciId: 'baskasi',
          islem: o[1].islem,
          nesneTuru: o[1].nesneTuru,
          nesneId: o[1].nesneId,
          aciklama: o[1].aciklama,
          oncekiOzet: o[1].oncekiOzet,
          ozet: o[1].ozet,
        ),
        o[2],
      ];
      expect(DenetimKaydi.zinciriDogrula(degismis), 2);
      expect(DenetimKaydi.zinciriDogrula([o[0], o[2]]), 2);
    });
  });

  group('Davet', () {
    final simdi = DateTime.utc(2026, 11, 25, 10);
    Davet davet({Set<Rol> roller = const {Rol.avukat}}) => Davet(
          kod: Davet.kodUret(Random(3)),
          kiraciId: 'b',
          eposta: 'Mert@Buro.com.tr',
          roller: roller,
          davetEden: 'a1',
          olusturma: simdi,
        );

    test('Davet doğru e-postayla 72 saat içinde bir kez kullanılır', () {
      final d = davet();
      expect(d.kod, hasLength(32));
      final kabul = d.kabulEt(eposta: 'mert@buro.com.tr', simdi: simdi.add(const Duration(hours: 1)));
      expect(kabul.kullanildi, isTrue);
      expect(() => kabul.kabulEt(eposta: 'mert@buro.com.tr', simdi: simdi), throwsStateError);
      expect(() => d.kabulEt(eposta: 'baska@buro.com.tr', simdi: simdi), throwsStateError);
      expect(() => d.kabulEt(eposta: 'mert@buro.com.tr', simdi: simdi.add(const Duration(hours: 73))), throwsStateError);
    });

    test('Koltuk kontrolü; ücretsiz roller koltuk tüketmez', () {
      expect(koltukKontrolu(lisansKoltugu: 5, koltukKullananAktifKullanici: 4, koltukTuketenBekleyenDavet: 0, yeniRoller: {Rol.avukat}),
          isNull);
      expect(koltukKontrolu(lisansKoltugu: 5, koltukKullananAktifKullanici: 4, koltukTuketenBekleyenDavet: 1, yeniRoller: {Rol.avukat}),
          contains('dolu'));
      expect(
          koltukKontrolu(lisansKoltugu: 5, koltukKullananAktifKullanici: 5, koltukTuketenBekleyenDavet: 0, yeniRoller: {Rol.talepEden}),
          isNull);
      expect(davet(roller: {Rol.muvekkil}).koltukTuketir(), isFalse);
      expect(davet().koltukTuketir(), isTrue);
    });
  });
}
