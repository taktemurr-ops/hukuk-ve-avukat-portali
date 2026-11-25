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
| ☑ | Sunucu iskeleti: Serverpod yerine shelf + postgres, SQL göçleri (`backend/README.md`) | C |
| ◐ | Sunucu uçları: kimlik, dosya, süre, kişi, cari, emanet, zaman, icra (kapak hesabı, tahsilat, aşama) hazır; SQL'ler şemaya karşı doğrulandı. Kurumsal: grup şirketi, sözleşme (sunucuda tarama, durum, onay zinciri) ve talep (SLA, otomatik atama, geçmiş) uçları hazır. Uygulama sunucu modunda bu modülleri sunucudan okur ve yazar; kurumsal hesapta demo verisi kullanılmaz. Uyum (açık ihbar formu, takip kodu, soruşturma, veri ihlali 72 saat) sunucuda ve uygulamada hazır. Bekleyenler: sözleşme yükümlülükleri, dış avukat ve toplu takip uçları; Dart derlemesi | C |
| ☐ | Flutter web prototipi: büyük tablo, editör, klavye ölçümü | C + K |
| ☐ | Şirket kuruluşu ve ortaklık sözleşmesi; Av. K. m.11 kontrolü | K + A |

## Sprint 1–2 — Kimlik ve organizasyon

