import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  final bugun = Tarih(2026, 11, 25);
  final tarife = SaatlikUcretTarifesi(
    kullanici: {'ece': Para.tl(3000), 'mert': Para.tl(2000)},
    dosyaOzel: {
      'd1': {'ece': Para.tl(2500)},
    },
    varsayilan: Para.tl(1500),
  );

  ZamanDefteri defter() {
    final z = ZamanDefteri(tarife: tarife);
    z.ekle(kullanici: 'ece', dosyaId: 'd1', tarih: bugun, dakika: 47, aciklama: 'Cevap dilekçesi taslağı', bugun: bugun);
    z.ekle(kullanici: 'ece', dosyaId: 'd2', tarih: bugun, dakika: 30, aciklama: 'Müvekkil görüşmesi', bugun: bugun);
    z.ekle(kullanici: 'mert', dosyaId: 'd1', tarih: bugun.gunEkle(-1), dakika: 61, aciklama: 'Duruşmaya katılım', bugun: bugun);
    z.ekle(
        kullanici: 'elif',
        dosyaId: 'd1',
        tarih: bugun,
        dakika: 20,
        aciklama: 'Dosya fotokopisi',
        bugun: bugun,
        faturalanabilir: false);
    return z;
  }

  test('ücret dosyaya özel tarifeden gelir; süre 6 dakikaya yukarı yuvarlanır', () {
    final z = defter();
    final k = z.kayitlar;
    expect(k[0].saatlikUcret, Para.tl(2500));
    expect(k[0].faturaDakikasi(), 48);
    expect(k[0].tutar(), Para.tl(2000));
    expect(k[1].tutar(), Para.tl(1500));
    expect(k[2].faturaDakikasi(), 66);
    expect(k[2].tutar(), Para.tl(2200));
    expect(k[3].saatlikUcret, Para.tl(1500));
    expect(k[3].tutar(), Para.sifir);
  });

  test('kayıt kuralları', () {
    final z = defter();
    expect(
        () => z.ekle(kullanici: 'ece', dosyaId: 'd1', tarih: bugun.gunEkle(1), dakika: 10, aciklama: 'İleri tarih', bugun: bugun),
        throwsArgumentError);
    expect(() => z.ekle(kullanici: 'ece', dosyaId: 'd1', tarih: bugun, dakika: 0, aciklama: 'Sıfır süre', bugun: bugun),
        throwsArgumentError);
    expect(() => z.ekle(kullanici: 'ece', dosyaId: 'd1', tarih: bugun, dakika: 10, aciklama: 'abc', bugun: bugun),
        throwsArgumentError);
    expect(
        () => z.ekle(kullanici: 'ece', dosyaId: 'd1', tarih: bugun, dakika: 1400, aciklama: 'Çok uzun gün', bugun: bugun),
        throwsArgumentError);
  });

  test('onay, fatura taslağı ve kesinleştirme', () {
    final z = defter();
    expect(() => z.onayla('z1', 'ece'), throwsStateError);
    z
      ..onayla('z1', 'mert')
      ..onayla('z3', 'ece')
      ..onayla('z4', 'ece');
    expect(() => z.onayla('z1', 'mert'), throwsStateError);

    final onizleme = z.faturaTaslagi('d1', yil: 2026);
    expect(onizleme.no, 'ZF-2026-0001');
    expect(onizleme.kalemler.map((k) => k.kayit.id), ['z3', 'z1']);
    expect(onizleme.toplam, Para.tl(4200));
    expect(onizleme.toplamDakika, 114);
    expect(z.kayit('z1')!.durum, ZamanDurumu.onaylandi);

    z.faturaTaslagi('d1', yil: 2026, kesinlestir: true);
    expect(z.kayit('z1')!.durum, ZamanDurumu.faturalandi);
    expect(z.kayit('z1')!.faturaNo, 'ZF-2026-0001');
    expect(z.kayit('z4')!.durum, ZamanDurumu.onaylandi);
    expect(() => z.faturaTaslagi('d1', yil: 2026, kesinlestir: true), throwsStateError);
    expect(() => z.sil('z1'), throwsStateError);
    z.sil('z2');
    expect(z.kayitlar, hasLength(3));
  });

  test('kullanıcı özeti', () {
    final o = defter().kullaniciOzeti(bugun.gunEkle(-7), bugun);
    expect(o['ece'], (77, 78));
    expect(o['mert'], (61, 66));
    expect(o['elif'], (20, 0));
  });

  test('kronometre duraklatılır ve dakikaya yukarı yuvarlanır', () {
    final t0 = DateTime.utc(2026, 11, 25, 9);
    final k = Kronometre()..baslat(t0);
    expect(k.calisiyor, isTrue);
    k
      ..duraklat(t0.add(const Duration(minutes: 10)))
      ..baslat(t0.add(const Duration(minutes: 20)));
    expect(k.gecen(t0.add(const Duration(minutes: 21))), const Duration(minutes: 11));
    expect(k.bitir(t0.add(const Duration(minutes: 25, seconds: 30))), 16);
    expect(k.calisiyor, isFalse);
    expect(k.bitir(t0), 1);
  });

  test('gelir paylaşımı: getiren, çalışanlar dakika oranında, kuruş farkı büroya', () {
    final d = GelirPaylasimi.dagit(
      tahsilat: Para.tl(10000),
      getiren: 'ali',
      calisanDakikalari: {'ece': 47, 'mert': 61, 'elif': 20},
    );
    expect(d['ali'], Para.kurus(200000));
    expect(d['ece'], Para.kurus(183593));
    expect(d['mert'], Para.kurus(238281));
    expect(d['elif'], Para.kurus(78125));
    expect(d[GelirPaylasimi.buroHesabi], Para.kurus(300001));
    expect(d.values.fold(Para.sifir, (a, b) => a + b), Para.tl(10000));

    final kimseYok = GelirPaylasimi.dagit(tahsilat: Para.tl(100), getiren: 'ali', calisanDakikalari: {});
    expect(kimseYok[GelirPaylasimi.buroHesabi], Para.tl(80));
    expect(
        () => GelirPaylasimi.dagit(
            tahsilat: Para.tl(1),
            getiren: 'a',
            calisanDakikalari: {},
            kural: const PaylasimKurali(getiren: 20, calisan: 50, buro: 40)),
        throwsArgumentError);
  });
}
