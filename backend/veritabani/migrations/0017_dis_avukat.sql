-- Kurumsal: dış avukat (anlaşmalı büro) işleri, bütçe ve fatura onayı. Bütçeyi aşan fatura veritabanında da
-- onaylanamaz; bütçe artışları gerekçeli ve silinmez; fatura durumları yalnızca ileri gider.

CREATE TABLE hukuk.dis_avukat (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id      uuid NOT NULL REFERENCES hukuk.kiraci(id),
  buro           text NOT NULL CHECK (length(trim(buro)) >= 2),
  sorumlu_avukat text NOT NULL,
  eposta         text NOT NULL CHECK (eposta ~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$'),
  uzmanliklar    text[] NOT NULL DEFAULT '{}',
  saatlik_kurus  bigint CHECK (saatlik_kurus >= 0),
  aktif          boolean NOT NULL DEFAULT true
);

CREATE TABLE hukuk.dis_avukat_isi (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id       uuid NOT NULL REFERENCES hukuk.kiraci(id),
  dis_avukat_id   uuid NOT NULL REFERENCES hukuk.dis_avukat(id),
  konu            text NOT NULL CHECK (length(trim(konu)) >= 3),
  ilk_butce_kurus bigint NOT NULL CHECK (ilk_butce_kurus > 0),
  baslangic       date NOT NULL DEFAULT current_date,
  dosya_id        uuid REFERENCES hukuk.dosya(id),
  talep_id        uuid REFERENCES hukuk.hukuk_talebi(id),
  kapali          boolean NOT NULL DEFAULT false
);

CREATE TABLE hukuk.dis_avukat_butce_artisi (
  id         bigserial PRIMARY KEY,
  kiraci_id  uuid NOT NULL REFERENCES hukuk.kiraci(id),
  isi_id     uuid NOT NULL REFERENCES hukuk.dis_avukat_isi(id),
  tutar_kurus bigint NOT NULL CHECK (tutar_kurus > 0),
  gerekce    text NOT NULL CHECK (length(trim(gerekce)) >= 10),
  onaylayan  uuid NOT NULL DEFAULT hukuk.aktif_kullanici(),
  tarih      date NOT NULL DEFAULT current_date
);

CREATE TABLE hukuk.dis_avukat_faturasi (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id     uuid NOT NULL REFERENCES hukuk.kiraci(id),
  isi_id        uuid NOT NULL REFERENCES hukuk.dis_avukat_isi(id),
  no            text NOT NULL CHECK (length(trim(no)) > 0),
  tarih         date NOT NULL,
  tutar_kurus   bigint NOT NULL CHECK (tutar_kurus > 0),
  aciklama      text NOT NULL DEFAULT '',
  durum         text NOT NULL DEFAULT 'bekliyor' CHECK (durum IN ('bekliyor', 'onaylandi', 'finansaGonderildi', 'reddedildi')),
  onaylayan     uuid,
  ret_gerekcesi text,
  ekleyen       uuid NOT NULL DEFAULT hukuk.aktif_kullanici(),
  CHECK (durum <> 'reddedildi' OR coalesce(length(trim(ret_gerekcesi)), 0) >= 5),
  CHECK ((durum = 'bekliyor') = (onaylayan IS NULL))
);
CREATE UNIQUE INDEX dis_avukat_faturasi_no ON hukuk.dis_avukat_faturasi (isi_id, lower(trim(no)));

CREATE FUNCTION hukuk.dis_avukat_fatura_kurallari() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  butce bigint;
  harcanan bigint;
  kapali boolean;
BEGIN
  SELECT i.ilk_butce_kurus + coalesce((SELECT sum(b.tutar_kurus) FROM hukuk.dis_avukat_butce_artisi b WHERE b.isi_id = i.id), 0),
         i.kapali
    INTO butce, kapali
    FROM hukuk.dis_avukat_isi i WHERE i.id = NEW.isi_id FOR UPDATE;
  IF TG_OP = 'INSERT' THEN
    IF kapali THEN
      RAISE EXCEPTION 'Kapalı işe fatura eklenemez' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.durum <> 'bekliyor' THEN
      RAISE EXCEPTION 'Fatura onay bekleyerek eklenir' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  -- Yalnızca ileri geçişler; tutar, numara ve iş değiştirilemez.
  IF NEW.tutar_kurus <> OLD.tutar_kurus OR NEW.no <> OLD.no OR NEW.isi_id <> OLD.isi_id OR NOT (
       (OLD.durum = 'bekliyor' AND NEW.durum IN ('onaylandi', 'reddedildi'))
    OR (OLD.durum = 'onaylandi' AND NEW.durum = 'finansaGonderildi')) THEN
    RAISE EXCEPTION 'Geçersiz fatura değişikliği (% → %)', OLD.durum, NEW.durum USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.durum = 'onaylandi' THEN
    SELECT coalesce(sum(f.tutar_kurus), 0) INTO harcanan FROM hukuk.dis_avukat_faturasi f
      WHERE f.isi_id = NEW.isi_id AND f.durum IN ('onaylandi', 'finansaGonderildi') AND f.id <> NEW.id;
    IF harcanan + NEW.tutar_kurus > butce THEN
      RAISE EXCEPTION 'Onay bütçeyi aşıyor; önce gerekçeli bütçe artışı onaylanmalı' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER dis_avukat_fatura_kurallari BEFORE INSERT OR UPDATE ON hukuk.dis_avukat_faturasi
FOR EACH ROW EXECUTE FUNCTION hukuk.dis_avukat_fatura_kurallari();

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['dis_avukat', 'dis_avukat_isi', 'dis_avukat_butce_artisi', 'dis_avukat_faturasi'] LOOP
    EXECUTE format('ALTER TABLE hukuk.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY kiraci_ayrimi ON hukuk.%I USING (kiraci_id = hukuk.aktif_kiraci()) '
                   'WITH CHECK (kiraci_id = hukuk.aktif_kiraci())', t);
  END LOOP;
END $$;
GRANT SELECT, INSERT, UPDATE ON hukuk.dis_avukat, hukuk.dis_avukat_isi, hukuk.dis_avukat_faturasi TO hukuk_uygulama;
GRANT SELECT, INSERT ON hukuk.dis_avukat_butce_artisi TO hukuk_uygulama;
GRANT USAGE ON SEQUENCE hukuk.dis_avukat_butce_artisi_id_seq TO hukuk_uygulama;
GRANT EXECUTE ON FUNCTION hukuk.dis_avukat_fatura_kurallari() TO hukuk_uygulama;
