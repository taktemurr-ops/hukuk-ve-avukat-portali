"""Haftalık özet: haftada bir, kapatılabilir, müvekkil/dosya bilgisi içermez."""


def test_haftalik_ozet(uygulama, veri, yonetici):
    hafta = "2026-12-07"  # pazartesi; Cevap dilekçesi 09.12, Gizli süre 10.12
    n = uygulama.deger("SELECT hukuk.haftalik_ozetleri_yaz(%s, 'https://app.ornek/')", hafta)
    assert n >= 2
    metin = yonetici.execute("SELECT metin FROM hukuk.eposta_kuyrugu WHERE alici = 'mert@ornek.com.tr' AND tur = 'haftalikOzet' "
                             "AND kiraci_id = %s", (veri["k1"],)).fetchone()[0]
    assert "Bu hafta son günü dolan süre: 1" in metin
    assert "Cevap" not in metin and "2026/1" not in metin and "Açık dosya" not in metin
    ayse = yonetici.execute("SELECT metin FROM hukuk.eposta_kuyrugu WHERE alici = 'ayse@ornek.com.tr' AND tur = 'haftalikOzet' "
                            "AND kiraci_id = %s", (veri["k1"],)).fetchone()[0]
    assert "Kurum geneli" in ayse
    # Aynı hafta ikinci kez gitmez; kapatan kullanıcıya gitmez.
    uygulama.oturum(veri["k1"], veri["elif"]).c.execute("SELECT hukuk.haftalik_ozet_tercihi(false)")
    uygulama.c.execute("SELECT hukuk.haftalik_ozetleri_yaz(%s, NULL)", (hafta,))
    assert yonetici.execute("SELECT count(*) FROM hukuk.eposta_kuyrugu WHERE alici = 'mert@ornek.com.tr' AND tur = 'haftalikOzet' "
                            "AND kiraci_id = %s", (veri["k1"],)).fetchone()[0] == 1
    uygulama.c.execute("SELECT hukuk.haftalik_ozetleri_yaz('2026-12-14', NULL)")
    assert yonetici.execute("SELECT count(*) FROM hukuk.haftalik_ozet_gonderimi WHERE kullanici_id = %s",
                            (veri["elif"],)).fetchone()[0] <= 1
