import 'dart:convert';

import 'package:hukuk_sunucu/hukuk_sunucu.dart';
import 'package:test/test.dart';

void main() {
  final simdi = DateTime.utc(2026, 11, 25, 18);
  final ics = icsOlustur([
    IcsEtkinlik(
      uid: 'durusma-1@hukukportali',
      baslangic: DateTime.utc(2026, 11, 27, 7, 30),
      bitis: DateTime.utc(2026, 11, 27, 8, 30),
      baslik: 'Duruşma · 2026/0002',
      yer: 'İstanbul 12. İş Mahkemesi, Kartal; Salon 3',
      hatirlatmaDakika: 120,
    ),
    IcsEtkinlik(
      uid: 'sure-1@hukukportali',
      baslangic: DateTime.utc(2026, 12, 2),
      tumGun: true,
      baslik: 'Süre son günü · 2026/0002 (teyit bekliyor)',
      aciklama: 'Çok uzun bir açıklama ' * 8,
    ),
  ], takvimAdi: 'Hukuk Portalı', simdi: simdi);

  test('RFC 5545: CRLF, başlık, UTC saat, tüm gün, kaçış ve hatırlatma', () {
    expect(ics, startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    expect(ics, contains('DTSTART:20261127T073000Z'));
    expect(ics, contains('DTSTART;VALUE=DATE:20261202\r\nDTEND;VALUE=DATE:20261203'));
    expect(ics, contains(r'LOCATION:İstanbul 12. İş Mahkemesi\, Kartal\; Salon 3'));
    expect(ics, contains('TRIGGER:-PT120M'));
    expect('BEGIN:VEVENT'.allMatches(ics).length, 2);
  });

  test('75 sekizliği aşan satırlar katlanır, Türkçe karakter bölünmez', () {
    for (final satir in ics.split('\r\n')) {
      expect(utf8.encode(satir).length, lessThanOrEqualTo(75), reason: satir);
    }
    final birlesik = ics.replaceAll('\r\n ', '');
    expect(birlesik, contains('DESCRIPTION:${'Çok uzun bir açıklama ' * 8}'.trimRight()));
  });
}
