-- KVKK saklama ve imha (Yönetmelik m.11: periyodik imha en geç 6 ayda bir). İmha tutanağını tüm dosyalara yetkili
-- bir yönetici hazırlar, başka bir yönetici onaylar (dört göz). Yasal saklama engeli olan dosya imha listesine giremez.
-- Onaylanan tutanaktaki dosyalar "imha edildi" olarak işaretlenir; içerik silme/anonimleştirme yöntemi (kategori
-- bazında) avukat onayıyla ayrıca devreye alınır — bu göç veri silmez.

ALTER TABLE hukuk.dosya
  ADD COLUMN saklama_engeli text,
  ADD COLUMN imha_tarihi date,
  ADD COLUMN imha_tutanagi text,
  ADD CONSTRAINT dosya_imha_kapali CHECK (imha_tarihi IS NULL OR kapanis IS NOT NULL),
  ADD CONSTRAINT dosya_imha_tutanakli CHECK ((imha_tarihi IS NULL) = (imha_tutanagi IS NULL));

CREATE TABLE hukuk.imha_tutanagi (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id   uuid NOT NULL REFERENCES hukuk.kiraci(id),
  no          text NOT NULL,
  tarih       date NOT NULL DEFAULT current_date,
  dosyalar    uuid[] NOT NULL CHECK (cardinality(dosyalar) > 0),
  yontem      text NOT NULL CHECK (yontem IN ('silme', 'yokEtme', 'anonimlestirme')),
  hazirlayan  uuid NOT NULL DEFAULT hukuk.aktif_kullanici(),
  onaylayan   uuid,
  onay_tarihi date,
  UNIQUE (kiraci_id, no),
  CHECK (onaylayan IS NULL OR onaylayan <> hazirlayan),
  CHECK ((onaylayan IS NULL) = (onay_tarihi IS NULL))
);
ALTER TABLE hukuk.imha_tutanagi ENABLE ROW LEVEL SECURITY;
CREATE POLICY imha_okuma ON hukuk.imha_tutanagi FOR SELECT USING (kiraci_id = hukuk.aktif_kiraci() AND hukuk.tum_yetkili());
CREATE POLICY imha_hazirlama ON hukuk.imha_tutanagi FOR INSERT
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci() AND hukuk.tum_yetkili() AND hazirlayan = hukuk.aktif_kullanici()
              AND onaylayan IS NULL);
GRANT SELECT, INSERT ON hukuk.imha_tutanagi TO hukuk_uygulama;
-- Yasal saklama engeli (dava, denetim, resmî talep) yöneticilerce dosyaya işlenir.
GRANT UPDATE (saklama_engeli) ON hukuk.dosya TO hukuk_uygulama;

-- Tutanaktaki dosyalar: aynı kurumda, kapalı, engelsiz ve daha önce imha edilmemiş olmalı.
CREATE FUNCTION hukuk.imha_tutanagi_kontrol() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM unnest(NEW.dosyalar) x(id) LEFT JOIN hukuk.dosya d ON d.id = x.id
             WHERE d.id IS NULL OR d.kiraci_id <> NEW.kiraci_id OR d.kapanis IS NULL
                OR coalesce(length(trim(d.saklama_engeli)), 0) > 0 OR d.imha_tarihi IS NOT NULL) THEN
    RAISE EXCEPTION 'Tutanakta imhaya uygun olmayan dosya var (açık, yasal saklama engelli veya zaten imha edilmiş)'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER imha_tutanagi_kontrol BEFORE INSERT ON hukuk.imha_tutanagi
FOR EACH ROW EXECUTE FUNCTION hukuk.imha_tutanagi_kontrol();

-- Onay (dört göz): onaylayan hazırlayan olamaz; dosyalar o anda da uygun olmalı; dosyalar işaretlenir, denetime yazılır.
CREATE FUNCTION hukuk.imha_tutanagi_onayla(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  t hukuk.imha_tutanagi%ROWTYPE;
BEGIN
  IF NOT hukuk.tum_yetkili() THEN
    RAISE EXCEPTION 'İmha tutanağını yalnızca yöneticiler onaylar' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT * INTO t FROM hukuk.imha_tutanagi WHERE id = p_id AND kiraci_id = hukuk.aktif_kiraci() FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tutanak bulunamadı' USING ERRCODE = 'no_data_found';
  END IF;
  IF t.onaylayan IS NOT NULL THEN
    RAISE EXCEPTION 'Tutanak zaten onaylandı' USING ERRCODE = 'check_violation';
  END IF;
  IF t.hazirlayan = hukuk.aktif_kullanici() THEN
    RAISE EXCEPTION 'Tutanağı hazırlayan onaylayamaz' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM hukuk.dosya d WHERE d.id = ANY (t.dosyalar)
             AND (coalesce(length(trim(d.saklama_engeli)), 0) > 0 OR d.imha_tarihi IS NOT NULL)) THEN
    RAISE EXCEPTION 'Tutanaktaki bir dosyaya sonradan yasal saklama engeli konmuş veya dosya zaten imha edilmiş'
      USING ERRCODE = 'check_violation';
  END IF;
  UPDATE hukuk.imha_tutanagi SET onaylayan = hukuk.aktif_kullanici(), onay_tarihi = current_date WHERE id = p_id;
  UPDATE hukuk.dosya SET imha_tarihi = current_date, imha_tutanagi = t.no WHERE id = ANY (t.dosyalar);
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  VALUES (t.kiraci_id, hukuk.aktif_kullanici(), 'silme', 'imha_tutanagi', t.no,
          cardinality(t.dosyalar) || ' dosya imha edildi olarak işaretlendi (' || t.yontem || ')', '', '');
END $$;

-- Son onaylı tutanak tarihi (periyodik imha takibi).
CREATE FUNCTION hukuk.son_periyodik_imha() RETURNS date
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT max(onay_tarihi) FROM hukuk.imha_tutanagi WHERE kiraci_id = hukuk.aktif_kiraci()
$$;

GRANT EXECUTE ON FUNCTION hukuk.imha_tutanagi_kontrol(), hukuk.imha_tutanagi_onayla(uuid), hukuk.son_periyodik_imha()
  TO hukuk_uygulama;
