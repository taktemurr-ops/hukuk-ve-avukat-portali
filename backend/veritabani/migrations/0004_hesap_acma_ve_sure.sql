-- Kendi kendine hesap açma ve süre hesabının gerekçesinin saklanması.
BEGIN;

-- Süre hesabının girdisi ve adım adım gerekçesi (denetim ve itiraz için).
ALTER TABLE hukuk.sure_kaydi
  ADD COLUMN baslangic date,
  ADD COLUMN hesap_adimlari jsonb NOT NULL DEFAULT '[]',
  ADD COLUMN kesin boolean NOT NULL DEFAULT true,
  ADD CONSTRAINT sure_baslangic_once CHECK (baslangic IS NULL OR baslangic <= son_gun);

-- Yeni müşteri: kiracı, ilk kullanıcı (kurucu rolüyle) ve 14 günlük deneme aboneliği tek işlemde açılır.
-- Kiracı bağlamı henüz olmadığından SECURITY DEFINER'dır; e-posta bu müşteri içinde benzersizdir.
CREATE FUNCTION hukuk.hesap_ac(p_kurum text, p_hesap_turu text, p_eposta text, p_ad_soyad text, p_sifre_ozeti text)
RETURNS TABLE (kiraci_id uuid, kullanici_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  k uuid := gen_random_uuid();
  u uuid := gen_random_uuid();
  rol text := CASE p_hesap_turu
                WHEN 'avukatlikBurosu' THEN 'buroSahibi'
                WHEN 'hukukBurosu' THEN 'yoneticiOrtak'
                WHEN 'kurumsal' THEN 'hukukDirektoru'
              END;
BEGIN
  IF rol IS NULL THEN
    RAISE EXCEPTION 'Geçersiz hesap türü' USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO hukuk.kiraci (id, ad, hesap_turu) VALUES (k, trim(p_kurum), p_hesap_turu);
  INSERT INTO hukuk.kullanici (id, kiraci_id, eposta, ad_soyad, sifre_ozeti) VALUES (u, k, lower(trim(p_eposta)), trim(p_ad_soyad), p_sifre_ozeti);
  INSERT INTO hukuk.kullanici_rol (kiraci_id, kullanici_id, rol) VALUES (k, u, rol);
  INSERT INTO hukuk.abonelik (kiraci_id, durum, donem, donem_basi, donem_sonu)
    VALUES (k, 'deneme', 'aylik', current_date, current_date + 14);
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
    VALUES (k, u, 'olusturma', 'kiraci', k::text, 'Hesap açıldı: ' || p_hesap_turu, '', '');
  RETURN QUERY SELECT k, u;
END $$;

GRANT EXECUTE ON FUNCTION hukuk.hesap_ac(text, text, text, text, text) TO hukuk_uygulama;

COMMIT;
