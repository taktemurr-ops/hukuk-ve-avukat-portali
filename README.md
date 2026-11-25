# Hukuk ve Avukat Portalı

Avukatlık büroları, hukuk büroları ve şirket hukuk birimleri için uçtan uca hukuk yönetim platformu.

> Tüm hakları saklıdır. Bu depo gizlidir; içeriği paylaşılamaz.

## Ürün kapsamı

Tam ürün kapsamı: [Kapsam dokümanı](https://claude.ai/artifact/776tAqTrSio4FcNoojSCYp) · Özet: [docs/00-kapsam.md](docs/00-kapsam.md)

Üç hesap türü vardır: **Avukatlık Bürosu**, **Hukuk Bürosu**, **Kurumsal**. Modüller, roller, yetkiler ve fiyat hesap türüne göre ayrıdır.

## Temel kararlar

| Konu | Karar |
| --- | --- |
| Arayüz | Flutter (web, iOS, Android, Windows, macOS) |
| Tanıtım sitesi | Ayrı statik site (arama motoru uyumu için Flutter değil) |
| Sunucu | Serverpod (Dart) + PostgreSQL + Redis |
| Belge, OCR, yapay zekâ | Ayrı Python servisi |
| Veri konumu | Tüm veri yalnızca Türkiye'de (yedek, log, hata takibi, yapay zekâ dahil) |
| Kurulum | SaaS, ayrılmış ortam ve müşteri sunucusuna kurulum; konteyner olarak paketlenir |

Ayrıntı: [docs/01-mimari.md](docs/01-mimari.md) · Tasarım: [docs/06-tasarim.md](docs/06-tasarim.md)

## Depo yapısı

```
apps/portal/              Flutter uygulaması (web + mobil + masaüstü)
packages/hukuk_cekirdek/  Saf Dart çekirdek: süre hesabı, tatil takvimi, hesap türleri
site/                     Statik tanıtım sitesi (gömülü fontlar, çerezsiz)
backend/                  Serverpod sunucusu (kurulum adımları içinde)
docs/                     Mimari, veri modeli, yetki modeli, iş listesi
.github/workflows/        Otomatik derleme ve testler
```

## Geliştirme

Gerekenler: Flutter (stable), Dart 3.5+, Docker.

```bash
# Çekirdek paket testleri
cd packages/hukuk_cekirdek
dart pub get
dart test

# Flutter uygulaması (ilk seferde platform klasörlerini üretin)
cd apps/portal
flutter create . --project-name portal --org tr.hukukportali --platforms=web,android,ios,windows,macos
flutter pub get
flutter run -d chrome
```

Her `push` ve `pull request` işleminde GitHub Actions çekirdek testleri ve Flutter analizini çalıştırır.

## Ekip

- Kurucu: ürün, satış, sunucu işletimi (DevOps)
- Avukat: hukuki doğruluk (süre kuralları, tarifeler, referans veriler, şablonlar, yapay zekâ çıktıları)
- Claude: tasarım, kod, test, dokümantasyon

## Hukuki doğruluk kuralı

Süre kuralları, tatil günleri, faiz oranları ve tarifeler **referans veridir**. Ekipteki avukat onaylamadan hiçbir kural canlıda kullanılmaz. Kodda her kural `OnayDurumu.taslak` olarak başlar.
