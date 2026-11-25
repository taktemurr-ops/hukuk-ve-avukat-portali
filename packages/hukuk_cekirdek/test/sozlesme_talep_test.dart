import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

const ornekSozlesme = '''
HİZMET SÖZLEŞMESİ

Madde 1 – Taraflar
İşbu sözleşme, ABC Gıda Sanayi ve Ticaret A.Ş. (bundan sonra "Müşteri") ile Delta Bilişim Hizmetleri Ltd. Şti. (bundan sonra "Hizmet Veren") arasında akdedilmiştir.

Madde 2 – Süre
Sözleşme 01.01.2026 tarihinde yürürlüğe girer ve 31.12.2026 tarihinde sona erer. Taraflardan biri sona erme tarihinden en az 60 (altmış) gün önce yazılı olarak bildirimde bulunmadıkça sözleşme aynı şartlarla birer yıl süreyle kendiliğinden uzar.

Madde 3 – Bedel ve Ödeme
Aylık hizmet bedeli 125.000,00 TL + KDV'dir. Fatura tarihinden itibaren 30 (otuz) gün içinde ödenir. Hizmet Veren, tek taraflı olarak ücret tarifesini her yıl güncelleme hakkına sahiptir.

Madde 4 – Sorumluluk
Hizmet Veren, hizmetin ifasından doğan tüm zararlardan sınırsız olarak sorumludur.

Madde 5 – Cezai Şart
Hizmet seviyesine uyulmaması hâlinde her ihlal için 50.000 TL cezai şart ödenir.

Madde 6 – Fesih
Müşteri, herhangi bir sebep göstermeksizin 30 gün önceden bildirmek kaydıyla sözleşmeyi feshedebilir.

Madde 7 – Gizlilik
Taraflar, birbirlerinin ticari sırlarını gizli tutacaktır.

Madde 8 – Uyuşmazlık
İşbu sözleşme Türk hukukuna tabidir. Uyuşmazlıklarda İstanbul (Çağlayan) Mahkemeleri ve İcra Daireleri yetkilidir.
''';

