# Tasarım sistemi

Referans taslak: [tasarim/genel-bakis-taslak.png](tasarim/genel-bakis-taslak.png) (kurucunun Genel Bakış taslağı).
Kod: `apps/portal/lib/tema/tema.dart`, `apps/portal/lib/bilesenler/tasarim.dart`.

## Renkler

| Ad | Kod | Kullanım |
| --- | --- | --- |
| Lacivert | `#0F1E33` | Yan menü, giriş tanıtım paneli |
| Koyu yeşil | `#0E5A4E` | Birincil düğme, seçili menü, vurgular |
| Altın | `#C9A45C` | Logo işareti, ikincil vurgu |
| Krem | `#F7F5F0` | Sayfa zemini |
| Kenar | `#E6E2D9` | Kart ve ayraç çizgileri |
| Metin | `#14213D` | Ana metin |

Durum rozetleri: Kritik (kırmızı), Teyit bekliyor (amber), Onay/teyitli (yeşil), Devam ediyor (mavi), Nötr (gri).

## Tipografi

- Başlıklar: **Source Serif 4** (600, 700)
- Metin: **Inter** (400–700)
- İkisi de SIL Open Font License; uygulamaya gömülüdür. Çalışma anında Google'dan font indirilmez (kullanıcı IP'si yurt dışına gitmez).

## Düzen

- Geniş ekran (≥1000 px): 268 px lacivert yan menü + beyaz üst çubuk (şirket seçici, arama, bildirim, profil) + krem içerik.
- Dar ekran: yan menü çekmeceye taşınır.
- Menü hesap türüne göre değişir: "Hukuk Talepleri" ve "Sözleşmeler" yalnızca Kurumsal; Kurumsal'da "Müvekkiller" yerine "Taraflar".
- Henüz geliştirilmeyen modüller boş ekran yerine yol haritasındaki fazıyla dürüstçe gösterilir.

## Taslağa göre eklenenler

- Göstergeler ve iş kuyruğu gerçek veriden hesaplanır; bir satıra tıklamak dosyayı açar.
- Kritik İşler: süre uyarıları (eskalasyon motoru) + geciken görevler. Tüm İşler: açık süreler + görevler.
- Yaklaşan duruşmalarda aynı avukatın çakışan duruşmaları "Çakışma" rozetiyle işaretlenir.
- Bildirim zili bekleyen süre uyarısı sayısını gösterir.
- Genel arama Türkçe karakterden bağımsızdır ve yetki filtresinden geçer (gizli dosya aramada da görünmez).
