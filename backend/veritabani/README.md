# Veritabanı şeması (PostgreSQL 16)

`migrations/` altındaki SQL dosyaları `goc.py` ile sırayla, her biri tek işlemde uygulanır (uygulananlar `public.hukuk_goc`'ta; uygulanmış dosya değiştirilemez). Şema, uygulama sunucusundan bağımsız olarak veri güvenliğini
veritabanı seviyesinde de garanti eder:

| Kural | Nasıl |
| --- | --- |
| Müşteriler birbirinin verisini göremez | Her tabloda satır düzeyi güvenlik (RLS); uygulama her işlemde `app.kiraci_id` ve `app.kullanici_id` ayarlar. Ayarlanmazsa hiçbir satır görünmez |
| Gizli dosya ve etik duvar | Uygulamadaki yetki denetçisiyle aynı kural RLS'te de var; görünmeyen dosyanın süresi ve belgesi de görünmez |
| Dört göz | Süreyi hesaplayan kendisi teyit edemez; tamamlanan süre kanıtsız kapanamaz |
| Değiştirilemez kayıtlar | Uygulama rolü denetim kaydını ve belge sürümlerini güncelleyemez, silemez; etik duvar silinmez, yalnızca gerekçeyle kaldırılır |
| Denetim zinciri | Her kayıt öncekinin SHA-256 özetini taşır; `hukuk.denetim_dogrula(kiraci)` zincir bozulduysa ilk bozuk sırayı döner (veritabanı yöneticisinin müdahalesi de görünür) |
| Veri yalnızca Türkiye'de | `kiraci.veri_bolgesi` yalnızca `TR` olabilir |
| Şifre | Yalnızca Argon2id özeti kabul edilir |
| Emanet | Müvekkil parası (müvekkil + dosya bazında) eksiye düşemez; mahsup yazılı onay ister |
| Zaman kaydı | Günlük 24 saat sınırı, kendi kaydını onaylayamama, faturalanmış kaydın değiştirilememesi |
| Sözleşme onayı | Aynı turda bir kişi yalnızca bir adımı onaylayabilir; ret/revizyon gerekçe ister |
| İhbar ve soruşturma | İhbarı kaydeden sonradan göremez; içerik yalnızca soruşturma ekibine açılır; ihbar edilen kişi soruşturmada yer alamaz |
| Davet | Kodun yalnızca özeti saklanır; 72 saat geçerlidir |
| Hesap açma | Kurum, kurucu kullanıcı (hesap türüne göre rol) ve 14 günlük deneme tek işlemde; ilk denetim kaydı |
| Giriş ve oturum | Oturum token'ının yalnızca özeti saklanır; 15 dakikada 5 hatalı denemede kilit; süresi dolan, kapatılan veya pasifleştirilen kullanıcının oturumu geçersiz |

Uygulama sunucusu veritabanına `hukuk_uygulama` rolüyle bağlanır (tablo sahibi değildir, RLS'ten muaf değildir).
Yeni müşteri kaydında uygulama önce yeni kiracı kimliğini üretir, `app.kiraci_id`'yi ona ayarlar, sonra ekler.

## Testler

Gerçek PostgreSQL'e karşı çalışır (53 test):

```bash
pip install "psycopg[binary]" pytest
PG_DSN="host=localhost port=5432 user=postgres password=..." python -m pytest -q
```
