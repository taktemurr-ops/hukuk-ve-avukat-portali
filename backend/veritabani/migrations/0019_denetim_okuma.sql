-- Denetim kaydı kimin neye baktığını da içerir (kişisel veri): yalnızca kiracının yöneticileri okuyabilir.
-- Yazma tüm kullanıcılar için açık kalır (her işlem kendi kaydını düşer); güncelleme ve silme zaten yok.
BEGIN;

DROP POLICY kiraci_ayrimi ON hukuk.denetim_kaydi;

CREATE POLICY denetim_okuma ON hukuk.denetim_kaydi FOR SELECT
  USING (kiraci_id = hukuk.aktif_kiraci() AND hukuk.tum_yetkili());

CREATE POLICY denetim_yazma ON hukuk.denetim_kaydi FOR INSERT
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci());

-- Doğrulama tüm zinciri görmeli (RLS ile eksik satır görse "sağlam" derdi); yalnızca kendi kiracısı ve yöneticiler.
CREATE OR REPLACE FUNCTION hukuk.denetim_dogrula(p_kiraci uuid) RETURNS bigint
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  d hukuk.denetim_kaydi;
  beklenen char(64) := repeat('0', 64);
  sayac bigint := 0;
BEGIN
  IF hukuk.aktif_kiraci() IS DISTINCT FROM p_kiraci OR NOT hukuk.tum_yetkili() THEN
    RAISE EXCEPTION 'Denetim kaydını yalnızca yöneticiler doğrulayabilir.' USING ERRCODE = '42501';
  END IF;
  FOR d IN SELECT * FROM hukuk.denetim_kaydi WHERE kiraci_id = p_kiraci ORDER BY sira LOOP
    sayac := sayac + 1;
    IF d.sira <> sayac OR d.onceki_ozet <> beklenen OR d.ozet <> hukuk.denetim_ozeti(d) THEN
      RETURN d.sira;
    END IF;
    beklenen := d.ozet;
  END LOOP;
  RETURN NULL;
END $$;

COMMIT;
