"""Dış avukat portalı: yalnızca bağlı büronun işleri; fatura yükleme; kurum tablolarına erişim yok."""
import uuid

import psycopg
import pytest

from conftest import OZET


def _portal(u, kullanici):
    u.c.execute("SELECT set_config('app.kiraci_id', '', false), set_config('app.kullanici_id', %s, false)", (str(kullanici),))
    return u


def test_dis_avukat_portali(uygulama, veri, yonetici):
    k = veri["k1"]
    dis_kul, direktor = uuid.uuid4(), uuid.uuid4()
    for kid, rol in [(dis_kul, "disAvukat"), (direktor, "hukukDirektoru")]:
        yonetici.execute("INSERT INTO hukuk.kullanici (id, kiraci_id, eposta, ad_soyad, sifre_ozeti) VALUES (%s, %s, %s, 'x', %s)",
                         (kid, k, f"{kid}@ornek.com.tr", OZET))
        yonetici.execute("INSERT INTO hukuk.kullanici_rol VALUES (%s, %s, %s)", (k, kid, rol))
    assert yonetici.execute("SELECT hukuk.yalniz_dis_avukat(%s), hukuk.yalniz_dis_avukat(%s)", (dis_kul, direktor)).fetchone() == (True, False)
    u = uygulama.oturum(k, direktor)
    dolu = u.c.execute("SELECT dolu FROM hukuk.koltuk_durumu()").fetchone()[0]
    yonetici.execute("UPDATE hukuk.kullanici_rol SET rol = 'avukat' WHERE kullanici_id = %s", (dis_kul,))
    assert u.c.execute("SELECT dolu FROM hukuk.koltuk_durumu()").fetchone()[0] == dolu + 1  # dış avukat koltuk tüketmez
    yonetici.execute("UPDATE hukuk.kullanici_rol SET rol = 'disAvukat' WHERE kullanici_id = %s", (dis_kul,))
    kaya = u.deger("INSERT INTO hukuk.dis_avukat (kiraci_id, buro, sorumlu_avukat, eposta) "
                   "VALUES (%s, 'Kaya Hukuk', 'Av. Deniz Kaya', 'deniz@kaya.av.tr') RETURNING id", k)
    diger = u.deger("INSERT INTO hukuk.dis_avukat (kiraci_id, buro, sorumlu_avukat, eposta) "
                    "VALUES (%s, 'Ak Hukuk', 'Av. Can Ak', 'can@ak.av.tr') RETURNING id", k)
    isim = u.deger("INSERT INTO hukuk.dis_avukat_isi (kiraci_id, dis_avukat_id, konu, ilk_butce_kurus) "
                   "VALUES (%s, %s, 'Rekabet soruşturması', 500000) RETURNING id", k, kaya)
    baska_is = u.deger("INSERT INTO hukuk.dis_avukat_isi (kiraci_id, dis_avukat_id, konu, ilk_butce_kurus) "
                       "VALUES (%s, %s, 'Vergi davası', 500000) RETURNING id", k, diger)

    # Bağlamadan önce portal boş; rolsüz kullanıcı bağlanamaz; avukat rolü bağlayamaz.
    assert _portal(uygulama, dis_kul).c.execute("SELECT count(*) FROM hukuk.dis_portal_isleri()").fetchone()[0] == 0
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        uygulama.oturum(k, veri["mert"]).c.execute("SELECT hukuk.dis_avukat_hesabi_bagla(%s, %s)", (kaya, dis_kul))
    with pytest.raises(psycopg.errors.CheckViolation):
        uygulama.oturum(k, direktor).c.execute("SELECT hukuk.dis_avukat_hesabi_bagla(%s, %s)", (kaya, veri["mert"]))
    uygulama.oturum(k, direktor).c.execute("SELECT hukuk.dis_avukat_hesabi_bagla(%s, %s)", (kaya, dis_kul))

    p = _portal(uygulama, dis_kul)
    assert p.liste("SELECT konu FROM hukuk.dis_portal_isleri()") == ["Rekabet soruşturması"]
    assert p.deger("SELECT count(*) FROM hukuk.dis_avukat_isi") == 0  # kurum tabloları görünmez
    assert p.deger("SELECT count(*) FROM hukuk.dosya") == 0
    f = p.deger("SELECT hukuk.dis_portal_fatura_ekle(%s, 'KH-1', current_date, 120000, 'Ekim')", isim)
    assert p.liste("SELECT durum FROM hukuk.dis_portal_faturalari(%s)", isim) == ["bekliyor"]
    with pytest.raises(psycopg.errors.NoDataFound):
        p.c.execute("SELECT hukuk.dis_portal_fatura_ekle(%s, 'X-1', current_date, 1, '')", (baska_is,))
    assert p.liste("SELECT no FROM hukuk.dis_portal_faturalari(%s)", baska_is) == []
    with pytest.raises(psycopg.errors.CheckViolation):
        p.c.execute("SELECT hukuk.dis_portal_fatura_ekle(%s, 'KH-2', current_date + 3, 1, '')", (isim,))
    assert p.c.execute("SELECT bekleyen_kurus FROM hukuk.dis_portal_isleri()").fetchone()[0] == 120000

    # Kurum faturayı görür; dış avukatın hesabı pasifleşince portal kapanır.
    assert uygulama.oturum(k, direktor).deger("SELECT ekleyen FROM hukuk.dis_avukat_faturasi WHERE id = %s", f) == dis_kul
    yonetici.execute("UPDATE hukuk.dis_avukat SET aktif = false WHERE id = %s", (kaya,))
    assert _portal(uygulama, dis_kul).deger("SELECT hukuk.dis_avukat_kimligi(%s)", dis_kul) is None