void main() {
  const tarayici = SozlesmeTarayici();

  group('SozlesmeTarayici', () {
    final t = tarayici.tara(ornekSozlesme);

    test('alanları çıkarır', () {
      expect(t.tur, SozlesmeTuru.hizmet);
      expect(t.taraflar, ['ABC Gıda Sanayi ve Ticaret A.Ş.', 'Delta Bilişim Hizmetleri Ltd. Şti.']);
      expect(t.baslangic, Tarih(2026, 1, 1));
      expect(t.bitis, Tarih(2026, 12, 31));
      expect(t.otomatikYenileme, isTrue);
      expect(t.ihbarSuresiGun, 60);
      expect(t.bedel, Para.tl(125000));
      expect(t.odemeVadesiGun, 30);
      expect(t.yetkiliYer, 'İstanbul');
      expect(t.uygulanacakHukuk, 'Türk hukuku');
      expect(t.tahkim, isFalse);
    });

    test('riskleri ve eksik maddeleri bulur', () {
      final kodlar = t.bulgular.map((b) => b.kod).toList();
      expect(kodlar.first, 'sinirsizSorumluluk');
      expect(kodlar, containsAll(['otomatikYenileme', 'cezaiSart', 'tekTarafliFesih', 'tekTarafliFiyat',
          'mucbirSebepYok', 'kvkkYok']));
      expect(kodlar, isNot(contains('gizlilikYok')));
      expect(kodlar, isNot(contains('yetkiYok')));
      expect(t.bulgular.first.alinti, contains('sınırsız olarak sorumludur'));
      expect(t.riskPuani, 86);
      expect(t.genelSeviye, SozlesmeRiski.yuksek);
    });

    test('yabancı hukuk, yurt dışı tahkim, kelimeyle yazılmış süreler', () {
      final s = tarayici.tara('Gizlilik Sözleşmesi\n'
          'Sözleşmenin süresi iki yıldır. Onay süresi beklenir.\n'
          'İşbu sözleşme İngiliz hukukuna tabidir ve uyuşmazlıklar ICC kuralları uyarınca Londra\'da tahkim yoluyla çözülür.');
      expect(s.tur, SozlesmeTuru.gizlilik);
      expect(s.sureAy, 24);
      expect(s.uygulanacakHukuk, 'İngiliz hukuku');
      expect(s.tahkim, isTrue);
      expect(s.bulgular.map((b) => b.kod), containsAll(['yabanciHukuk', 'yurtdisiTahkim']));
      expect(s.bulgular.map((b) => b.kod), isNot(contains('yetkiYok')));
    });

    test('ihbar süresi bulunamayan otomatik yenileme orta risk; geçersiz tarih yok sayılır', () {
      final s = tarayici.tara('Kira Sözleşmesi\nSözleşme 31.02.2026 tarihinde başlar. '
          'Süre sonunda sözleşme otomatik olarak yenilenir.');
      expect(s.baslangic, isNull);
      expect(s.bulgular.firstWhere((b) => b.kod == 'otomatikYenileme').seviye, SozlesmeRiski.orta);
      expect(s.bulgular.map((b) => b.kod), isNot(contains('gizlilikYok')));
    });

    test('Türkçe küçük harf uzunluğu korur', () {
      expect(SozlesmeTarayici.kucukHarf('İSTANBUL IŞIK'), 'istanbul ışık');
    });
  });

  group('Sozlesme', () {
    Sozlesme yeni() => Sozlesme(
        id: 's1', no: 'SZ-2026-0001', baslik: 'BT hizmet', tur: SozlesmeTuru.diger, karsiTaraf: 'Delta', sorumlu: 'av1')
      ..taramayiUygula(tarayici.tara(ornekSozlesme));

    test('tarama boş alanları doldurur, girilmiş değeri ezmez', () {
      final s = Sozlesme(
          id: 's1', no: 'SZ', baslik: 'x', tur: SozlesmeTuru.diger, karsiTaraf: 'D', sorumlu: 'a', ihbarSuresiGun: 90)
        ..taramayiUygula(tarayici.tara(ornekSozlesme));
      expect(s.tur, SozlesmeTuru.hizmet);
      expect(s.ihbarSuresiGun, 90);
      expect(s.bitis, Tarih(2026, 12, 31));
      expect(s.otomatikYenileme, isTrue);
      expect(s.ihbarSonGunu, Tarih(2026, 10, 2));
    });

    test('süreden bitiş hesaplanır', () {
      final s = Sozlesme(id: 's', no: 'n', baslik: 'b', tur: SozlesmeTuru.diger, karsiTaraf: 'k', sorumlu: 's')
        ..taramayiUygula(TaramaSonucu(sureAy: 24, baslangic: Tarih(2026, 3, 15)));
      expect(s.bitis, Tarih(2028, 3, 14));
    });

    test('durum geçişleri ve yürürlük şartı', () {
      final s = Sozlesme(id: 's', no: 'n', baslik: 'b', tur: SozlesmeTuru.hizmet, karsiTaraf: 'k', sorumlu: 's');
      expect(() => s.durumDegistir(SozlesmeDurumu.yururlukte), throwsStateError);
      s
        ..durumDegistir(SozlesmeDurumu.onayda)
        ..durumDegistir(SozlesmeDurumu.imzada);
      expect(() => s.durumDegistir(SozlesmeDurumu.yururlukte), throwsStateError);
      s.baslangic = Tarih(2026, 1, 1);
      s.durumDegistir(SozlesmeDurumu.yururlukte);
      expect(s.durum, SozlesmeDurumu.yururlukte);
    });

    test('ihbar uyarıları ve kendiliğinden uzama', () {
      final s = yeni()..durum = SozlesmeDurumu.yururlukte;
      expect(s.uyarilar(Tarih(2026, 8, 1)), isEmpty);
      expect(s.uyarilar(Tarih(2026, 9, 15)).single.tur, SozlesmeUyariTuru.ihbarYaklasiyor);
      expect(s.uyarilar(Tarih(2026, 11, 25)).single.tur, SozlesmeUyariTuru.ihbarKacti);
      expect(s.kendiligindenUzat(Tarih(2026, 12, 31)), isFalse);
      expect(s.kendiligindenUzat(Tarih(2028, 1, 5)), isTrue);
      expect(s.bitis, Tarih(2028, 12, 31));
    });

    test('yükümlülük uyarıları', () {
      final s = yeni()
        ..yukumlulukler.add(Yukumluluk(
            id: 'y1', aciklama: 'Teminat mektubu', taraf: YukumlulukTarafi.karsiTaraf, sonTarih: Tarih(2026, 2, 1)));
      expect(s.uyarilar(Tarih(2026, 1, 10)).single.tur, SozlesmeUyariTuru.yukumlulukYaklasiyor);
      expect(s.uyarilar(Tarih(2026, 2, 2)).single.tur, SozlesmeUyariTuru.yukumlulukGecikti);
      s.yukumlulukler[0] = s.yukumlulukler[0].tamamla();
      expect(s.uyarilar(Tarih(2026, 2, 2)), isEmpty);
    });
  });

  group('Hukuk talepleri', () {
    final hesap = IsGunuHesabi(TurkiyeTatilleri.takvim([2026]));

    test('iş günü: hafta sonu ve bayram atlanır, arife yarım gün sayılır', () {
      expect(hesap.ekle(Tarih(2026, 12, 4), 3), Tarih(2026, 12, 9));
      expect(hesap.ekle(Tarih(2026, 3, 18), 3), Tarih(2026, 3, 24));
      expect(hesap.arasinda(Tarih(2026, 12, 4), Tarih(2026, 12, 9)), 3);
    });

    test('öncelik SLA süresini belirler', () {
      expect(Oncelik.acil.slaIsGunu(TalepTuru.hukukiGorus), 1);
      expect(Oncelik.yuksek.slaIsGunu(TalepTuru.sozlesmeInceleme), 2);
      expect(Oncelik.dusuk.slaIsGunu(TalepTuru.sozlesmeInceleme), 6);
    });

    test('talep oluşur, yükü en az olana atanır, bilgi beklerken SLA durur', () {
      final defter = TalepDefteri(
          hesap: hesap,
          yonlendirici: const TalepYonlendirici({
            TalepTuru.sozlesmeInceleme: ['ece', 'mert'],
            TalepTuru.diger: ['ece'],
          }));
      final gun = Tarih(2026, 12, 4);
      HukukTalebi ac(String b) => defter.olustur(
          baslik: b, aciklama: '', tur: TalepTuru.sozlesmeInceleme, oncelik: Oncelik.normal,
          talepEden: 'satis.uzmani', birim: 'Satış', bugun: gun);
      final t1 = ac('Bayi sözleşmesi');
      final t2 = ac('NDA');
      final t3 = ac('Kira');
      expect([t1.atanan, t2.atanan, t3.atanan], ['ece', 'mert', 'ece']);
      expect(t1.no, 'HT-2026-0001');
      expect(t1.durum, TalepDurumu.atandi);
      expect(t1.slaSonGun, Tarih(2026, 12, 9));

      t1.durumDegistir(TalepDurumu.incelemede, kullanici: 'ece', bugun: Tarih(2026, 12, 7), hesap: hesap);
      t1.durumDegistir(TalepDurumu.bilgiBekleniyor,
          kullanici: 'ece', bugun: Tarih(2026, 12, 7), hesap: hesap, not: 'İmzalı teklif eksik');
      expect(t1.slaDurumu(Tarih(2026, 12, 20), hesap), SlaDurumu.durduruldu);
      t1.durumDegistir(TalepDurumu.incelemede, kullanici: 'ece', bugun: Tarih(2026, 12, 10), hesap: hesap);
      expect(t1.slaSonGun, Tarih(2026, 12, 14));
      expect(t1.slaDurumu(Tarih(2026, 12, 10), hesap), SlaDurumu.zamaninda);
      expect(t1.slaDurumu(Tarih(2026, 12, 11), hesap), SlaDurumu.riskli);
      expect(t1.slaDurumu(Tarih(2026, 12, 15), hesap), SlaDurumu.gecikti);

      expect(() => t2.durumDegistir(TalepDurumu.reddedildi, kullanici: 'mert', bugun: gun, hesap: hesap),
          throwsArgumentError);
      expect(() => t2.durumDegistir(TalepDurumu.onayda, kullanici: 'mert', bugun: gun, hesap: hesap),
          throwsStateError);
      t1.durumDegistir(TalepDurumu.tamamlandi, kullanici: 'ece', bugun: Tarih(2026, 12, 11), hesap: hesap);
      expect(t1.slaDurumu(Tarih(2027, 1, 1), hesap), SlaDurumu.zamaninda);
      expect(t1.gecmis.map((o) => o.aciklama).last, 'Tamamlandı');
    });
  });

  test('sunucudan yüklenen beklemedeki talep SLA ötelemesini korur', () {
    final hesap = IsGunuHesabi(TurkiyeTatilleri.takvim([2026]));
    final t = HukukTalebi(
      id: 't1',
      no: 'HT-2026-0001',
      baslik: 'NDA',
      aciklama: '',
      tur: TalepTuru.sozlesmeInceleme,
      oncelik: Oncelik.normal,
      talepEden: 'Satış',
      birim: 'Satış',
      olusturma: Tarih(2026, 11, 2),
      slaSonGun: Tarih(2026, 11, 5),
      beklemeBaslangici: Tarih(2026, 11, 3),
    )..durum = TalepDurumu.bilgiBekleniyor;
    expect(t.beklemeBaslangici, Tarih(2026, 11, 3));
    // 3 Kasım Salı → 6 Kasım Cuma: 3 iş günü bekleme; SLA 5 Kasım'dan 3 iş günü sonraya (10 Kasım) kayar.
    t.durumDegistir(TalepDurumu.incelemede, kullanici: 'a', bugun: Tarih(2026, 11, 6), hesap: hesap);
    expect(t.slaSonGun, Tarih(2026, 11, 10));
    expect(t.beklemeBaslangici, isNull);
  });
}
