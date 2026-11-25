import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  const politika = OnayPolitikasi(
    hukukEkibi: {'selin', 'can'},
    hukukDirektoru: {'ayse'},
    finans: {'gul'},
    genelMudur: {'ali'},
  );
  Sozlesme s({Para? bedel, TaramaSonucu? tarama}) =>
      Sozlesme(id: 's', no: 'n', baslik: 'b', tur: SozlesmeTuru.hizmet, karsiTaraf: 'k', sorumlu: 'ayse', bedel: bedel, tarama: tarama);

  test('adımlar bedel, risk ve dövize göre belirlenir', () {
    expect(politika.adimlar(s(tarama: const TaramaSonucu())).map((a) => a.kod), ['hukuk']);
    expect(politika.adimlar(s()).map((a) => a.kod), ['hukuk', 'direktor']);
    expect(politika.adimlar(s(bedel: Para.tl(999999.99), tarama: const TaramaSonucu())).map((a) => a.kod), ['hukuk']);
    expect(politika.adimlar(s(bedel: Para.tl(1000000), tarama: const TaramaSonucu())).map((a) => a.kod), ['hukuk', 'finans']);
    expect(politika.adimlar(s(bedel: Para.tl(5000000), tarama: const TaramaSonucu())).map((a) => a.kod),
        ['hukuk', 'finans', 'gm']);
    expect(politika.adimlar(s(bedel: const Para.kurus(100, birim: 'USD'), tarama: const TaramaSonucu())).last.neden,
        'Döviz cinsinden bedel');
    const yuksek = TaramaSonucu(bulgular: [
      TaramaBulgusu(kod: 'x', baslik: 'x', seviye: RiskSeviyesi.yuksek, aciklama: 'x'),
    ]);
    expect(politika.adimlar(s(tarama: yuksek)).map((a) => a.kod), ['hukuk', 'direktor']);
  });

  test('sıralı onay; yetkisiz ve çifte onay engellenir; tamamlanınca onaylandı', () {
    final p = OnaySureci(sozlesmeId: 's', adimlar: politika.adimlar(s(bedel: Para.tl(2000000))), baslatan: 'ayse');
    final t = DateTime.utc(2026, 11, 25);
    expect(p.siradaki!.kod, 'hukuk');
    expect(p.onaylayabilir('gul'), isFalse);
    expect(() => p.karar('gul', OnayKarariTuru.onay, t), throwsStateError);
    p.karar('selin', OnayKarariTuru.onay, t);
    expect(p.siradaki!.kod, 'direktor');
    p.karar('ayse', OnayKarariTuru.onay, t);
    expect(p.siradaki!.kod, 'finans');
    expect(p.durum, OnaySurecDurumu.devam);
    p.karar('gul', OnayKarariTuru.onay, t);
    expect(p.durum, OnaySurecDurumu.onaylandi);
    expect(p.siradaki, isNull);
    expect(() => p.karar('gul', OnayKarariTuru.onay, t), throwsStateError);
  });

  test('aynı kişi iki adımı onaylayamaz; ret gerekçe ister ve süreci bitirir', () {
    const pol = OnayPolitikasi(hukukEkibi: {'ayse', 'selin'}, hukukDirektoru: {'ayse'}, finans: {}, genelMudur: {});
    final p = OnaySureci(sozlesmeId: 's', adimlar: pol.adimlar(s()), baslatan: 'ayse');
    final t = DateTime.utc(2026, 11, 25);
    p.karar('ayse', OnayKarariTuru.onay, t);
    expect(p.onaylayabilir('ayse'), isFalse);
    expect(() => p.karar('ayse', OnayKarariTuru.onay, t), throwsStateError);
    expect(() => p.karar('ayse', OnayKarariTuru.ret, t), throwsStateError);

    final r = OnaySureci(sozlesmeId: 's', adimlar: pol.adimlar(s()), baslatan: 'ayse');
    expect(() => r.karar('selin', OnayKarariTuru.revizyon, t), throwsArgumentError);
    r.karar('selin', OnayKarariTuru.revizyon, t, not: 'Cezai şart oranı düşürülsün');
    expect(r.durum, OnaySurecDurumu.revizyon);
    expect(r.siradaki, isNull);
  });
}
