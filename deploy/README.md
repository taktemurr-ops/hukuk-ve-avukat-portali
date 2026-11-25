# Kurulum ve canlıya hazırlık

Tüm bileşenler **Türkiye'deki** sunucularda çalışır (veri, yedek, günlük, e-posta, ödeme bildirimi dahil).

## Bileşenler

| Servis | Görev |
| --- | --- |
| `veritabani` | PostgreSQL 16 (satır düzeyi güvenlik, denetim zinciri) |
| `goc` | Şema göçlerini sırayla uygular (`backend/veritabani/goc.py`), uygulama kullanıcısını (`hukuk_api`) hazırlar |
| `sunucu` | Dart uygulama sunucusu (API), e-posta kuyruğu gönderici görevi |
| `belge` | Python belge servisi (metin çıkarma, OCR, Word üretimi) |
| `clamav` | Yüklenen belgelerin zararlı yazılım taraması |

## İlk kurulum (tek sunucu)

```bash
cd deploy
cp .env.ornek .env        # değerleri doldurun (openssl rand ile üretin), .env'i gizli kasada saklayın
docker compose up -d --build
docker compose logs -f sunucu
```

Göç durumu: `docker compose run --rm goc python goc.py --kontrol` (bekleyen göç varsa 1 ile çıkar).
Uygulanmış bir göç dosyası değiştirilirse `goc.py` durur; değişiklikler her zaman yeni göçle yapılır.

## Canlıya çıkmadan önce (kontrol listesi)

- [ ] **Sunucu sağlayıcısı** Türkiye'de; disk şifreleme açık; yönetim erişimi yalnızca VPN/SSH anahtarıyla.
- [ ] `ORTAM=canli` — sahte ödeme ve SMTP'siz/ClamAV'sız başlatma engellenir.
- [ ] **TLS**: `sunucu` yalnızca `127.0.0.1:8080`'de; önüne TLS ters vekil (Caddy/nginx), HSTS açık.
- [ ] **Gizli değerler** (`PG_*`, `TOTP_ANAHTARI`, `ODEME_GIZLI`, `SMTP_SIFRE`) gizli kasada; depoda yok.
      `TOTP_ANAHTARI` kaybolursa kullanıcıların iki adımlı doğrulaması yeniden kurulmalıdır.
- [ ] **Ödeme kuruluşu** (iyzico/PayTR vb.) seçildi, `OdemeSaglayici` uyarlaması yazıldı ve test kartlarıyla
      bildirim imzası, tutar uyuşmazlığı ve tekrar gelen bildirim denendi. Bildirim adresi:
      `https://<api>/acik/odeme-bildirimi/<saglayici>`.
- [ ] **E-posta**: SMTP (TLS), SPF/DKIM/DMARC kayıtları; davet e-postası bir test adresine ulaştı.
- [ ] **Yedekleme** (aşağıda) kuruldu ve **geri yükleme denendi**.
- [ ] **İzleme**: `GET /saglik`, disk doluluğu, e-posta kuyruğunda `hata` sayısı, ClamAV imza güncelliği.
- [ ] **Avukat onayı**: süre kuralları, harç/faiz/AAÜT tarifeleri, şablonlar, sözleşme tarama kuralları, KVKK saklama süreleri.
- [ ] **KVKK**: aydınlatma metni, açık rıza gerekmeyen işleme dayanakları, VERBİS kaydı, veri işleme sözleşmesi şablonu.
- [ ] İlk derleme ve tüm testler (Dart, Flutter, Python, veritabanı) CI'da yeşil.

## Yedekleme

Veritabanı (günlük tam + sürekli WAL arşivi önerilir) ve belge klasörü (`belgeler` birimi) birlikte yedeklenir;
yedekler şifreli ve **yine Türkiye'de** ayrı bir konumda tutulur.

```bash
# Günlük mantıksal yedek (şifreli)
docker compose exec -T veritabani pg_dump -U hukuk_sahip -Fc hukuk | \
  gpg --symmetric --cipher-algo AES256 -o /yedek/hukuk-$(date +%F).dump.gpg

# Belgeler (içerik adresli; artımlı kopya yeterli)
docker run --rm -v hukuk_belgeler:/kaynak:ro -v /yedek/belgeler:/hedef alpine \
  sh -c "cp -an /kaynak/. /hedef/"
```

Geri yükleme denemesi en az ayda bir ayrı bir ortamda yapılır; ardından `hukuk.denetim_dogrula(kiraci)` ile denetim
zincirinin sağlam olduğu ve rastgele belgelerin SHA-256 özetlerinin kayıtlarla eşleştiği kontrol edilir.
