# Sunucu (Serverpod)

Serverpod projesi, Dart SDK'sı olan bir makinede bir kez üretilir ve depoya eklenir.

## İlk kurulum (kurucu bilgisayarında)

```bash
dart pub global activate serverpod_cli
cd backend
serverpod create hukuk
# Oluşan klasörler:
#   hukuk_server   sunucu kodu
#   hukuk_client   otomatik üretilen istemci
#   hukuk_flutter  örnek Flutter uygulaması (kullanılmayacak, silinebilir; arayüz apps/portal)
```

Ardından:

1. `hukuk_server/pubspec.yaml` içine çekirdek paketi ekleyin:
   ```yaml
   dependencies:
     hukuk_cekirdek:
       path: ../../packages/hukuk_cekirdek
   ```
2. `apps/portal/pubspec.yaml` içine istemciyi ekleyin:
   ```yaml
   dependencies:
     hukuk_client:
       path: ../../backend/hukuk/hukuk_client
   ```
3. Yerelde çalıştırma:
   ```bash
   cd backend/hukuk/hukuk_server
   docker compose up --build --detach   # PostgreSQL + Redis
   dart bin/main.dart --apply-migrations
   ```
4. `config/passwords.yaml` dosyasını **asla** depoya eklemeyin (.gitignore'da).

Bu adımlar tamamlandığında modeller (`docs/02-veri-modeli.md`) Serverpod model dosyalarına çevrilecek.
