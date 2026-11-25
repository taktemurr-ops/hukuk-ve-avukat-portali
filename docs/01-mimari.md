# Mimari

## Genel görünüm

```
[Flutter uygulaması]  web · iOS · Android · Windows · macOS
        │  (Serverpod istemcisi, tip güvenli)
        ▼
[Serverpod sunucusu]  modüler monolit (Dart)
   ├─ PostgreSQL      ana veri, satır düzeyinde müşteri izolasyonu
   ├─ Redis           önbellek, oturum, kuyruk
   ├─ Nesne depolama  belgeler (S3 uyumlu, ör. MinIO), şifreli
   ├─ OpenSearch      Türkçe tam metin arama (yetki filtreli)
   └─ İş kuyruğu      bildirim, süre hatırlatma, aktarım, entegrasyon (yeniden denenebilir)
        │
        ▼
[Belge/AI servisi]    Python: OCR, DOCX/PDF/UDF dönüşümü, sözleşme tarama, yerel AI modeli

[Masaüstü yardımcı]   Flutter masaüstü: UYAP oturumu ve e-imza (PKCS#11, FFI)
[Tanıtım sitesi]      Statik site (SEO), ödeme sayfası ödeme kuruluşunda
```

## Kararlar

| # | Karar | Gerekçe |
| --- | --- | --- |
| K1 | Flutter tek kod tabanı | Küçük ekip; web, mobil, masaüstü aynı kod |
| K2 | Serverpod (Dart) sunucu | Uygulama ile aynı dil, istemci kodu otomatik üretilir, kendi sunucumuzda/müşteri sunucusunda çalışır |
| K3 | Modüler monolit | Üç kişilik ekip için mikroservis gereksiz yük; modül sınırları kodda korunur |
| K4 | PostgreSQL + her tabloda `kiraci_id` | Çok kiracılı izolasyon; ayrılmış ortamda aynı şema |
| K5 | Saf Dart çekirdek paket (`hukuk_cekirdek`) | Süre hesabı gibi kritik kurallar hem istemcide hem sunucuda aynı kodla, kolay test |
| K6 | Veri yalnızca Türkiye'de | Bağlayıcı ürün kararı; Firebase, yurt dışı AI API, yurt dışı e-posta/SMS kullanılmaz |
| K7 | Konteyner (Docker) paketleme | SaaS, ayrılmış ortam ve müşteri sunucusuna kurulum aynı paketle |
| K8 | Tanıtım sitesi Flutter değil | Arama motoru görünürlüğü |
| K9 | Mobilde satın alma yok | Uygulama mağazası komisyonu; satın alma web'de |

## Flutter web riski

Ek kapsam dokümanı web'de yoğun tablo, belge düzenleme ve klavye erişilebilirliği istiyor. İlk iki haftada prototip ile ölçülecek:

- 5.000 satırlı dosya listesinde kaydırma ve filtreleme akıcılığı
- Dilekçe editörü (zengin metin) ve DOCX'e dönüşüm kalitesi
- Yalnızca klavye ile tüm akışın tamamlanabilmesi, ekran okuyucu

Sonuç kötüyse yalnızca yoğun tablo/editör ekranları için alternatif değerlendirilir; karar bu dosyaya yazılır.

## Ortamlar

`gelistirme` (yerel Docker) → `test` (staging, anonim veri) → `canli`. Canlı veri asla test ortamına kopyalanmaz.

## Türkiye'de çalışan bileşen listesi (yurt dışına veri çıkmaz)

| İhtiyaç | Seçim |
| --- | --- |
| Sunucu | Türkiye'de veri merkezi olan bulut veya kolokasyon (karar bekliyor) |
| Hata takibi | Kendi sunucumuzda Sentry |
| Ürün analitiği | Kendi sunucumuzda (ör. PostHog/Matomo) |
| E-posta / SMS | Türkiye'de veri tutan sağlayıcı |
| Mobil bildirim | FCM/APNs yalnızca içeriksiz "yeni bildirim" sinyali |
| Ödeme | iyzico / PayTR / Param (karar bekliyor) |
| e-SMM / e-Fatura | GİB onaylı yerli entegratör |
| Yapay zekâ | Türkiye'deki GPU sunucusunda açık ağırlıklı model |
