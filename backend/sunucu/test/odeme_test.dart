import 'package:hukuk_sunucu/hukuk_sunucu.dart';
import 'package:test/test.dart';

void main() {
  final s = SahteOdemeSaglayici(kokAdres: Uri.parse('https://api.ornek.test/'), gizli: 'cok-gizli-test-anahtari');
  final ref = rastgeleReferans();

  test('referans 32 onaltılık karakter ve tekil', () {
    expect(ref, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(rastgeleReferans(), isNot(ref));
  });

  test('imzalı bildirim doğrulanır; alan değişirse reddedilir', () {
    final alanlar = {'referans': ref, 'tutar': '180000', 'durum': 'basarili', 'islemNo': 'S-1'};
    alanlar['imza'] = s.imza(ref, '180000', 'basarili', 'S-1');
    final b = s.bildirimDogrula(alanlar, const {})!;
    expect(b.basarili, isTrue);
    expect(b.tutarKurus, 180000);
    expect(b.islemNo, 'S-1');
    expect(s.bildirimDogrula({...alanlar, 'tutar': '1'}, const {}), isNull);
    expect(s.bildirimDogrula({...alanlar, 'durum': 'basarisiz'}, const {}), isNull);
    expect(s.bildirimDogrula({...alanlar, 'imza': ''}, const {}), isNull);
  });

  test('ödeme sayfası yalnızca geçerli referansla açılır', () async {
    expect((s.sayfa('<script>', const {})).statusCode, 404);
    final y = s.sayfa(ref, const {'tutar': '180000', 'aciklama': '<b>x</b>'});
    final html = await y.readAsString();
    expect(html, contains('1800,00 TL'));
    expect(html, isNot(contains('<b>x</b>')));
  });

  test('sabit zamanlı karşılaştırma', () {
    expect(sabitZamanliEsit('abc', 'abc'), isTrue);
    expect(sabitZamanliEsit('abc', 'abd'), isFalse);
    expect(sabitZamanliEsit('abc', 'ab'), isFalse);
  });
}
