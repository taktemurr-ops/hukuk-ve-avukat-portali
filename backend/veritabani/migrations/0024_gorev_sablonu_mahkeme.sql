-- Dosyanın mahkeme ve esas numarası (UYAP aktarımında mükerrer kontrolü için tekil) ve büroya özel görev
-- şablonları. Şablonu herkes kullanır, yalnızca yöneticiler ekler/değiştirir; silinmez, pasifleşir.
BEGIN;

ALTER TABLE hukuk.dosya
  ADD COLUMN mahkeme text CHECK (length(mahkeme) <= 200),
  ADD COLUMN esas_no text CHECK (esas_no ~ '^[0-9]{4}/[0-9]{1,7}( (E|D|Talimat|Tal)\.?)?$');
CREATE UNIQUE INDEX dosya_mahkeme_esas_tekil ON hukuk.dosya (kiraci_id, lower(mahkeme), esas_no)
  WHERE mahkeme IS NOT NULL AND esas_no IS NOT NULL;
GRANT UPDATE (mahkeme, esas_no) ON hukuk.dosya TO hukuk_uygulama;

-- Aktarımda mükerrer kontrolü: gizli (görünmeyen) dosyalar dahil; dosyanın kendisi açığa çıkmaz, yalnızca var/yok.
CREATE FUNCTION hukuk.dosya_esas_var(p_kiraci uuid, p_mahkeme text, p_esas text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT p_kiraci = hukuk.aktif_kiraci() AND EXISTS (
    SELECT 1 FROM hukuk.dosya WHERE kiraci_id = p_kiraci AND lower(mahkeme) = lower(p_mahkeme) AND esas_no = p_esas)
$$;

CREATE TABLE hukuk.gorev_sablonu (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id  uuid NOT NULL REFERENCES hukuk.kiraci(id),
  ad         text NOT NULL CHECK (length(trim(ad)) BETWEEN 3 AND 100),
  -- [{"baslik": "...", "gunSonra": 0, "rol": "sorumlu|yedek|stajyer", "oncelik": "dusuk|normal|yuksek|kritik"}]
  adimlar    jsonb NOT NULL CHECK (jsonb_typeof(adimlar) = 'array' AND jsonb_array_length(adimlar) BETWEEN 1 AND 50),
  aktif      boolean NOT NULL DEFAULT true,
  olusturan  uuid NOT NULL DEFAULT hukuk.aktif_kullanici(),
  guncelleme timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX gorev_sablonu_ad_tekil ON hukuk.gorev_sablonu (kiraci_id, lower(ad)) WHERE aktif;
ALTER TABLE hukuk.gorev_sablonu ENABLE ROW LEVEL SECURITY;
CREATE POLICY gorev_sablonu_okuma ON hukuk.gorev_sablonu FOR SELECT USING (kiraci_id = hukuk.aktif_kiraci());
CREATE POLICY gorev_sablonu_ekleme ON hukuk.gorev_sablonu FOR INSERT
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci() AND hukuk.tum_yetkili());
CREATE POLICY gorev_sablonu_degisiklik ON hukuk.gorev_sablonu FOR UPDATE
  USING (kiraci_id = hukuk.aktif_kiraci() AND hukuk.tum_yetkili())
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci() AND hukuk.tum_yetkili());
GRANT SELECT, INSERT ON hukuk.gorev_sablonu TO hukuk_uygulama;
GRANT UPDATE (ad, adimlar, aktif, guncelleme) ON hukuk.gorev_sablonu TO hukuk_uygulama;

COMMIT;
