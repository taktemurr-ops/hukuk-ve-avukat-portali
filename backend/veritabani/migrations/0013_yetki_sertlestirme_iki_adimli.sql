-- 1) Yetki sertleştirme: kullanıcı, rol ve kurum kayıtları uygulama rolüyle doğrudan değiştirilemez.
--    (Hesap açma, davet kabulü ve oturum işlemleri SECURITY DEFINER fonksiyonlarla yapılır.)
-- 2) İki adımlı doğrulama (TOTP): sır uygulama sunucusunda AES-256-GCM ile şifrelenir; veritabanında yalnızca
--    şifreli hâli durur. Aynı kodun ikinci kez kullanılmasına karşı son kullanılan zaman adımı saklanır.

REVOKE INSERT, UPDATE ON hukuk.kiraci, hukuk.kullanici FROM hukuk_uygulama;
-- Şifre özeti ve TOTP sırları uygulama rolüne hiç görünmez.
REVOKE SELECT ON hukuk.kullanici FROM hukuk_uygulama;
GRANT SELECT (id, kiraci_id, eposta, ad_soyad, aktif, iki_adimli, olusturma, kisi_id) ON hukuk.kullanici TO hukuk_uygulama;

-- Rol verme/alma ve dosya ekibi: yalnızca yöneticiler; kimse kendi rolünü değiştiremez.
DROP POLICY kiraci_ayrimi ON hukuk.kullanici_rol;
CREATE POLICY rol_okuma ON hukuk.kullanici_rol FOR SELECT USING (kiraci_id = hukuk.aktif_kiraci());
CREATE POLICY rol_verme ON hukuk.kullanici_rol FOR INSERT
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci() AND hukuk.tum_yetkili() AND kullanici_id <> hukuk.aktif_kullanici());
CREATE POLICY rol_alma ON hukuk.kullanici_rol FOR DELETE
  USING (kiraci_id = hukuk.aktif_kiraci() AND hukuk.tum_yetkili() AND kullanici_id <> hukuk.aktif_kullanici());

DROP POLICY kiraci_ayrimi ON hukuk.dosya_ekip;
CREATE POLICY ekip_okuma ON hukuk.dosya_ekip FOR SELECT USING (kiraci_id = hukuk.aktif_kiraci());
CREATE POLICY ekip_yazma ON hukuk.dosya_ekip FOR INSERT
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci() AND (hukuk.tum_yetkili() OR EXISTS (
    SELECT 1 FROM hukuk.dosya d WHERE d.id = dosya_id AND hukuk.aktif_kullanici() IN (d.sorumlu, d.yedek_sorumlu))));
CREATE POLICY ekip_cikarma ON hukuk.dosya_ekip FOR DELETE
  USING (kiraci_id = hukuk.aktif_kiraci() AND (hukuk.tum_yetkili() OR EXISTS (
    SELECT 1 FROM hukuk.dosya d WHERE d.id = dosya_id AND hukuk.aktif_kullanici() IN (d.sorumlu, d.yedek_sorumlu))));

ALTER TABLE hukuk.kullanici
  ADD COLUMN totp_sir bytea,
  ADD COLUMN totp_bekleyen bytea,
  ADD COLUMN totp_son_adim bigint NOT NULL DEFAULT 0,
  ADD CONSTRAINT iki_adimli_sir_var CHECK (NOT iki_adimli OR totp_sir IS NOT NULL);

-- Girişte (şifre doğrulandıktan sonra) şifreli sır ve son kullanılan adım.
CREATE FUNCTION hukuk.iki_adimli_sir(p_kullanici uuid, OUT sir bytea, OUT son_adim bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT totp_sir, totp_son_adim FROM hukuk.kullanici WHERE id = p_kullanici AND iki_adimli AND aktif
$$;

-- Kodun zaman adımını işler; aynı veya daha eski adım tekrar kullanılamaz (yeniden oynatma).
CREATE FUNCTION hukuk.iki_adimli_adim_kullan(p_kullanici uuid, p_adim bigint) RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  WITH g AS (UPDATE hukuk.kullanici SET totp_son_adim = p_adim
             WHERE id = p_kullanici AND totp_son_adim < p_adim RETURNING 1)
  SELECT EXISTS (SELECT 1 FROM g)
$$;

-- Oturumdaki kullanıcının kendi kurulumu.
CREATE FUNCTION hukuk.iki_adimli_bekleyen_yaz(p_sifreli bytea) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  UPDATE hukuk.kullanici SET totp_bekleyen = p_sifreli WHERE id = hukuk.aktif_kullanici()
$$;

CREATE FUNCTION hukuk.iki_adimli_bekleyen() RETURNS bytea
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT totp_bekleyen FROM hukuk.kullanici WHERE id = hukuk.aktif_kullanici()
$$;

CREATE FUNCTION hukuk.iki_adimli_etkinlestir(p_adim bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
BEGIN
  UPDATE hukuk.kullanici SET totp_sir = totp_bekleyen, totp_bekleyen = NULL, iki_adimli = true, totp_son_adim = p_adim
  WHERE id = hukuk.aktif_kullanici() AND totp_bekleyen IS NOT NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Önce iki adımlı doğrulama kurulumu başlatılmalı' USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  SELECT u.kiraci_id, u.id, 'degisiklik', 'guvenlik', u.id::text, 'İki adımlı doğrulama açıldı', '', ''
  FROM hukuk.kullanici u WHERE u.id = hukuk.aktif_kullanici();
END $$;

CREATE FUNCTION hukuk.iki_adimli_kapat() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
BEGIN
  UPDATE hukuk.kullanici SET totp_sir = NULL, totp_bekleyen = NULL, iki_adimli = false WHERE id = hukuk.aktif_kullanici();
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  SELECT u.kiraci_id, u.id, 'degisiklik', 'guvenlik', u.id::text, 'İki adımlı doğrulama kapatıldı', '', ''
  FROM hukuk.kullanici u WHERE u.id = hukuk.aktif_kullanici();
END $$;

GRANT EXECUTE ON FUNCTION hukuk.iki_adimli_sir(uuid), hukuk.iki_adimli_adim_kullan(uuid, bigint),
  hukuk.iki_adimli_bekleyen_yaz(bytea), hukuk.iki_adimli_bekleyen(), hukuk.iki_adimli_etkinlestir(bigint),
  hukuk.iki_adimli_kapat() TO hukuk_uygulama;
