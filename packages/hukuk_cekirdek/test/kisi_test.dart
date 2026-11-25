import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

Kisi _kisi(String id, String ad, {String? no, KisiTuru tur = KisiTuru.tuzel, String? eposta}) =>
    Kisi(id: id, kiraciId: 'buro1', tur: tur, ad: ad, kimlikNo: no, eposta: eposta);

void main() {
  group('İsim eşleştirme', () {
    test('Türkçe karakter, büyük harf ve şirket ekleri yok sayılır', () {
      expect(IsimEslestirme.normallestir('ABC Gıda Sanayi ve Ticaret A.Ş.'), 'abc gida');
      expect(IsimEslestirme.normallestir('ABC GIDA SAN. TİC. AŞ'), 'abc gida');
      expect(IsimEslestirme.normallestir('Delta İnşaat Ltd. Şti.'), 'delta insaat');
      expect(IsimEslestirme.benzerlik('Ayşe Yılmaz', 'AYŞE YILMAZ'), 1);
    });

    test('Sözcük sırası önemsiz', () {
      expect(IsimEslestirme.benzerlik('Yılmaz Ayşe', 'Ayşe Yılmaz'), 1);
    });

    test('Benzer ve farklı isimler', () {
      expect(IsimEslestirme.benzerlik('Mehmet Demir', 'Mehmet Demirci'), closeTo(0.857, 0.001));
      expect(IsimEslestirme.benzerlik('Ali Veli', 'Ayşe Yılmaz'), lessThan(0.5));
      expect(IsimEslestirme.benzerlik('Kaya Lojistik', 'Kaya Lojistik Holding'), lessThan(IsimEslestirme.varsayilanEsik));
    });

    test('Levenshtein', () {
      expect(IsimEslestirme.levenshtein('kitap', 'kitaplar'), 3);
      expect(IsimEslestirme.levenshtein('', 'abc'), 3);
      expect(IsimEslestirme.levenshtein('abc', 'abc'), 0);
    });
  });

  group('Unvan geçmişi', () {
    test('Unvan değişince eski unvan geçmişte kalır ve aranabilir', () {
      final eski = _kisi('k1', 'Kaya Nakliyat Ltd. Şti.');
      final yeni = eski.unvanDegistir('Kaya Lojistik A.Ş.', Tarih(2025, 6, 1));
      expect(yeni.ad, 'Kaya Lojistik A.Ş.');
      expect(yeni.unvanGecmisi.single.unvan, 'Kaya Nakliyat Ltd. Şti.');
      expect(yeni.tumAdlar, hasLength(2));
      final adaylar = MukerrerKontrol.bul([yeni], ad: 'KAYA NAKLİYAT');
      expect(adaylar.single.kisi.id, 'k1');
    });
  });

  group('Mükerrer kayıt', () {
    final mevcut = [
      _kisi('k1', 'ABC Gıda San. ve Tic. A.Ş.', no: '1234567890'),
      _kisi('k2', 'Mehmet Demirci', tur: KisiTuru.gercek),
      _kisi('k3', 'Zeytin Turizm A.Ş.'),
    ];

    test('Aynı kimlik numarası kesin mükerrerdir', () {
      final s = MukerrerKontrol.bul(mevcut, ad: 'Bambaşka Ad', kimlikNo: '1234567890');
      expect(s.single.tur, MukerrerTuru.kesin);
    });

    test('Benzer isim olası mükerrerdir', () {
      final s = MukerrerKontrol.bul(mevcut, ad: 'Mehmet Demir');
      expect(s.single.kisi.id, 'k2');
      expect(s.single.tur, MukerrerTuru.olasi);
    });

    test('Birleştirmede boş alanlar dolar, farklı ad geçmişe yazılır', () {
      final ana = _kisi('k1', 'ABC Gıda A.Ş.', no: '1234567890');
      final ikincil = _kisi('k9', 'ABC Gıda Pazarlama', eposta: 'info@abc.com.tr');
      final b = MukerrerKontrol.birlestir(ana, ikincil, tarih: Tarih(2026, 11, 25));
      expect(b.id, 'k1');
      expect(b.eposta, 'info@abc.com.tr');
      expect(b.unvanGecmisi.map((u) => u.unvan), ['ABC Gıda Pazarlama']);
    });

    test('Farklı kimlik numaralı kayıtlar birleştirilemez', () {
      expect(
        () => MukerrerKontrol.birlestir(_kisi('a', 'X', no: '1234567890'), _kisi('b', 'X', no: '9876543217'),
            tarih: Tarih(2026, 1, 1)),
        throwsArgumentError,
      );
    });
  });
}
