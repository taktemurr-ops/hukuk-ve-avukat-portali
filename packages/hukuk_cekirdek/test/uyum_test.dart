import 'dart:math';

import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 20, 9);
  final ihbar = Ihbar(
    id: 'i1',
    takipKodu: Ihbar.takipKoduUret(Random(1)),
    zaman: t0,
    kanal: IhbarKanali.web,
    kategori: IhbarKategorisi.rusvetYolsuzluk,
    aciklama: 'Satın alma biriminde tedarikçiden hediye alındığı iddiası',
    ilgiliKisiler: {'emre'},
  );

  test('takip kodu 10 karakter ve karışan harf içermez', () {
    final k = Ihbar.takipKoduUret();
    expect(k, hasLength(10));
    expect(RegExp('[01OI]').hasMatch(k), isFalse);
  });

  test('ihbar edilen kişi soruşturmada yer alamaz; erişim yalnızca ekipte', () {
    expect(() => Sorusturma(id: 's', ihbar: ihbar, sorumlu: 'emre', acilis: t0), throwsStateError);
    final s = Sorusturma(id: 's', ihbar: ihbar, sorumlu: 'ayse', acilis: t0);
    expect(() => s.ekipEkle('emre', ekleyen: 'ayse'), throwsStateError);
    expect(() => s.ekipEkle('can', ekleyen: 'mert'), throwsStateError);
    s.ekipEkle('can', ekleyen: 'ayse');
    expect(s.erisebilir('can'), isTrue);
    expect(s.erisebilir('mert'), isFalse);
    expect(() => s.notEkle('mert', 'x', t0), throwsStateError);
    s.notEkle('can', 'Fatura kayıtları istendi', t0);
    expect(s.notlar.single.kullanici, 'can');
  });

  test('aşamalar, geri bildirim ve sonuç süreleri', () {
    final s = Sorusturma(id: 's', ihbar: ihbar, sorumlu: 'ayse', acilis: t0);
    expect(s.geriBildirimSonu, DateTime.utc(2026, 11, 27, 9));
    expect(s.geriBildirimGecikti(DateTime.utc(2026, 11, 28)), isTrue);
    s.geriBildirimVer('ayse', DateTime.utc(2026, 11, 22));
    expect(s.geriBildirimGecikti(DateTime.utc(2026, 11, 28)), isFalse);
    expect(() => s.kapat('ayse', SorusturmaSonucu.dogrulandi, 'Yeterince uzun bir sonuç özeti metni'), throwsStateError);
    s
      ..sorusturmayaAl('ayse')
      ..raporlamayaGec('ayse');
    expect(() => s.kapat('ayse', SorusturmaSonucu.dogrulandi, 'kısa'), throwsArgumentError);
    s.kapat('ayse', SorusturmaSonucu.kismen, 'Hediye kabulü doğrulandı, ihale etkisi tespit edilmedi.');
    expect(s.durum, SorusturmaDurumu.kapandi);
    expect(s.sonucGecikti(DateTime.utc(2027, 6, 1)), isFalse);

    final r = Sorusturma(id: 'r', ihbar: ihbar, sorumlu: 'ayse', acilis: t0);
    expect(() => r.reddet('ayse', 'kısa'), throwsArgumentError);
    r.reddet('ayse', 'İhbarda somut olgu yok, ek bilgi gelmedi');
    expect(r.durum, SorusturmaDurumu.reddedildi);
    expect(r.durum.acik, isFalse);
  });

  test('veri ihlali: 72 saat içinde Kurul bildirimi', () {
    final v = VeriIhlali(id: 'v', ogrenilme: t0, aciklama: 'E-posta yanlış gruba gönderildi', etkilenenKisiSayisi: 120);
    expect(v.kurulSonZaman, DateTime.utc(2026, 11, 23, 9));
    expect(v.kalan(DateTime.utc(2026, 11, 22, 9)), const Duration(hours: 24));
    expect(v.gecikti(DateTime.utc(2026, 11, 23, 10)), isTrue);
    expect(() => v.kurulaBildirildi(DateTime.utc(2026, 11, 19)), throwsArgumentError);
    v.kurulaBildirildi(DateTime.utc(2026, 11, 22, 18));
    expect(v.gecikti(DateTime.utc(2026, 12, 1)), isFalse);
  });
}
