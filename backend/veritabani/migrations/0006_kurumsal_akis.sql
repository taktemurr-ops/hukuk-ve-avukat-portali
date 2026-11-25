-- Kurumsal akışlar için sunucu tarafı ek alanlar: sözleşme onay turu, talep beklemesi ve talep geçmişi.

ALTER TABLE hukuk.sozlesme
  ADD COLUMN birim text NOT NULL DEFAULT '',
  ADD COLUMN yenileme_suresi_ay integer NOT NULL DEFAULT 12 CHECK (yenileme_suresi_ay BETWEEN 1 AND 120),
  -- Sözleşme her "onayda" durumuna geçtiğinde yeni bir onay turu başlar; kararlar tur numarasıyla saklanır.
  ADD COLUMN onay_turu integer NOT NULL DEFAULT 0 CHECK (onay_turu >= 0);

-- Onay kararı yalnızca sözleşmenin güncel turuna ve sözleşme "onayda" iken yazılabilir.
CREATE FUNCTION hukuk.sozlesme_onay_kontrol() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  s record;
BEGIN
  SELECT durum, onay_turu INTO s FROM hukuk.sozlesme WHERE id = NEW.sozlesme_id FOR UPDATE;
  IF s.durum IS DISTINCT FROM 'onayda' OR s.onay_turu <> NEW.tur_no THEN
    RAISE EXCEPTION 'Sözleşme onay aşamasında değil veya onay turu güncel değil' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.kullanici_id <> hukuk.aktif_kullanici() THEN
    RAISE EXCEPTION 'Onay kararı yalnızca oturumdaki kullanıcı adına yazılabilir' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM hukuk.sozlesme_onay WHERE sozlesme_id = NEW.sozlesme_id AND tur_no = NEW.tur_no
             AND karar <> 'onay') THEN
    RAISE EXCEPTION 'Bu onay turu sonuçlanmış (ret veya revizyon)' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER sozlesme_onay_kontrol BEFORE INSERT ON hukuk.sozlesme_onay
FOR EACH ROW EXECUTE FUNCTION hukuk.sozlesme_onay_kontrol();

ALTER TABLE hukuk.hukuk_talebi
  ADD COLUMN bekleme_baslangici date,
  ADD COLUMN talep_eden_kullanici uuid,
  ADD CONSTRAINT talep_bekleme_tutarli CHECK ((durum = 'bilgiBekleniyor') = (bekleme_baslangici IS NOT NULL));

-- Talep geçmişi: yalnızca eklenir.
CREATE TABLE hukuk.talep_olayi (
  id        bigserial PRIMARY KEY,
  kiraci_id uuid NOT NULL REFERENCES hukuk.kiraci(id),
  talep_id  uuid NOT NULL REFERENCES hukuk.hukuk_talebi(id),
  tarih     date NOT NULL DEFAULT current_date,
  kullanici text NOT NULL,
  aciklama  text NOT NULL,
  zaman     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX talep_olayi_talep ON hukuk.talep_olayi (talep_id, id);
ALTER TABLE hukuk.talep_olayi ENABLE ROW LEVEL SECURITY;
CREATE POLICY kiraci_ayrimi ON hukuk.talep_olayi
  USING (kiraci_id = hukuk.aktif_kiraci()) WITH CHECK (kiraci_id = hukuk.aktif_kiraci());
GRANT SELECT, INSERT ON hukuk.talep_olayi TO hukuk_uygulama;
GRANT USAGE ON SEQUENCE hukuk.talep_olayi_id_seq TO hukuk_uygulama;
GRANT EXECUTE ON FUNCTION hukuk.sozlesme_onay_kontrol() TO hukuk_uygulama;
