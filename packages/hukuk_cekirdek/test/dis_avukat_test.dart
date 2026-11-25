import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  final gun = Tarih(2026, 11, 25);
  const delta = DisAvukat(id: 'da1', buro: 'Kaya Hukuk', sorumluAvukat: 'Av. Deniz Kaya', eposta: 'deniz@kaya.av.tr');
  const ege = DisAvukat(id: 'da2', buro: 'Ege Hukuk', sorumluAvukat: 'Av. Selim Ege', eposta: 'selim@ege.av.tr');

  test('bütçe takibi, aşım engeli, gerekçeli artış, red ve finansa gönderim', () {
    final i = DisAvukatIsi(id: 'i1', disAvukatId: 'da1', konu: 'Ankara iş davaları', ilkButce: Para.tl(100000), baslangic: gun);
    final f1 = i.faturaEkle(id: 'f1', no: 'A-101', tarih: gun, tutar: Para.tl(60000), aciklama: 'Ekim hizmetleri');
    i.faturaOnayla(f1, 'ayse');
    expect(i.kullanimYuzdesi, 60);
    expect(i.butceDurumu, ButceDurumu.normal);
    final f2 = i.faturaEkle(id: 'f2', no: 'A-102', tarih: gun, tutar: Para.tl(25000), aciklama: 'Duruşma');
    i.faturaOnayla(f2, 'ayse');
    expect(i.butceDurumu, ButceDurumu.uyari);
    expect(() => i.faturaEkle(id: 'x', no: 'a-102', tarih: gun, tutar: Para.tl(1), aciklama: ''), throwsStateError);

    final f3 = i.faturaEkle(id: 'f3', no: 'A-103', tarih: gun, tutar: Para.tl(20000), aciklama: 'Bilirkişi itirazı');
    expect(i.bekleyen, Para.tl(20000));
    expect(() => i.faturaOnayla(f3, 'ayse'), throwsStateError);
    expect(() => i.butceArtir(Para.tl(30000), 'kısa', 'ayse', gun), throwsArgumentError);
    i.butceArtir(Para.tl(30000), 'İstinaf aşaması kapsama eklendi', 'ayse', gun);
    expect(i.butce, Para.tl(130000));
    i.faturaOnayla(f3, 'ayse');
    expect(i.harcanan, Para.tl(105000));
    expect(i.kullanimYuzdesi, 81);

    final f4 = i.faturaEkle(id: 'f4', no: 'A-104', tarih: gun, tutar: Para.tl(5000), aciklama: 'Fotokopi');
    expect(() => i.faturaReddet(f4, 'ayse', ''), throwsArgumentError);
    i.faturaReddet(f4, 'ayse', 'Sözleşme kapsamı dışında');
    expect(i.harcanan, Para.tl(105000));
    expect(() => i.finansaGonder(f4), throwsStateError);
    i.finansaGonder(f1);
    expect(f1.durum, FaturaDurumu.finansaGonderildi);
    expect(i.harcanan, Para.tl(105000));

    i.kapali = true;
    expect(() => i.faturaEkle(id: 'f5', no: 'A-105', tarih: gun, tutar: Para.tl(1), aciklama: ''), throwsStateError);
  });

  test('dış avukat özeti harcamaya göre sıralı', () {
    final a = DisAvukatIsi(id: 'a', disAvukatId: 'da1', konu: 'x', ilkButce: Para.tl(50000), baslangic: gun);
    final b = DisAvukatIsi(id: 'b', disAvukatId: 'da2', konu: 'y', ilkButce: Para.tl(80000), baslangic: gun);
    final c = DisAvukatIsi(id: 'c', disAvukatId: 'da2', konu: 'z', ilkButce: Para.tl(20000), baslangic: gun)..kapali = true;
    b.faturaOnayla(b.faturaEkle(id: 'f', no: '1', tarih: gun, tutar: Para.tl(30000), aciklama: ''), 'ayse');
    a.faturaEkle(id: 'g', no: '1', tarih: gun, tutar: Para.tl(10000), aciklama: '');
    final o = DisAvukatOzeti.hesapla([delta, ege], [a, b, c]);
    expect(o.first.avukat.id, 'da2');
    expect(o.first.isSayisi, 2);
    expect(o.first.acikIs, 1);
    expect(o.first.butce, Para.tl(100000));
    expect(o.first.harcanan, Para.tl(30000));
    expect(o.last.bekleyen, Para.tl(10000));
  });
}
