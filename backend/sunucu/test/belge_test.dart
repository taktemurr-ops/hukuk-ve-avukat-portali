import 'dart:convert';
import 'dart:io';

import 'package:hukuk_sunucu/hukuk_sunucu.dart';
import 'package:test/test.dart';

void main() {
  group('İçerik türü kontrolü', () {
    test('uzantıyla uyuşan imzalar kabul edilir', () {
      expect(icerikTuruKontrol('pdf', utf8.encode('%PDF-1.7\n...')), isNull);
      expect(icerikTuruKontrol('docx', [0x50, 0x4B, 0x03, 0x04, 0, 0]), isNull);
      expect(icerikTuruKontrol('udf', [0x50, 0x4B, 0x03, 0x04, 1]), isNull);
      expect(icerikTuruKontrol('jpg', [0xFF, 0xD8, 0xFF, 0xE0]), isNull);
      expect(icerikTuruKontrol('heic', [0, 0, 0, 0x18, ...utf8.encode('ftypheic')]), isNull);
      expect(icerikTuruKontrol('txt', utf8.encode('Sayın Mahkeme,')), isNull);
    });

    test('uzantısı değiştirilmiş veya çalıştırılabilir dosya reddedilir', () {
      expect(icerikTuruKontrol('pdf', [0x4D, 0x5A, 0x90, 0x00]), contains('Çalıştırılabilir'));
      expect(icerikTuruKontrol('docx', [0x7F, 0x45, 0x4C, 0x46]), contains('Çalıştırılabilir'));
      expect(icerikTuruKontrol('pdf', utf8.encode('<html>')), contains('uyuşmuyor'));
      expect(icerikTuruKontrol('txt', [0x41, 0x00, 0x42]), contains('uyuşmuyor'));
      expect(icerikTuruKontrol('png', const []), contains('uyuşmuyor'));
    });
  });

  group('Yerel nesne deposu', () {
    late Directory gecici;
    setUp(() async => gecici = await Directory.systemTemp.createTemp('belge_test'));
    tearDown(() async => gecici.delete(recursive: true));

    test('yazar ve okur; anahtar dışına çıkılamaz', () async {
      final d = YerelNesneDeposu(gecici.path);
      const anahtar = '11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222/1';
      await d.yaz(anahtar, [1, 2, 3]);
      expect(await d.oku(anahtar), [1, 2, 3]);
      expect(() => d.yaz('../../etc/passwd', [1]), throwsArgumentError);
      expect(() => d.oku('11111111-1111-1111-1111-111111111111/../x/1'), throwsArgumentError);
    });
  });
}
