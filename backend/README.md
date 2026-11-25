# Sunucu tarafı

| Klasör | İçerik |
| --- | --- |
| `veritabani/` | PostgreSQL 16 şeması (SQL göçleri) ve gerçek PostgreSQL'e karşı testler. Müşteri ayrımı, gizli dosya, etik duvar, dört göz ve değiştirilemez denetim kaydı veritabanında da zorlanır |
| `sunucu/` | Dart HTTP API (shelf + postgres). Süre, faiz ve yetki kuralları uygulamayla aynı `hukuk_cekirdek` paketinden gelir; süreler sunucuda hesaplanır |

## Mimari kararı (25.11.2026)

Başta Serverpod düşünülmüştü. Veri güvenliğini veritabanı seviyesinde de garanti etmek için şema elle yazılmış SQL
göçleriyle yönetiliyor (satır düzeyi güvenlik, tetikleyiciler, SECURITY DEFINER fonksiyonları). Serverpod kendi
ORM'i ve göç sistemiyle tabloları üretmek istediğinden bu yapıyla çakışır; bu yüzden sunucu, kod üretimi
gerektirmeyen `shelf` + `postgres` paketleriyle yazıldı. Dil yine Dart, paylaşılan çekirdek aynı.

## Yerelde çalıştırma

```bash
# 1. Veritabanı
createdb hukuk
for f in veritabani/migrations/*.sql; do psql -d hukuk -f "$f"; done
psql -d hukuk -c "CREATE ROLE hukuk_api LOGIN PASSWORD 'degistirin' IN ROLE hukuk_uygulama"

# 2. Sunucu
cd sunucu
dart pub get
dart test
PG_VERITABANI=hukuk PG_KULLANICI=hukuk_api PG_SIFRE=degistirin PG_SSL=kapali dart run bin/sunucu.dart
```

## Uçlar (ilk sürüm)

| Yöntem | Yol | Açıklama |
| --- | --- | --- |
| GET | `/saglik` | Durum |
| POST | `/giris` | E-posta + şifre → oturum token'ı (birden çok kurumda hesap varsa kurum seçimi) |
| POST | `/cikis` | Oturumu kapatır |
| GET | `/ben` | Kullanıcı, kurum ve roller |
| GET/POST | `/dosyalar` | Görünür dosyalar / yeni dosya (yıl bazında numara) |
| GET | `/dosyalar/{id}` | Dosya (görülemiyorsa 404; görüntüleme denetime yazılır) |
| GET/POST | `/dosyalar/{id}/sureler` | Süreler / süre hesapla ve kaydet (sunucuda hesaplanır, teyit bekler) |
| POST | `/sureler/{id}/teyit` | Teyit (hesaplayan kendisi teyit edemez) |
| POST | `/sureler/{id}/tamamla` | Kanıtla tamamlama |
| GET | `/denetim/dogrula` | Denetim zinciri sağlam mı |

Sunucu henüz derlenmedi (geliştirme ortamında Dart yok); ilk derleme ve `dart test` CI'da veya yerelde yapılacak.
