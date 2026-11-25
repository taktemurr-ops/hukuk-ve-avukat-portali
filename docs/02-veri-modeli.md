# Veri modeli (ilk taslak)

Her tabloda: `id`, `kiraci_id`, `olusturan`, `olusturma_zamani`, `guncelleyen`, `guncelleme_zamani`, `surum` (iyimser kilit). Silme yumuşaktır (`silindi_zamani`); kalıcı imha ayrı süreçtir.

## Kiracı ve organizasyon

| Varlık | Önemli alanlar |
| --- | --- |
| Kiraci | ad, hesap_turu (avukatlik_burosu / hukuk_burosu / kurumsal), lisans_profili, durum, kurulum_tipi (saas / ayrilmis / musteri_sunucusu) |
| TuzelKisilik | kiraci, unvan, vkn, mersis, ana_sirket (grup yapısı) |
| Birim | tuzel_kisilik, tur (sube / departman / ekip / is_birimi), ust_birim, masraf_merkezi |
| NumaraSerisi | tuzel_kisilik, belge_turu, onek, sonraki_no |
| Kullanici | e-posta, ad, durum, mfa, son_giris |
| Uyelik | kullanici, kiraci, roller, birimler |
| YetkiDevri | veren, alan, kapsam, baslangic, bitis, gerekce |

## Taraflar ve iş kabulü

| Varlık | Önemli alanlar |
| --- | --- |
| Kisi | tur (gercek / tuzel), tckn/vkn, ad/unvan, unvan_gecmisi, iletisim_tercihi |
| KisiIliskisi | kisi_a, kisi_b, iliski_turu (ortak, iştirak, yetkili, akraba) |
| CikarCatismasiKontrolu | aranan_kisiler, bulunan_eslesmeler, karar, gerekce, onaylayan |
| Vekaletname | muvekkil, avukatlar, alt_vekiller, noter, yevmiye_no, tarih, yetkiler (genel/özel liste), asil_evrak_yeri, durum (gecerli / azil / istifa) |

## Dosya, süre, görev

| Varlık | Önemli alanlar |
| --- | --- |
| Dosya | tur, yargi_kolu, mahkeme, esas_no, karar_no, ic_no, dis_referanslar, asama, dava_degeri, para_birimi, sorumlu, yedek_sorumlu, ekip, gizlilik_duzeyi |
| DosyaTaraf | dosya, kisi, sifat (davacı, davalı, borçlu, tanık, bilirkişi...) |
| Tebligat | dosya?, kanal (uets / kep / elektronik / fiziki / uyap), ulasma_tarihi, teblig_tarihi, orijinal_belge, eslesme_durumu |
| SureKurali | kod, surum, miktar, birim, yargi_kolu, dayanak, adli_tatilde_uzar, yururluk, onay_durumu, onaylayan |
| Sure | dosya, kural+surum, tetikleyen (tebligat/olay), baslangic, son_gun, hesap_adimlari (JSON), asil_sorumlu, yedek_sorumlu, teyit_eden, teyit_zamani, durum, onceki_hesap |
| Durusma | dosya, tarih_saat, yer, katilimcilar, tutanak, aksiyonlar |
| Gorev | dosya?, baslik, atanan, yedek, son_tarih, oncelik, kapanis_kaniti (işlem no / makbuz / belge) |
| Bildirim | alici, kanal, gonderildi, goruldu, teyit_edildi |

## Belge

| Varlık | Önemli alanlar |
| --- | --- |
| Belge | dosya/sozlesme, ad, tur, gizlilik |
| BelgeSurumu | belge, surum_no, depolama_anahtari, sha256, boyut, ocr_metni, orijinal_mi, imzali_mi |
| TeslimZinciri | belge_surumu, kimden, kime, zaman, aciklama |

## Finans

| Varlık | Önemli alanlar |
| --- | --- |
| UcretSozlesmesi | muvekkil, tur (sabit / yuzde / saatlik / asamali / abonelik), tutar, taksitler |
| CariHareket | muvekkil, dosya?, tur (avans / masraf / tahsilat / vekalet_ucreti), tutar, para_birimi, kur, belge |
| EmanetHareketi | muvekkil, dosya, tur (giris / muvekkile_aktarim), tutar, mutabakat_durumu |
| Makbuz | e-SMM no, tutar, kdv, stopaj, durum |

## Kurumsal

| Varlık | Önemli alanlar |
| --- | --- |
| Talep | talep_eden, birim, tur, form_verisi, oncelik, sla, atanan, durum, yeniden_acilma |
| Sozlesme | taraflar, tur, bedel, para_birimi, baslangic, bitis, otomatik_yenileme, fesih_bildirim_suresi, risk_puani, onay_durumu |
| SozlesmeAlani | sozlesme, alan, deger, kaynak_sayfa, guven, dogrulayan |
| Yukumluluk | sozlesme, aciklama, sahip, tarih, tekrar, gerceklesme_kaniti |
| Onay | nesne, adim, onayci, karar, zaman, yeniden_acilma_nedeni |
| RiskKaydi | dosya, talep_tutari, tahmini_risk, olasilik, onayli_karsilik, fiili_odeme, donem |

## Denetim

| Varlık | Önemli alanlar |
| --- | --- |
| DenetimOlayi | kiraci, kullanici, islem (goruntuleme / indirme / paylasim / degisiklik / silme / rol_verme / disa_aktarma / destek_erisimi), nesne, zaman, ip, onceki_ozet (hash zinciri) |

Denetim kayıtları yalnızca eklenir, değiştirilemez; her kayıt bir öncekinin özetini taşır.
