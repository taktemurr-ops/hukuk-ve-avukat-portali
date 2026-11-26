# İç güvenlik ve sızma testi (26.11.2026)

Kapsam: veritabanı (satır güvenliği, yetkiler), Dart uygulama sunucusu, Python belge servisi, tanıtım ve ihbar sayfaları,
istemci, Docker kurulumu. Yöntem: kod incelemesi + saldırgan gözüyle otomatik denemeler. Denemeler CI'da her değişiklikte
tekrar çalışır (`araclar/guvenlik_testi.py`, `backend/veritabani/tests/test_kiracilar_arasi.py`,
`backend/sunucu/test/guvenlik_test.dart`, `services/belge/tests/test_guvenlik_saldiri.py`).

## Bulunan ve kapatılan açıklar

| Önem | Bulgu | Düzeltme |
| --- | --- | --- |
| Yüksek | Yabancı anahtar denetimi satır güvenliğini aşıyordu: bir kurum, başka kurumun kayıt kimliğini bilirse kendi kaydını ona bağlayabiliyordu (ör. portal paylaşımıyla başka kurumun dosyasını kendi müvekkiline göstermek, başka kurumun dosyasına belge eklemek). | `0033`: kiraci_id taşıyan tüm bağlantılarda aynı kurum zorunlu (38 tablo, tetikleyiciyle). |
| Yüksek | Oturumsuz uçlarda hız sınırı yoktu; çok sayıda hesap denenebiliyor, her giriş denemesi Argon2 ile sunucuyu meşgul ediyordu. | IP başına hız sınırı: kimlik uçları 10 dakikada 30, diğer açık uçlar dakikada 60 istek; IP bellekte tuzlu özetle tutulur, kaydedilmez. Şifre en fazla 256 karakter. |
| Orta | İstek gövdesi önce tamamen belleğe alınıp sonra boyutu denetleniyordu (büyük istekle bellek tüketme). | Gövde akış hâlinde ve sınırla okunur (JSON 1 MB, ödeme bildirimi 64 KB). |
| Orta | Belge servisinde UDF içeriği standart XML ayrıştırıcıyla okunuyordu (varlık bombası/XXE riski); görüntü piksel sınırı uyarı düzeyindeydi; rapor satır sayısı sınırsızdı. | defusedxml; 40 megapiksel sınırı (görüntü açılmadan); OCR zaman aşımı; rapor en fazla 100.000 satır. |
| Orta | `ORTAM` boş bırakılırsa sahte ödeme, SMTP'siz ve virüs taramasız başlatma serbestti. | Açıkça `gelistirme`/`test` değilse canlı kabul edilir; docker-compose varsayılanı `canli`. |
| Orta | Veritabanı ve belge servisi internete çıkabilen ağdaydı; kapsayıcılar tam yetkiliydi. | İç ağ `internal`; belge servisi ve sunucu salt okunur dosya sistemi, yetkiler düşürülmüş, belge servisinde bellek/süreç sınırı. |
| Düşük | Veritabanı fonksiyonları PUBLIC'e açıktı. | Yalnızca uygulama rolü; ileride eklenenler için de varsayılan kapalı. |
| Düşük | Bozuk yüzde kodlu dosya adı 500 hatası veriyordu; dosya adında satır sonu/NUL denetlenmiyordu. | 400 ile reddedilir. |
| Düşük | API yanıtlarında içerik güvenlik politikası yoktu; ödeme isteğinde IP sahtelenebilir başlıktan alınıyordu. | `Content-Security-Policy: default-src 'none'; frame-ancestors 'none'; sandbox`, `Permissions-Policy`, `Cross-Origin-Resource-Policy`; IP yalnızca güvenilir vekilden. |
| Düşük | Tanıtım ve ihbar sayfalarında içerik güvenlik politikası yoktu. | Betik özetli CSP (CI'da denetlenir). |

## Denenip güvenli bulunanlar

Oturumsuz/sahte oturumla erişim, kurumlar arası dosya/rol/denetim erişimi, SQL enjeksiyonu (arama, yol, giriş), çalıştırılabilir
ve HTML dosya yükleme, yol geçişi, CORS, iç hata ayrıntısı sızması, çıkış sonrası token, kaba kuvvet. Token'lar 256 bit, kodlar
128 bit rastgele ve yalnızca özetleri saklanıyor; şifreler Argon2id; oturum token'ı istemcide yalnızca bellekte.

## Kalan ve dış test gerektirenler

- Canlı ortamda bağımsız bir firmaya sızma testi (TLS yapılandırması, ters vekil, sunucu sertleştirme dahil).
- Flutter web uygulamasının sunulduğu alan adında içerik güvenlik politikası (ters vekilde).
- Bağımlılık açık taraması (Dependabot / `pip-audit`, `dart pub outdated`) düzenli çalıştırılmalı.
- Hesap kilidi (5 hatalı girişte 15 dk) bir saldırganın belirli bir kullanıcıyı geçici kilitlemesine izin verir; bilinçli denge.
