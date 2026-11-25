import 'dart:io';

import 'package:hukuk_sunucu/hukuk_sunucu.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final ortam = Platform.environment;
  final vt = Veritabani.ortamdan(ortam);
  final kokenler = (ortam['IZINLI_KOKENLER'] ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
  final belgeKlasoru = ortam['BELGE_KLASORU'];
  if (belgeKlasoru == null || belgeKlasoru.isEmpty) {
    stderr.writeln('BELGE_KLASORU tanımlı değil (belge içeriklerinin saklanacağı, Türkiye\'deki kalıcı ve şifreli disk).');
    exit(2);
  }
  final totpAnahtari = ortam['TOTP_ANAHTARI'];
  if (totpAnahtari == null || totpAnahtari.isEmpty) {
    stderr.writeln('TOTP_ANAHTARI tanımlı değil (32 bayt, base64; ör. openssl rand -base64 32). Gizli kasada tutulmalı.');
    exit(2);
  }
  // Ödeme sağlayıcısı: ODEME_SAGLAYICI=sahte yalnızca geliştirme/test içindir ve canlı ortamda reddedilir.
  OdemeSaglayici? odeme;
  switch (ortam['ODEME_SAGLAYICI']) {
    case 'sahte':
      if (ortam['ORTAM'] == 'canli') {
        stderr.writeln('Sahte ödeme sağlayıcısı canlı ortamda kullanılamaz.');
        exit(2);
      }
      odeme = SahteOdemeSaglayici(
          kokAdres: Uri.parse(ortam['DIS_ADRES'] ?? 'http://localhost:8080/'), gizli: ortam['ODEME_GIZLI'] ?? '');
      stdout.writeln('UYARI: sahte ödeme sağlayıcısı etkin (gerçek ödeme alınmaz).');
    case null || '':
      stdout.writeln('Ödeme sağlayıcısı tanımlı değil; ödeme başlatma kapalı.');
    default:
      stderr.writeln('Bilinmeyen ödeme sağlayıcısı: ${ortam['ODEME_SAGLAYICI']}');
      exit(2);
  }
  // E-posta: SMTP tanımlıysa gönderilir; değilse geliştirmede günlüğe yazılır, canlıda başlatılmaz.
  final EpostaGonderici eposta;
  if ((ortam['SMTP_SUNUCU'] ?? '').isNotEmpty) {
    eposta = SmtpGonderici(
      sunucu: ortam['SMTP_SUNUCU']!,
      port: int.parse(ortam['SMTP_PORT'] ?? '587'),
      kullanici: ortam['SMTP_KULLANICI'] ?? '',
      sifre: ortam['SMTP_SIFRE'] ?? '',
      gonderenAdres: ortam['SMTP_GONDEREN'] ?? 'bildirim@hukukportali.com.tr',
    );
  } else if (ortam['ORTAM'] == 'canli') {
    stderr.writeln('SMTP_SUNUCU tanımlı değil; canlı ortamda e-posta gönderimi zorunludur.');
    exit(2);
  } else {
    eposta = GunlugeYazanGonderici();
    stdout.writeln('UYARI: SMTP tanımlı değil; e-postalar sunucu günlüğüne yazılıyor (geliştirme).');
  }
  final portalAdresi = ortam['PORTAL_ADRESI'] ?? '';
  EpostaGorevi(vt, eposta, kaydet: (h) => stderr.writeln('E-POSTA HATASI: $h')).baslat();
  // Süre hatırlatma/eskalasyon e-postaları (saatlik; Türkiye saatiyle 08:00'den sonra, her uyarı günde bir kez).
  SureBildirimGorevi(vt,
          portalAdresi: portalAdresi.isEmpty ? null : Uri.parse(portalAdresi),
          kaydet: (h) => stderr.writeln('SÜRE BİLDİRİMİ HATASI: $h'))
      .baslat();
  // Zararlı yazılım taraması: CLAMD_ADRESI (ör. clamav:3310). Canlıda zorunlu.
  VirusTarayici? tarayici;
  final clamd = ortam['CLAMD_ADRESI'] ?? '';
  if (clamd.isNotEmpty) {
    final p = clamd.split(':');
    tarayici = ClamdTarayici(p.first, p.length > 1 ? int.parse(p[1]) : 3310);
  } else if (ortam['ORTAM'] == 'canli') {
    stderr.writeln('CLAMD_ADRESI tanımlı değil; canlı ortamda belge taraması zorunludur.');
    exit(2);
  } else {
    stdout.writeln('UYARI: virüs taraması kapalı (geliştirme).');
  }
  final davetAdresi = ortam['DAVET_ADRESI'];
  final handler = uygulama(
    vt,
    virusTarayici: tarayici,
    davetAdresi: davetAdresi == null || davetAdresi.isEmpty ? null : Uri.parse(davetAdresi),
    sifirlamaAdresi: portalAdresi.isEmpty ? null : Uri.parse(portalAdresi).resolve('sifre-sifirla'),
    dogrulamaAdresi: portalAdresi.isEmpty ? null : Uri.parse(portalAdresi).resolve('eposta-dogrula'),
    odemeSaglayici: odeme,
    depo: YerelNesneDeposu(belgeKlasoru),
    sifreleyici: AlanSifreleyici.base64(totpAnahtari),
    izinliKokenler: kokenler,
    belgeAzamiBoyut: int.parse(ortam['BELGE_AZAMI_MB'] ?? '50') * 1024 * 1024,
    kaydet: (h, iz) => stderr.writeln('HATA: $h\n$iz'),
  );
  final port = int.parse(ortam['PORT'] ?? '8080');
  final sunucu = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  sunucu.autoCompress = true;
  stdout.writeln('Hukuk sunucusu ${sunucu.port} numaralı portta.');
}
