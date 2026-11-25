import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Seçilen dosya: ad ve içerik.
typedef SecilenDosya = ({String ad, Uint8List icerik});

/// Cihazdan tek dosya seçtirir; vazgeçilirse `null`. Testlerde [dosyaSecici] değiştirilir.
typedef DosyaSecici = Future<SecilenDosya?> Function(List<String> uzantilar);

Future<SecilenDosya?> _platformdanSec(List<String> uzantilar) async {
  final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: uzantilar, withData: true);
  final f = r?.files.singleOrNull;
  final b = f?.bytes;
  if (f == null || b == null) return null;
  return (ad: f.name, icerik: b);
}

DosyaSecici dosyaSecici = _platformdanSec;

/// Dosyayı cihaza kaydeder (web'de indirme, masaüstü ve mobilde konum sorulur). Vazgeçilirse false.
typedef DosyaKaydedici = Future<bool> Function(String ad, List<int> icerik);

Future<bool> _platformaKaydet(String ad, List<int> icerik) async {
  final yol = await FilePicker.platform.saveFile(fileName: ad, bytes: Uint8List.fromList(icerik));
  // Web'de indirme başlatılır ve yol dönmez; diğer platformlarda yol null ise kullanıcı vazgeçmiştir.
  return yol != null || kIsWeb;
}

DosyaKaydedici dosyaKaydet = _platformaKaydet;

/// Excel'in Türkçe sürümünün CSV'si çoğunlukla Windows-1254'tür; önce UTF-8 denenir, olmazsa 1254 çözülür.
String csvCoz(List<int> b) {
  try {
    return utf8.decode(b);
  } on FormatException {
    return String.fromCharCodes([for (final x in b) _cp1254[x] ?? x]);
  }
}

/// Windows-1254'ün Latin-1'den farklı olan kodları (Türkçe harfler ve 0x80–0x9F aralığı).
const _cp1254 = <int, int>{
  0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021,
  0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x91: 0x2018, 0x92: 0x2019,
  0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC, 0x99: 0x2122,
  0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153, 0x9F: 0x0178,
  0xD0: 0x011E, 0xDD: 0x0130, 0xDE: 0x015E, 0xF0: 0x011F, 0xFD: 0x0131, 0xFE: 0x015F,
};

/// Satırları ";" ayraçlı CSV metnine çevirir (gerekirse tırnaklar).
String csvYaz(List<List<String>> satirlar) => satirlar
    .map((s) => s.map((h) => h.contains(RegExp('[;"\\n\\r]')) ? '"${h.replaceAll('"', '""')}"' : h).join(';'))
    .join('\n');
