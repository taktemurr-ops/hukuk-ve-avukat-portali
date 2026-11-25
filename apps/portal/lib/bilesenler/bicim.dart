import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
const _kisaAylar = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];

/// "25 Kasım 2026, Çarşamba"
String uzunTarih(Tarih t) => '${t.gun} ${_aylar.elementAt(t.ay - 1)} ${t.yil}, ${t.gunAdi}';

/// "26 Kas"
String kisaTarih(Tarih t) => '${t.gun} ${_kisaAylar.elementAt(t.ay - 1)}';

/// "KAS" (Türkçe büyük harf kuralıyla)
String ayKisaltmasi(int ay) => _kisaAylar.elementAt(ay - 1).replaceAll('i', 'İ').toUpperCase();

String saat(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// Tarih-saat için kısa Türkçe biçim: "27.11.2026 Cuma 10:30".
String tarihSaat(DateTime dt) {
  final t = Tarih.from(dt);
  return '${t.turkceBicim} ${t.gunAdi} ${saat(dt)}';
}

/// "bugün", "yarın", "3 gün sonra", "2 gün geçti".
String kalanMetni(int kalan) {
  if (kalan == 0) return 'bugün';
  if (kalan == 1) return 'yarın';
  if (kalan > 1) return '$kalan gün sonra';
  return '${-kalan} gün geçti';
}

/// "Ayşe Yılmaz" → "AY"
String basHarfler(String ad) {
  final parcalar = ad.replaceAll(RegExp(r'^(Av\.|Stj\.)\s*'), '').trim().split(RegExp(r'\s+'));
  final harfler = parcalar.where((p) => p.isNotEmpty).take(2).map((p) => p.substring(0, 1)).join();
  return harfler.replaceAll('i', 'İ').toUpperCase();
}
