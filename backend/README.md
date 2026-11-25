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
| POST | `/kayit` | Yeni müşteri: kurum + kurucu kullanıcı + 14 gün deneme (şifre kuralları sunucuda da denetlenir) |
| GET | `/ben` | Kullanıcı, kurum ve roller |
| GET | `/kullanicilar` | Kurumdaki kullanıcılar ve rolleri |
| GET/POST | `/dosyalar` | Görünür dosyalar / yeni dosya (yıl bazında numara) |
| GET | `/dosyalar/{id}` | Dosya (görülemiyorsa 404; görüntüleme denetime yazılır) |
| GET/POST | `/dosyalar/{id}/sureler` | Süreler / süre hesapla ve kaydet (sunucuda hesaplanır, teyit bekler) |
| POST | `/sureler/{id}/teyit` | Teyit (hesaplayan kendisi teyit edemez) |
| POST | `/sureler/{id}/tamamla` | Kanıtla tamamlama |
| GET | `/denetim/dogrula` | Denetim zinciri sağlam mı |
| GET | `/taraflar` · POST `/dosyalar/{id}/taraflar` | Görünür dosyaların tarafları / taraf ekleme (dosya açarken `taraflar` da gönderilebilir) |
| GET/POST | `/gorevler` | Görevler / yeni görev |
| POST | `/gorevler/{id}/kapat` · `/iptal` | Kapatma (kritik süreden doğan görev kanıtsız kapanmaz, iptal edilemez) |
| GET/POST | `/durusmalar` · DELETE `/durusmalar/{id}` | Duruşmalar / ekleme (aynı avukatın çakışmaları uyarı olarak döner) / silme |
| GET/POST | `/tebligatlar` · POST `/tebligatlar/{id}/bagla` | Tebligatlar (tebliğ tarihi sunucuda, mükerrer kayıt engellenir) / dosyaya bağlama |
| GET/POST | `/vekaletnameler` · POST `/vekaletnameler/{id}/durum` | Vekâletnameler / azil, istifa, süre dolması (sona eren kilitlenir) |
| GET/POST | `/kisiler` | Kişiler / yeni kişi (TCKN/VKN ve e-posta doğrulanır) |
| GET | `/kisiler/{id}/cari` | Müvekkil carisi: avans bakiyesi, masraf, ücret alacağı ve hareketler |
| GET/POST | `/cari` | Tüm cari hareketler / yeni hareket (avans, masraf, iade, ücret tahakkuku/tahsilatı) |
| GET/POST | `/emanet` | Müvekkil parası hareketleri / yeni hareket (bakiye eksiye düşemez; ücret mahsubu onay ister) |
| GET/POST | `/zaman` | Zaman kayıtları (varsayılan son 30 gün) / yeni kayıt (ücret istemciden alınmaz) |
| POST | `/zaman/{id}/onayla` | Onay (kendi kaydını onaylayamaz — veritabanında zorlanır) |
| DELETE | `/zaman/{id}` | Kendi taslak kaydını silme |
| GET/POST | `/icra` | İcra dosyaları (tahsilatlarıyla) / yeni takip (akdi faizde oran zorunlu) |
| GET | `/icra/{id}?tarih=` | Kapak hesabı: faiz, masraf, harçlar, tahsilat mahsupları (masraf → faiz → anapara) |
| POST | `/icra/{id}/tahsilat` | Tahsilat ekleme |
| POST | `/icra/{id}/durum` | Takip aşaması (ve tebliğ tarihi) |
| GET/POST | `/sirketler` | Grup şirketleri (VKN doğrulanır; ekleme hukuk ekibine açık) |
| GET/POST | `/sozlesmeler` | Sözleşmeler ve uyarıları / yeni sözleşme (SZ-yıl-sıra numarası sunucuda) |
| POST | `/sozlesmeler/{id}/durum` | Durum geçişi; "onayda"ya geçiş yeni onay turu açar, imzaya yalnızca zincir tamamlanınca geçilir |
| POST | `/sozlesmeler/{id}/yukumlulukler` · `/yukumlulukler/{id}/tamamla` | Sözleşme yükümlülüğü ekleme / tamamlama |
| GET/POST | `/sozlesmeler/{id}/onay` | Onay zinciri (rollerden: hukuk, direktör, finans ≥1 M TL, genel müdür ≥5 M TL) / karar |
| GET/POST | `/talepler` | Talepler ve geçmişi / yeni talep (SLA iş günüyle hesaplanır, en az yüklü ekip üyesine atanır) |
| POST | `/talepler/{id}/durum` | Durum geçişi (bilgi beklemesi SLA'yı öteler, ret gerekçe ister) |
| POST | `/talepler/{id}/ata` | Hukuk ekibinden birine atama |
| POST | `/acik/ihbar/{kiraciId}` | **Oturumsuz** ihbar formu (yalnızca kurumsal hesaplar; kurum başına saatte 30); takip kodu bir kez döner |
| POST | `/acik/ihbar-durumu` | Takip koduyla durum (yalnızca aşama ve geri bildirim bilgisi; içerik yok) |
| GET/POST | `/ihbarlar` | Görülebilen ihbarlar, soruşturma ve notlarıyla / çalışan adına ihbar kaydı |
| POST | `/ihbarlar/{id}/sorusturma` | Soruşturma açma (hukuk direktörü / uyum sorumlusu; ihbar edilen kişi sorumlu olamaz) |
| POST | `/sorusturmalar/{id}/ekip` · `/not` · `/geri-bildirim` · `/durum` | Ekip, not, ihbarcıya geri bildirim, aşama (soruşturmaya al, raporla, reddet, kapat) |
| GET/POST | `/veri-ihlalleri` | Kişisel veri ihlalleri (72 saat sayacıyla) / yeni kayıt |
| POST | `/veri-ihlalleri/{id}/bildirim` | Kurul'a veya ilgililere bildirim zamanı (bir kez yazılır) |

Tutarlar istemciyle sunucu arasında kuruş cinsinden tam sayı olarak taşınır. Sunucudaki tüm SQL metinleri CI'da
şemaya karşı `PREPARE` edilir (`araclar/sql_denetim.py`).

Sunucu henüz derlenmedi (geliştirme ortamında Dart yok); ilk derleme ve `dart test` CI'da veya yerelde yapılacak.
