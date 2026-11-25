-- Kişi kartının kalan alanları, unvan geçmişi ve kişiler arası ilişkiler (çıkar çatışması taraması dolaylı
-- eşleşmeleri ve eski unvanları da bulsun diye). Unvan geçmişi yalnızca veritabanında büyür: ad değişince eski ad
-- otomatik eklenir, istemci geçmişi silemez ya da değiştiremez.
BEGIN;

ALTER TABLE hukuk.kisi
  ADD COLUMN mersis_no        text CHECK (mersis_no ~ '^[0-9]{16}$'),
  ADD COLUMN telefon          text CHECK (length(telefon) <= 30),
  ADD COLUMN adres            text CHECK (length(adres) <= 500),
  ADD COLUMN iletisim_tercihi text NOT NULL DEFAULT 'eposta' CHECK (iletisim_tercihi IN ('eposta', 'telefon', 'sms', 'portal')),
  ADD COLUMN notlar           text CHECK (length(notlar) <= 2000),
  ADD COLUMN unvan_gecmisi    jsonb NOT NULL DEFAULT '[]',
  ADD CONSTRAINT kisi_ad_bos_degil CHECK (length(trim(ad)) > 0);

CREATE FUNCTION hukuk.kisi_unvan_gecmisi() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.unvan_gecmisi := OLD.unvan_gecmisi;  -- istemciden gelen geçmiş yok sayılır
  NEW.tur := OLD.tur;                       -- gerçek/tüzel kişi sonradan değişmez
  IF trim(NEW.ad) <> OLD.ad THEN
    NEW.ad := trim(NEW.ad);
    NEW.unvan_gecmisi := OLD.unvan_gecmisi
      || jsonb_build_array(jsonb_build_object('unvan', OLD.ad, 'bitis', to_char(current_date, 'YYYY-MM-DD')));
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER kisi_unvan_gecmisi BEFORE UPDATE ON hukuk.kisi FOR EACH ROW EXECUTE FUNCTION hukuk.kisi_unvan_gecmisi();

CREATE TABLE hukuk.kisi_iliski (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id uuid NOT NULL REFERENCES hukuk.kiraci(id),
  kisi_a    uuid NOT NULL REFERENCES hukuk.kisi(id),
  kisi_b    uuid NOT NULL REFERENCES hukuk.kisi(id),
  tur       text NOT NULL CHECK (tur IN ('ortak', 'istirak', 'yetkili', 'calisan', 'akraba', 'vekil', 'grupSirketi')),
  olusturan uuid NOT NULL DEFAULT hukuk.aktif_kullanici(),
  olusturma timestamptz NOT NULL DEFAULT now(),
  CHECK (kisi_a <> kisi_b)
);
CREATE UNIQUE INDEX kisi_iliski_tekil ON hukuk.kisi_iliski (kiraci_id, least(kisi_a, kisi_b), greatest(kisi_a, kisi_b), tur);
ALTER TABLE hukuk.kisi_iliski ENABLE ROW LEVEL SECURITY;
CREATE POLICY kiraci_ayrimi ON hukuk.kisi_iliski USING (kiraci_id = hukuk.aktif_kiraci())
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci());
GRANT SELECT, INSERT, DELETE ON hukuk.kisi_iliski TO hukuk_uygulama;

-- İlişkideki iki kişi de bu kiracıya ait olmalı (başka büronun kişisine bağlanamaz).
CREATE FUNCTION hukuk.kisi_iliski_kontrol() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
BEGIN
  IF (SELECT count(*) FROM hukuk.kisi WHERE id IN (NEW.kisi_a, NEW.kisi_b) AND kiraci_id = NEW.kiraci_id) <> 2 THEN
    RAISE EXCEPTION 'İlişkideki kişiler bu kuruma ait değil.' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER kisi_iliski_kontrol BEFORE INSERT ON hukuk.kisi_iliski FOR EACH ROW EXECUTE FUNCTION hukuk.kisi_iliski_kontrol();

COMMIT;
