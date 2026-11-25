import 'package:hukuk_cekirdek/hukuk_cekirdek.dart';

import 'hata.dart';

/// JSON yardımcıları: Türkçe ve tutarlı hata iletileriyle alan okuma.
Tarih tarihAlani(Map<String, dynamic> j, String alan, {Tarih? varsayilan}) {
  final v = j[alan];
  if (v == null && varsayilan != null) return varsayilan;
  if (v is! String) throw ApiHatasi(400, '"$alan" tarihi zorunludur (YYYY-AA-GG).', kod: 'eksik_alan');
  try {
    return Tarih.parse(v);
  } on FormatException {
    throw ApiHatasi(400, '"$alan" YYYY-AA-GG biçiminde olmalı.', kod: 'gecersiz_istek');
  } on ArgumentError {
    throw ApiHatasi(400, '"$alan" geçersiz bir tarih.', kod: 'gecersiz_istek');
  }
}

/// Tutarlar istemci ile sunucu arasında kuruş (tam sayı) olarak taşınır; kayan nokta kullanılmaz.
int kurusAlani(Map<String, dynamic> j, String alan, {bool sifirOlabilir = false}) {
  final v = j[alan];
  if (v is! int) throw ApiHatasi(400, '"$alan" kuruş cinsinden tam sayı olmalı.', kod: 'gecersiz_istek');
  if (v < 0 || (!sifirOlabilir && v == 0)) throw ApiHatasi(400, '"$alan" sıfırdan büyük olmalı.', kod: 'gecersiz_istek');
  return v;
}

T enumAlani<T extends Enum>(Map<String, dynamic> j, String alan, List<T> degerler) {
  final v = j[alan];
  for (final d in degerler) {
    if (d.name == v) return d;
  }
  throw ApiHatasi(400, '"$alan" için geçerli değerler: ${degerler.map((d) => d.name).join(', ')}.', kod: 'gecersiz_istek');
}

String tarihMetni(Object? v) => v is DateTime ? Tarih.from(v).isoBicim : (v?.toString() ?? '');

Tarih tarihDegeri(Object? v) => v is DateTime ? Tarih.from(v) : Tarih.parse(v! as String);
