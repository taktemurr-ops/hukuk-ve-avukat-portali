import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  const holding = Sirket(id: 'h', unvan: 'ABC Holding A.Ş.');
  const gida = Sirket(id: 'g', unvan: 'ABC Gıda A.Ş.', anaSirketId: 'h', vkn: '1234567890');
  const lojistik = Sirket(id: 'l', unvan: 'ABC Lojistik A.Ş.', anaSirketId: 'g');
  const dis = Sirket(id: 'd', unvan: 'ABC Dış Ticaret A.Ş.', anaSirketId: 'h');

  test('ağaç, kapsam, derinlik ve yetki kapsamı', () {
    final g = GrupYapisi([lojistik, dis, gida, holding]);
    expect(g.kokler.map((s) => s.id), ['h']);
    expect(g.altlar('h').map((s) => s.id), ['d', 'g']);
    expect(g.kapsam('h'), {'h', 'g', 'l', 'd'});
    expect(g.kapsam('g'), {'g', 'l'});
    expect(g.derinlik('l'), 2);
    expect(g.agacSirasi().map((e) => '${e.$1.id}${e.$2}'), ['h0', 'd1', 'g1', 'l2']);
    expect(g.yetkiKapsami(['g', 'd']), {'g', 'l', 'd'});
  });

  test('bilinmeyen ana şirket, döngü ve mükerrer VKN reddedilir', () {
    expect(() => GrupYapisi([lojistik]), throwsArgumentError);
    expect(
        () => GrupYapisi(const [
              Sirket(id: 'a', unvan: 'A', anaSirketId: 'b'),
              Sirket(id: 'b', unvan: 'B', anaSirketId: 'a'),
            ]),
        throwsArgumentError);
    final g = GrupYapisi([holding, gida]);
    expect(() => g.ekle(const Sirket(id: 'x', unvan: 'X', vkn: '1234567890')), throwsArgumentError);
    expect(g.ekle(lojistik).kapsam('g'), {'g', 'l'});
  });
}
