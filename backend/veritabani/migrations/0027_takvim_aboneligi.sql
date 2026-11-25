-- Takvim aboneliği (Google/Outlook/Apple takvimine iCal bağlantısı). Bağlantı kişiye özeldir; yalnızca özeti
-- saklanır, bir kez gösterilir; yenilenince eskisi geçersizleşir. Akışta müvekkil adı ya da dosya başlığı yoktur
-- (dış takvim sağlayıcısı Türkiye dışında olabilir): yalnızca dosya iç numarası, mahkeme/yer ve saat.
-- Akış kullanıcının kendi yetkisiyle üretilir (RLS): bağlantı sahibinin göremediği dosya akışa girmez.
BEGIN;

CREATE TABLE hukuk.takvim_aboneligi (
  kullanici_id uuid PRIMARY KEY REFERENCES hukuk.kullanici(id),
  kiraci_id    uuid NOT NULL REFERENCES hukuk.kiraci(id),
  token_ozeti  char(64) NOT NULL UNIQUE,
  olusturma    timestamptz NOT NULL DEFAULT now(),
  son_okuma    timestamptz
);
ALTER TABLE hukuk.takvim_aboneligi ENABLE ROW LEVEL SECURITY;  -- politika yok: yalnızca fonksiyonlarla

CREATE FUNCTION hukuk.takvim_baglantisi_olustur(p_ozet char(64)) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
BEGIN
  IF hukuk.aktif_kullanici() IS NULL OR hukuk.portal_kisisi(hukuk.aktif_kullanici()) IS NOT NULL THEN
    RAISE EXCEPTION 'Takvim bağlantısı yalnızca büro kullanıcıları içindir.' USING ERRCODE = '42501';
  END IF;
  INSERT INTO hukuk.takvim_aboneligi (kullanici_id, kiraci_id, token_ozeti)
  VALUES (hukuk.aktif_kullanici(), hukuk.aktif_kiraci(), p_ozet)
  ON CONFLICT (kullanici_id) DO UPDATE SET token_ozeti = EXCLUDED.token_ozeti, olusturma = now(), son_okuma = NULL;
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  VALUES (hukuk.aktif_kiraci(), hukuk.aktif_kullanici(), 'paylasim', 'takvim', hukuk.aktif_kullanici()::text,
          'Takvim bağlantısı oluşturuldu (öncekisi geçersiz)', '', '');
END $$;

CREATE FUNCTION hukuk.takvim_baglantisi_kapat() RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
BEGIN
  DELETE FROM hukuk.takvim_aboneligi WHERE kullanici_id = hukuk.aktif_kullanici();
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  VALUES (hukuk.aktif_kiraci(), hukuk.aktif_kullanici(), 'degisiklik', 'takvim', hukuk.aktif_kullanici()::text,
          'Takvim bağlantısı kapatıldı', '', '');
  RETURN true;
END $$;

CREATE FUNCTION hukuk.takvim_baglantisi_var() RETURNS TABLE (olusturma timestamptz, son_okuma timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT olusturma, son_okuma FROM hukuk.takvim_aboneligi WHERE kullanici_id = hukuk.aktif_kullanici()
$$;

-- Oturumsuz akış isteği: bağlantının sahibi (aktif hesap). Okuma zamanı güncellenir.
CREATE FUNCTION hukuk.takvim_sahibi(p_ozet char(64)) RETURNS TABLE (kullanici_id uuid, kiraci_id uuid)
LANGUAGE sql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  UPDATE hukuk.takvim_aboneligi t SET son_okuma = now()
  FROM hukuk.kullanici u
  WHERE t.token_ozeti = p_ozet AND u.id = t.kullanici_id AND u.aktif
  RETURNING t.kullanici_id, t.kiraci_id
$$;

-- Şifre değiştirme müvekkil portalı oturumunda da çalışsın: portal oturumunda kiracı bağlamı yoktur, denetim kaydının
-- kurumu kullanıcının kendi kaydından alınır.
CREATE OR REPLACE FUNCTION hukuk.sifre_degistir(p_yeni_ozet text, p_mevcut_oturum char(64)) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  v_kiraci uuid;
BEGIN
  UPDATE hukuk.kullanici SET sifre_ozeti = p_yeni_ozet WHERE id = hukuk.aktif_kullanici() AND aktif
  RETURNING kiraci_id INTO v_kiraci;
  IF v_kiraci IS NULL THEN
    RAISE EXCEPTION 'Oturum geçersiz.' USING ERRCODE = '42501';
  END IF;
  UPDATE hukuk.oturum SET iptal = now()
  WHERE kullanici_id = hukuk.aktif_kullanici() AND iptal IS NULL AND token_ozeti <> p_mevcut_oturum;
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  VALUES (v_kiraci, hukuk.aktif_kullanici(), 'degisiklik', 'kullanici', hukuk.aktif_kullanici()::text,
          'Şifre değiştirildi; diğer oturumlar kapatıldı', '', '');
END $$;

REVOKE ALL ON FUNCTION hukuk.takvim_baglantisi_olustur(char), hukuk.takvim_baglantisi_kapat(), hukuk.takvim_baglantisi_var(),
  hukuk.takvim_sahibi(char) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hukuk.takvim_baglantisi_olustur(char), hukuk.takvim_baglantisi_kapat(), hukuk.takvim_baglantisi_var(),
  hukuk.takvim_sahibi(char) TO hukuk_uygulama;

COMMIT;