| Durum | İş |
| --- | --- |
| ◐ | Kayıt, hesap türü seçimi, e-posta doğrulama, aktivasyon, şifre belirleme — arayüz ve doğrulama kuralları hazır (TCKN/VKN, şifre, telefon); sunucu bağlantısı bekliyor |
| ◐ | Giriş, iki adımlı doğrulama, şifre sıfırlama, oturum yönetimi — giriş, şifremi unuttum, 5 hatalı denemede kilit, TOTP (RFC 6238 vektörleriyle doğrulandı) ve 2FA kurulum ekranı hazır; girişte kod sorma ve sunucu bekliyor |
| ◐ | Kiracı, tüzel kişilik, birim, kullanıcı, rol, davet — davet kodu, 72 saat geçerlilik, ücretsiz roller ve koltuk kontrolü ve Ekip ve davetler ekranı hazır; davet e-postası ve sunucu bekliyor |
| ◐ | Yetki fonksiyonu (tek kapı) + denetim kaydı — yetki denetçisi ve rol/işlem matrisi hazır; zincirli (SHA-256) denetim kaydı, doğrulama ve Denetim Kaydı ekranı hazır; sunucuda kalıcı saklama bekliyor |
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
| ◐ | Temel sözleşme kaydı ve onayı — sözleşme kaydı, durum akışı (taslak→müzakere→onay→imza→yürürlük), yükümlülük takibi, ihbar/yenileme uyarıları ve ekranlar hazır; çok adımlı onay zinciri (hukuk → yüksek riskte/taramasızda hukuk direktörü → 1 milyon TL ve dövizde finans → 5 milyon TL'de genel müdür; eşikler taslak), aynı kişinin iki adımı onaylayamaması, gerekçeli ret/revizyon, onayınızı bekleyenler ve bildirimi hazır; e-imza bekliyor |
| ◐ | Otomatik sözleşme taraması (Faz 2'den öne alındı) — kural tabanlı tarama: tür, taraflar, tarihler, süre, otomatik yenileme, ihbar süresi, bedel, vade, yetkili mahkeme, uygulanacak hukuk, tahkim; 14 risk/eksik madde kuralı ve alıntı. PDF/Word/OCR ve yapay zekâ destekli tarama Python servisi bekliyor; kurallar avukat kontrolü bekliyor |
| ◐ | Kurumsal hukuk talepleri (Faz 2'den öne alındı) — talep formu, türe göre otomatik atama (iş yükü dengeli), iş günü bazlı SLA, bilgi beklerken SLA durdurma, ret gerekçesi, geçmiş; ekranlar hazır. E-posta/Teams ile talep alma bekliyor |

## Arayüz

| Durum | İş |
| --- | --- |
| ☑ | Tasarım sistemi (docs/06-tasarim.md): lacivert yan menü, Genel Bakış, durum rozetleri, gömülü fontlar |

## Sprint 11–12 — Satış ve canlıya hazırlık

| Durum | İş |
| --- | --- |
| ◐ | Tanıtım sitesi, demo hesabı ve örnek veri — statik site (site/), üç hesap türü için demo girişi ve örnek veri hazır; form gönderimi ve fiyatların kesinleşmesi bekliyor |
| ◐ | Ödeme, abonelik, e-fatura, başarısız ödeme akışı — abonelik yaşam döngüsü (14 gün deneme, aylık/yıllık, 1-3-7. gün tekrar deneme, askı, dönem sonu iptal, kıst koltuk farkı, KDV) ve ekranı hazır; yurt içi ödeme kuruluşu ve e-Arşiv entegrasyonu bekliyor |
| ◐ | Veri aktarım sihirbazı (Excel/CSV, DavaTek/UYAP çıktıları) — CSV müvekkil aktarımı (sütun tahmini, TCKN/VKN, mükerrer, mutabakat) hazır; Excel ve UYAP çıktıları bekliyor |
| ☐ | Kabul testleri, sızma testi, yedekten geri dönüş testi |
| ☐ | 5–10 pilot büro |

## Faz 2'den öne alınanlar (25.11.2026)

| Durum | İş |
| --- | --- |
| ◐ | Raporlar — iş yükü (kişi bazlı), açık süre dağılımı, ücret alacağı yaşlandırma (FIFO) ve masraf alacağı, talep performansı (SLA uyumu, ortalama çözüm), sözleşme risk ve bitiş özeti; CSV kopyalama denetim kaydına yazılır. PDF/Excel çıktısı ve zamanlanmış rapor e-postası bekliyor |
| ◐ | Müvekkil portalı — yalnızca davetle; büro dosya bazında paylaşır, belge bazında paylaşır; müvekkil dosya özeti, sonraki duruşma, paylaşılan belgeler ve yazışmayı görür; süre, görev, iç not ve ekip görünmez; okundu bilgisi, denetim kaydı. Gerçek davet akışı, bildirim e-postası ve belge indirme sunucu bekliyor |
| ◐ | Zaman kaydı ve gelir paylaşımı (Hukuk Bürosu) — kronometre (duraklatılabilir), elle kayıt (dk, 1:30, 1,5 saat), 6 dakikalık faturalama birimi, kişi/dosya bazlı saatlik ücret, 24 saat ve ileri tarih kontrolü, kendi kaydını onaylayamama, fatura taslağı ve müvekkil carisine tahakkuk; gelir paylaşımı (getiren/çalışan/büro, süre oranında, kuruş farkı büroya). Paylaşım oranlarının ayarlardan değiştirilmesi bekliyor |
| ◐ | İcra takibi — takip türleri (ilamsız, kambiyo, kira, ilamlı, rehin), işlemiş faiz (yasal/avans), 2026 icra harçları (başvurma 732 TL, binde 5 peşin, %4,55/%9,10/%11,38 tahsil, %2 cezaevi), kısmi ödemelerin masraf → faiz → asıl alacak sırasıyla mahsubu, takip sonrası faizin yalnızca kalan asıl alacağa işlemesi, peşin harcın tahsil harcına mahsubu, fazla ödeme uyarısı; dosya hesabı ekranı, tahsilat, durum. Toplu takip (Hukuk Bürosu): Excel'den yapıştırma, satır doğrulama, her borçlu için dosya ve takip. UYAP'a takip gönderimi ve icra AAÜT ücretinin hukuki kontrolü bekliyor |
| ◐ | Etik duvar (Hukuk Bürosu) — dosya bazında kullanıcı engelleme; en yetkili rolü bile engeller; ekipteki kişi önce ekipten çıkarılmalı; kurma ve kaldırma gerekçeli ve denetim kaydında; geçmiş silinmez; engellenen kişi dosyayı liste, arama, rapor ve bildirimlerde göremez |
| ◐ | Bildirim merkezi — süre uyarıları (alıcıya göre), 48 saat içindeki duruşmalar, eşleşmeyen tebligatlar, okunmamış müvekkil mesajları, kurumsalda riskli/geciken talepler ve sözleşme tarihleri; yetki tek kapıdan; okundu bilgisi; telefon bildirimi içerik taşımaz. E-posta ve telefon bildirim gönderimi sunucu bekliyor |
| ◐ | KVKK saklama ve imha — kategori bazlı saklama süreleri (taslak), kapanıştan itibaren imha tarihi, yasal saklama engeli, imhaya hazır kayıtların seçimi, imha tutanağı (silme/yok etme/anonimleştirme), dört göz onayı, 6 aylık periyodik imha takibi ve gecikme uyarısı. Sürelerin büro politikasıyla kesinleşmesi ve belge servisinde gerçek silme bekliyor |
| ◐ | Dış avukat yönetimi (Kurumsal) — dış büro kayıtları, iş ve bütçe, fatura girişi (mükerrer no engeli), onay/ret (gerekçeli), bütçeyi aşan onayın engellenmesi ve gerekçeli bütçe artışı, %80 uyarısı, finansa gönderim, büro bazında harcama özeti. Dış avukat portalı (faturayı dış avukatın yüklemesi) ve e-fatura eşleştirme bekliyor |
| ◐ | Grup şirketleri (Kurumsal) — şirket ağacı (döngü ve bilinmeyen ana şirket engeli, mükerrer VKN engeli), üst bardan şirket seçimi, sözleşme/talep/raporların seçilen şirket ve alt şirketleriyle süzülmesi, şirket ekleme. Kullanıcı bazlı şirket yetkisi sunucuda bekliyor |
| ◐ | Uyum ve iç soruşturma (Kurumsal) — ihbar kaydı (anonim, takip kodu, içerik denetim kaydına yazılmaz), soruşturma (ihbar edilen kişi sorumlu/ekip olamaz, yalnızca ekip erişir), ön inceleme/soruşturma/raporlama/kapanış, ihbarcıya 7 gün ve sonuç için 90 gün hedefi (kurum politikası, taslak), notlar; kişisel veri ihlalinde Kurul'a 72 saat bildirim takibi (KVKK Kurulu 2019/10). İhbarcının takip koduyla giriş yaptığı dış ihbar formu bekliyor |
| ◐ | Belge servisi (Python) — PDF/Word/UDF/görüntü/metinden metin çıkarma, taranmış PDF ve görüntüde Türkçe OCR, SHA-256, Word çıktısı (eksik alanlar sarı vurgulu), dosya güvenliği (25 MB, içerikten tür tespiti, şifreli ve zip bombası reddi); 13 test burada çalıştırıldı ve geçti. PDF ve UDF çıktısı, uygulama sunucusuyla bağlantı bekliyor |
| ◐ | Veritabanı şeması (PostgreSQL 16) — kiracı, kullanıcı, rol, kişi, dosya, ekip, etik duvar, süre, belge ve sürüm, denetim kaydı; satır düzeyi güvenlikle müşteri ayrımı, gizli dosya ve etik duvar (uygulamayla aynı kural), dört göz ve kanıt kısıtları, değiştirilemez denetim kaydı ve belge sürümü, SHA-256 denetim zinciri ve doğrulama, veri bölgesi yalnızca TR; ikinci göçle finans (emanet eksiye düşmez), zaman kaydı, grup şirketi, sözleşme ve onay, hukuk talebi, icra, ihbar ve soruşturma (yalnızca ekip görür), davet ve abonelik tabloları; giriş ve oturum fonksiyonları (token özeti, kilit, pasifleştirmede oturum kapanışı); 18 test gerçek PostgreSQL'de çalıştırıldı ve geçti. API katmanı bekliyor |
| ◐ | Uygulama sunucusu (Dart, shelf + postgres; Serverpod yerine — gerekçe backend/README.md) — Argon2id şifre (referans vektörle test), oturum token'ı (yalnızca özeti saklanır), kullanıcı varlığını sızdırmayan giriş, çok kurumlu hesapta kurum seçimi, kiracı bağlamının işlem başına ayarlanması, dosya listesi/oluşturma/ayrıntı, sunucuda süre hesabı ve kaydı, teyit ve kanıtla tamamlama, denetim zinciri doğrulama, güvenlik başlıkları, CORS, Türkçe hata eşlemesi. Henüz derlenmedi; diğer modüllerin uçları ve Flutter istemcisinin bağlanması bekliyor |
| ◐ | Uygulamanın sunucuya bağlanması — `--dart-define=SUNUCU_ADRESI=...` ile sunucu modu: giriş (çok kurumlu hesapta kurum seçimi), kayıt, çıkış; girişten sonra dosya, süre ve kullanıcılar sunucudan yüklenir; dosya açma, tebligattan süre hesaplama (sunucuda), teyit ve kanıtla tamamlama sunucuda yapılır ve sonra yeniden yüklenir. Demo modu aynen çalışır. Diğer modüller (finans, sözleşme, icra…) için sunucu uçları bekliyor |
| ☑ | Statik denetim araçları (araclar/): Dart sözdizimi, isim çakışması, import/Key bağlantısı, adlandırılmış argüman — Dart derleyicisi olmayan ortamda ilk savunma hattı; iki gerçek derleme hatası yakalandı ve düzeltildi |
