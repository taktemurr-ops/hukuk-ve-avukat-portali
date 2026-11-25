import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  group('Etik duvar', () {
    final gun = Tarih(2026, 11, 25);

    test('kurulur, yetki denetçisi en yetkili rolü bile engeller, kaldırma kayıt altına alınır', () {
      final d = EtikDuvarDefteri();
      expect(
          () => d.kur(dosyaId: 'd1', kullanici: 'mert', gerekce: 'kısa', kuran: 'ayse', tarih: gun, dosyaEkibi: {}),
          throwsArgumentError);
      expect(
          () => d.kur(
              dosyaId: 'd1', kullanici: 'mert', gerekce: 'Karşı tarafı önceki büroda temsil etti', kuran: 'ayse', tarih: gun,
              dosyaEkibi: {'mert'}),
          throwsStateError);
      expect(
          () => d.kur(
              dosyaId: 'd1', kullanici: 'ayse', gerekce: 'Karşı tarafı önceki büroda temsil etti', kuran: 'ayse', tarih: gun,
              dosyaEkibi: {}),
          throwsArgumentError);
      d.kur(
          dosyaId: 'd1', kullanici: 'mert', gerekce: 'Karşı tarafı önceki büroda temsil etti', kuran: 'ayse', tarih: gun,
          dosyaEkibi: {'ayse'});
      expect(d.engelliler('d1'), {'mert'});
      expect(
          () => d.kur(
              dosyaId: 'd1', kullanici: 'mert', gerekce: 'Karşı tarafı önceki büroda temsil etti', kuran: 'ayse', tarih: gun,
              dosyaEkibi: {}),
          throwsStateError);

      const mert = Aktor(kullaniciId: 'mert', kiraciId: 'k', roller: {Rol.yoneticiOrtak});
      final nesne = KorunanNesne(kiraciId: 'k', etikDuvar: d.engelliler('d1'));
      expect(const YetkiDenetcisi().karar(mert, Islem.goruntule, nesne).neden, 'Etik duvar');

      expect(() => d.kaldir(dosyaId: 'd1', kullanici: 'mert', gerekce: 'x', kaldiran: 'ayse', tarih: gun),
          throwsArgumentError);
      d.kaldir(dosyaId: 'd1', kullanici: 'mert', gerekce: 'Çatışma sona erdi, müvekkil onayı alındı', kaldiran: 'ayse', tarih: gun);
      expect(d.engelliler('d1'), isEmpty);
      expect(d.gecmis('d1').single.kaldirmaGerekcesi, 'Çatışma sona erdi, müvekkil onayı alındı');
      expect(() => d.kaldir(dosyaId: 'd1', kullanici: 'mert', gerekce: 'Tekrar kaldırma denemesi', kaldiran: 'ayse', tarih: gun),
          throwsStateError);
    });
  });

  group('Bildirim kutusu', () {
    final t = DateTime.utc(2026, 11, 25, 9);
    Bildirim b(String id, BildirimOnceligi o, int saat) => Bildirim(
        id: id, tur: BildirimTuru.sure, oncelik: o, baslik: id, aciklama: '', zaman: t.add(Duration(hours: saat)));

    test('okunmamış önce, sonra öncelik, sonra yeni olan', () {
      final k = BildirimKutusu();
      final l = [
        b('a', BildirimOnceligi.bilgi, 3),
        b('b', BildirimOnceligi.kritik, 1),
        b('c', BildirimOnceligi.kritik, 2),
        b('d', BildirimOnceligi.uyari, 5),
      ];
      expect(k.sirala(l).map((x) => x.id), ['c', 'b', 'd', 'a']);
      k.oku('c');
      expect(k.sirala(l).map((x) => x.id), ['b', 'd', 'a', 'c']);
      expect(k.okunmamis(l), 3);
      k.tumunuOku(l);
      expect(k.okunmamis(l), 0);
    });

    test('anlık bildirim metni kişisel veri içermez', () {
      expect(Bildirim.anlikBildirimMetni.contains(RegExp(r'\d')), isFalse);
    });
  });
}
