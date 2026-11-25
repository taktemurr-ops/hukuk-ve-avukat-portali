/// Hukuki referans verinin (süre kuralı, tarife, tatil) onay durumu.
enum OnayDurumu {
  /// Yazıldı, avukat incelemedi. Canlıda kullanılamaz.
  taslak,

  /// Avukat onayladı, kullanıma açık.
  onayli,

  /// Mevzuat değişti veya hata bulundu; yeni hesaplarda kullanılmaz.
  kaldirildi,
}
