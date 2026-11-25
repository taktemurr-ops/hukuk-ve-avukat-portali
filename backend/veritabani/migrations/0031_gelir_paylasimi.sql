-- Büro ayarı: tahsil edilen vekâlet ücretinin paylaşım oranları (getiren / çalışanlar / büro). Toplam %100.
BEGIN;

ALTER TABLE hukuk.kiraci
  ADD COLUMN paylasim_getiren int NOT NULL DEFAULT 20,
  ADD COLUMN paylasim_calisan int NOT NULL DEFAULT 50,
  ADD COLUMN paylasim_buro    int NOT NULL DEFAULT 30,
  ADD CONSTRAINT paylasim_orani CHECK (
    paylasim_getiren BETWEEN 0 AND 100 AND paylasim_calisan BETWEEN 0 AND 100 AND paylasim_buro BETWEEN 0 AND 100
    AND paylasim_getiren + paylasim_calisan + paylasim_buro = 100);

CREATE FUNCTION hukuk.gelir_paylasim_kurali(OUT getiren int, OUT calisan int, OUT buro int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT paylasim_getiren, paylasim_calisan, paylasim_buro FROM hukuk.kiraci WHERE id = hukuk.aktif_kiraci()
$$;

CREATE FUNCTION hukuk.gelir_paylasim_ayarla(p_getiren int, p_calisan int, p_buro int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  v_once text;
BEGIN
  IF NOT hukuk.tum_yetkili() THEN
    RAISE EXCEPTION 'Paylaşım oranlarını yalnızca yöneticiler değiştirebilir.' USING ERRCODE = '42501';
  END IF;
  SELECT paylasim_getiren || '/' || paylasim_calisan || '/' || paylasim_buro INTO v_once
    FROM hukuk.kiraci WHERE id = hukuk.aktif_kiraci();
  UPDATE hukuk.kiraci SET paylasim_getiren = p_getiren, paylasim_calisan = p_calisan, paylasim_buro = p_buro
   WHERE id = hukuk.aktif_kiraci();
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  VALUES (hukuk.aktif_kiraci(), hukuk.aktif_kullanici(), 'degisiklik', 'kiraci', hukuk.aktif_kiraci()::text,
          'Gelir paylaşım oranları (getiren/çalışan/büro): ' || v_once || ' -> '
          || p_getiren || '/' || p_calisan || '/' || p_buro, '', '');
END $$;

REVOKE ALL ON FUNCTION hukuk.gelir_paylasim_ayarla(int, int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hukuk.gelir_paylasim_kurali(), hukuk.gelir_paylasim_ayarla(int, int, int) TO hukuk_uygulama;

COMMIT;
