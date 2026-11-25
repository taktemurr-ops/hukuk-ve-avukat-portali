# Yetki modeli

## Katmanlar

Kiracı → tüzel kişilik → birim/ekip → dosya → belge → işlem.

Bir kullanıcının bir nesnede bir işlemi yapabilmesi için:

1. Nesnenin kiracısının üyesi olmalı,
2. Rolü o işleme izin vermeli,
3. Nesnenin tüzel kişilik/birim kapsamında olmalı,
4. Dosya düzeyinde engel (etik duvar, gizli dosya) olmamalı,
5. Riskli işlemse ikinci onay alınmış olmalı.

## İşlemler (ayrı ayrı yetkilendirilir)

`goruntule`, `indir`, `disa_aktar`, `paylas`, `duzenle`, `onayla`, `imzala`, `gonder`, `kapat`, `yeniden_ac`, `sil`, `sure_teyit_et`, `muhafaza_baslat`, `muhafaza_kaldir`, `rol_ver`.

## Kural: tek kapı

Tüm okuma yolları (liste, arama, ön izleme, başlık, rapor, Excel, API, bildirim, yapay zekâ) **aynı yetki fonksiyonundan** geçer. Bir kanal kendi filtresini yazamaz. Bu kural kod incelemesinde kontrol edilir ve otomatik testle doğrulanır.

## Özel durumlar

| Durum | Kural |
| --- | --- |
| Etik duvar | Seçili kullanıcılar dosyanın varlığını bile göremez |
| Çıkar çatışması incelemesi | Korumalı dosyanın adı ve içeriği gösterilmez, yalnızca "eşleşme var" |
| Acil erişim | Gerekçeli, süreli, yöneticiye bildirilir, denetim kaydına işaretli yazılır |
| Destek erişimi | Müşteri onayı, kapsam, süre ve gerekçeyle; her işlem kayıtlı |
| Ayrılan kullanıcı | Oturumlar ve paylaşım linkleri anında iptal; kritik işleri devir listesine |
| Dış avukat | Yalnızca atanan dosyalar, süreli |
| Müvekkil | Yalnızca kendisiyle paylaşılan durum, belge, mesaj ve finans görünümü |
