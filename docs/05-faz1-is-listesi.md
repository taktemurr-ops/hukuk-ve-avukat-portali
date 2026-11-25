# Faz 1 iş listesi

Durum: ☐ başlamadı · ◐ sürüyor · ☑ bitti. Sorumlu: K = kurucu, A = avukat, C = Claude.

## Sprint 0 — Temel (2 hafta)

| Durum | İş | Sorumlu |
| --- | --- | --- |
| ☑ | Depo yapısı, CI, çekirdek paket | C |
| ☑ | Süre hesaplama motoru (ilk sürüm) + testler | C |
| ☐ | Süre kuralları, tatil verisi ve ayarların hukuki kontrolü (arife, hafta sonu, icra ve idari yargıda adli tatil) | A |
| ☐ | Avukatın yazacağı 100+ süre senaryosu → otomatik test | A + C |
| ☐ | Türkiye'de sunucu sağlayıcısı seçimi | K |
| ☐ | Ödeme kuruluşu seçimi ve üye işyeri başvurusu | K |
| ☐ | Serverpod projesinin üretilmesi (`backend/README.md`) | K + C |
| ☐ | Flutter web prototipi: büyük tablo, editör, klavye ölçümü | C + K |
| ☐ | Şirket kuruluşu ve ortaklık sözleşmesi; Av. K. m.11 kontrolü | K + A |

## Sprint 1–2 — Kimlik ve organizasyon

| Durum | İş |
| --- | --- |
| ◐ | Kayıt, hesap türü seçimi, e-posta doğrulama, aktivasyon, şifre belirleme — arayüz ve doğrulama kuralları hazır (TCKN/VKN, şifre, telefon); sunucu bağlantısı bekliyor |
| ◐ | Giriş, iki adımlı doğrulama, şifre sıfırlama, oturum yönetimi — giriş, şifremi unuttum, 5 hatalı denemede kilit hazır; iki adımlı doğrulama ve sunucu bekliyor |
| ☐ | Kiracı, tüzel kişilik, birim, kullanıcı, rol, davet |
| ◐ | Yetki fonksiyonu (tek kapı) + denetim kaydı — yetki denetçisi ve rol/işlem matrisi hazır; denetim kaydı bekliyor |
| ☐ | Lisans profili ve modül açma-kapama |

## Sprint 3–4 — Müvekkil, iş kabulü, vekâlet

| Durum | İş |
| --- | --- |
| ◐ | Kişi/taraf kartı, ilişkiler, mükerrer birleştirme — çekirdek kurallar (Türkçe isim eşleştirme, unvan geçmişi, birleştirme) ve liste/arama/yeni kişi ekranı hazır; düzenleme, ilişki ekranı ve sunucu bekliyor |
| ◐ | Çıkar çatışması taraması, gerekçeli karar ve onay — tarayıcı (kimlik no, aynı/benzer isim, ilişkili kişi, gizli dosya maskeleme) ve karar ekranı hazır; denetim kaydı ve sunucu bekliyor |
| ◐ | Vekâletname, alt vekil, işlem öncesi yetki kontrolü, yetki belgesi — kurallar (HMK m.74 özel yetkiler, tevkil) ve kontrol ekranı hazır; vekâletname ekleme formu, yetki belgesi çıktısı ve özel yetki listesinin avukat kontrolü bekliyor |

## Sprint 5–7 — Dosya, süre, görev, tebligat

| Durum | İş |
| --- | --- |
| ◐ | Dosya kartı, taraflar, aşamalar, bağlı dosyalar — model, iç numara serisi, liste (yetki filtreli) ve detay ekranı hazır; dosya açma formu bekliyor |
| ◐ | Tebligat kaydı (manuel), eşleşmeyen evrak kuyruğu — ulaşma/tebliğ ayrımı, mükerrer engeli, esas no + mahkeme + taraf ile eşleştirme, kuyruk ve bağlama ekranı hazır |
| ◐ | Süre oluşturma, teyit, asıl/yedek sorumlu, eskalasyon, yeniden hesap — kurallar (iki kişi teyidi, kanıtla tamamlama, eski hesabı saklama, eskalasyon, devir listesi) ve ekranlar hazır; bildirim gönderimi sunucu bekliyor |
| ◐ | Duruşma, çakışma uyarısı, takvim — çakışma (yol süresi dahil) ve takvim görünümü hazır; duruşma ekleme formu ve Google/Outlook senkronu bekliyor |
| ◐ | Görev, iş akışı şablonları, kanıtla kapanış — model, 2 şablon (iş davası, icra takibi), kanıtla kapanış hazır; şablon düzenleyici bekliyor |
| ☐ | Bildirim servisi (e-posta, SMS, push sinyali) ve tercihler |

## Sprint 8–10 — Belge, şablon, finans

| Durum | İş |
| --- | --- |
| ◐ | Belge yükleme, sürüm, hash, zararlı dosya taraması, OCR, arama — sürüm ve SHA-256 bütünlük, izinli dosya türleri, dosyada belge listesi hazır; gerçek dosya yükleme, zararlı dosya taraması ve OCR sunucu bekliyor |
| ◐ | Şablon motoru, DOCX/PDF/UDF çıktı — alan birleştirme, koşullu blok, eksik alan raporu ve 3 taslak şablon (mazeret, ihtarname, ücret sözleşmesi) hazır; DOCX/PDF/UDF dönüşümü Python servisi bekliyor; şablon metinleri avukat onayı bekliyor |
| ◐ | Hesaplama araçları (faiz, harç, AAÜT, döviz) — dönemsel yasal faiz (%9/%24/%31), avans faizi, 2026 harçları, AAÜT 2025-26 ve 2026-27, makbuz hesabı hazır; avans faizi geçmişi, döviz ve işçilik alacakları bekliyor; tüm tarifeler avukat onayı bekliyor |
| ◐ | Cari hesap, emanet hesabı, ücret sözleşmesi, e-SMM — cari (avans/masraf/ücret), emanet (eksiye düşmeme, onaylı mahsup, bekleme uyarısı) ve Finans ekranı hazır; e-SMM entegratör bağlantısı bekliyor |
| ☐ | Temel sözleşme kaydı ve onayı |

## Arayüz

| Durum | İş |
| --- | --- |
| ☑ | Tasarım sistemi (docs/06-tasarim.md): lacivert yan menü, Genel Bakış, durum rozetleri, gömülü fontlar |

## Sprint 11–12 — Satış ve canlıya hazırlık

| Durum | İş |
| --- | --- |
| ☐ | Tanıtım sitesi, demo hesabı ve örnek veri |
| ☐ | Ödeme, abonelik, e-fatura, başarısız ödeme akışı |
| ☐ | Veri aktarım sihirbazı (Excel/CSV, DavaTek/UYAP çıktıları) |
| ☐ | Kabul testleri, sızma testi, yedekten geri dönüş testi |
| ☐ | 5–10 pilot büro |
