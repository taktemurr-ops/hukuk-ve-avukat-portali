import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

Dosya _dosya(String id, {String? esas, String? mahkeme, DosyaAsamasi asama = DosyaAsamasi.ilkDerece}) => Dosya(
      id: id,
      kiraciId: 'b',
      icNo: '2026/0001',
      tur: DosyaTuru.hukuk,
      baslik: 'Dosya $id',
      sorumlu: 'a1',
      acilisTarihi: Tarih(2026, 1, 1),
      esasNo: esas,
      mahkeme: mahkeme,
      asama: asama,
    );

Tebligat _tebligat({String? esas, String gonderen = 'İSTANBUL 5. ASLİYE TİCARET MAHKEMESİ', List<String> taraflar = const [], String? ozet, TebligatKanali kanal = TebligatKanali.uyap}) =>
    Tebligat(
      id: 't1',
      kiraciId: 'b',
      kanal: kanal,
      ulasmaTarihi: Tarih(2026, 11, 25),
      gonderen: gonderen,
      konu: 'Gerekçeli karar',
      esasNo: esas,
      taraflar: taraflar,
      belgeOzeti: ozet,
    );

void main() {
  group('Dosya', () {
    test('Yedek sorumlu asılla aynı olamaz', () {
      expect(
        () => Dosya(
            id: 'x',
            kiraciId: 'b',
            icNo: '1',
            tur: DosyaTuru.icra,
            baslik: 'x',
            sorumlu: 'a1',
            yedekSorumlu: 'a1',
            acilisTarihi: Tarih(2026, 1, 1)),
        throwsArgumentError,
      );
    });

    test('Numara serisi sıralı ve sıfır dolgulu', () {
      final seri = NumaraSerisi(yil: 2026);
      expect(seri.sonraki(), '2026/0001');
      expect(seri.sonraki(), '2026/0002');
      expect(NumaraSerisi(yil: 2027, onek: 'İC-', sonNumara: 41).sonraki(), 'İC-2027/0042');
    });

    test('Esas numarası normalleştirme', () {
      expect(esasNoNormallestir('2026/0123 E.'), '2026/123');
      expect(esasNoNormallestir('2026 / 123'), '2026/123');
    });
  });

  group('Tebligat', () {
    test('Elektronik kanalda tebliğ ulaşmayı izleyen 5. gündür, fizikide aynı gün', () {
      expect(_tebligat(kanal: TebligatKanali.uets).tebligTarihi, Tarih(2026, 11, 30));
      expect(_tebligat(kanal: TebligatKanali.fiziki).tebligTarihi, Tarih(2026, 11, 25));
    });

    test('Aynı belge özeti aynı tekillik anahtarını üretir', () {
      expect(_tebligat(ozet: 'abc123').tekillikAnahtari, _tebligat(ozet: 'abc123').tekillikAnahtari);
      expect(_tebligat().tekillikAnahtari, _tebligat().tekillikAnahtari);
      expect(_tebligat(gonderen: 'Ankara 1. İş Mahkemesi').tekillikAnahtari, isNot(_tebligat().tekillikAnahtari));
    });

    final dosyalar = [
      _dosya('d1', esas: '2026/123 E.', mahkeme: 'İstanbul 5. Asliye Ticaret Mahkemesi'),
      _dosya('d2', esas: '2025/88 E.', mahkeme: 'Ankara 3. İş Mahkemesi'),
      _dosya('d3', esas: '2026/123 E.', mahkeme: 'İzmir 1. Asliye Hukuk', asama: DosyaAsamasi.kapandi),
    ];

    test('Esas no ve mahkeme aynıysa tek yüksek öneri otomatik eşleşir', () {
      final oneriler = TebligatEslestirici.oner(_tebligat(esas: '2026/123'), dosyalar);
      expect(oneriler.first.dosya.id, 'd1');
      expect(oneriler.first.puan, 1.0);
      expect(TebligatEslestirici.otomatikEslesme(oneriler)?.id, 'd1');
    });

    test('Kapalı dosya önerilmez', () {
      final oneriler = TebligatEslestirici.oner(_tebligat(esas: '2026/123', gonderen: 'İzmir 1. Asliye Hukuk'), dosyalar);
      expect(oneriler.map((o) => o.dosya.id), ['d1']);
      expect(oneriler.single.puan, 0.8);
      expect(TebligatEslestirici.otomatikEslesme(oneriler), isNull);
    });

    test('Yalnızca taraf adı eşleşirse öneri düşük güvenle kuyruğa düşer', () {
      final oneriler = TebligatEslestirici.oner(
        _tebligat(gonderen: 'Ankara 3. İş Mahkemesi', taraflar: ['ABC Gıda A.Ş.']),
        dosyalar,
        dosyaTaraflari: {
          'd2': ['ABC Gıda Sanayi ve Ticaret A.Ş.'],
        },
      );
      expect(oneriler.single.dosya.id, 'd2');
      expect(oneriler.single.puan, 0.5);
      expect(TebligatEslestirici.otomatikEslesme(oneriler), isNull);
    });

    test('Dosyaya bağlanınca durum eşleşti olur', () {
      final t = _tebligat().dosyayaBagla('d1');
      expect(t.dosyaId, 'd1');
      expect(t.eslesmeDurumu, EslesmeDurumu.eslesti);
      expect(t.tebligTarihi, Tarih(2026, 11, 30));
    });
  });
}
