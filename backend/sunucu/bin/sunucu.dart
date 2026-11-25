import 'dart:io';

import 'package:hukuk_sunucu/hukuk_sunucu.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final ortam = Platform.environment;
  final vt = Veritabani.ortamdan(ortam);
  final kokenler = (ortam['IZINLI_KOKENLER'] ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
  final handler = uygulama(vt, izinliKokenler: kokenler, kaydet: (h, iz) => stderr.writeln('HATA: $h\n$iz'));
  final port = int.parse(ortam['PORT'] ?? '8080');
  final sunucu = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  sunucu.autoCompress = true;
  stdout.writeln('Hukuk sunucusu ${sunucu.port} numaralı portta.');
}
