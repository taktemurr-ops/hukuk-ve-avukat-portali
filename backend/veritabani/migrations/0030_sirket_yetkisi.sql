-- Kurumsal hesapta kullanıcı bazlı şirket yetkisi: kullanıcıya şirket atanmışsa sözleşme ve hukuk taleplerini yalnızca
-- o şirketlerde ve alt şirketlerinde görür/değiştirir. Atama yoksa (varsayılan) ve yöneticilerde kısıt yoktur.
-- Şirketi boş kayıtlar kısıtlı kullanıcıya görünmez.
BEGIN;

CREATE TABLE hukuk.kullanici_sirket (
  kiraci_id    uuid NOT NULL REFERENCES hukuk.kiraci(id),
  kullanici_id uuid NOT NULL REFERENCES hukuk.kullanici(id),
  sirket_id    uuid NOT NULL REFERENCES hukuk.sirket(id),
  PRIMARY KEY (kullanici_id, sirket_id)
);
ALTER TABLE hukuk.kullanici_sirket ENABLE ROW LEVEL SECURITY;
CREATE POLICY kullanici_sirket_okuma ON hukuk.kullanici_sirket FOR SELECT USING (kiraci_id = hukuk.aktif_kiraci());
GRANT SELECT ON hukuk.kullanici_sirket TO hukuk_uygulama;

CREATE FUNCTION hukuk.sirket_erisimi(p_sirket uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT hukuk.tum_yetkili()
      OR NOT EXISTS (SELECT 1 FROM hukuk.kullanici_sirket WHERE kullanici_id = hukuk.aktif_kullanici())
      OR (p_sirket IS NOT NULL AND EXISTS (
            WITH RECURSIVE ustler(id, ana, derinlik) AS (
              SELECT s.id, s.ana_sirket_id, 0 FROM hukuk.sirket s WHERE s.id = p_sirket
              UNION ALL
              SELECT s.id, s.ana_sirket_id, u.derinlik + 1 FROM hukuk.sirket s JOIN ustler u ON s.id = u.ana
              WHERE u.derinlik < 20)
            SELECT 1 FROM ustler u JOIN hukuk.kullanici_sirket ks
              ON ks.sirket_id = u.id AND ks.kullanici_id = hukuk.aktif_kullanici()))
$$;

DROP POLICY kiraci_ayrimi ON hukuk.sozlesme;
CREATE POLICY sirket_yetkisi ON hukuk.sozlesme
  USING (kiraci_id = hukuk.aktif_kiraci() AND hukuk.sirket_erisimi(sirket_id))
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci() AND hukuk.sirket_erisimi(sirket_id));

DROP POLICY kiraci_ayrimi ON hukuk.hukuk_talebi;
CREATE POLICY sirket_yetkisi ON hukuk.hukuk_talebi
  USING (kiraci_id = hukuk.aktif_kiraci() AND hukuk.sirket_erisimi(sirket_id))
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci() AND hukuk.sirket_erisimi(sirket_id));

-- Yönetici atar; boş liste kısıtı kaldırır.
CREATE FUNCTION hukuk.kullanici_sirketleri_ayarla(p_kullanici uuid, p_sirketler uuid[]) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  v_kiraci uuid := hukuk.aktif_kiraci();
BEGIN
  IF NOT hukuk.tum_yetkili() THEN
    RAISE EXCEPTION 'Şirket yetkisini yalnızca yöneticiler değiştirebilir.' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hukuk.kullanici WHERE id = p_kullanici AND kiraci_id = v_kiraci) THEN
    RAISE EXCEPTION 'Kullanıcı bulunamadı.' USING ERRCODE = 'P0002';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(coalesce(p_sirketler, '{}')) x
             WHERE NOT EXISTS (SELECT 1 FROM hukuk.sirket s WHERE s.id = x AND s.kiraci_id = v_kiraci)) THEN
    RAISE EXCEPTION 'Şirket bu kuruma ait değil.' USING ERRCODE = '23514';
  END IF;
  DELETE FROM hukuk.kullanici_sirket WHERE kullanici_id = p_kullanici;
  INSERT INTO hukuk.kullanici_sirket (kiraci_id, kullanici_id, sirket_id)
  SELECT DISTINCT v_kiraci, p_kullanici, x FROM unnest(coalesce(p_sirketler, '{}')) x;
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  VALUES (v_kiraci, hukuk.aktif_kullanici(), 'rolVerme', 'kullanici', p_kullanici::text,
          CASE WHEN cardinality(coalesce(p_sirketler, '{}')) = 0 THEN 'Şirket kısıtı kaldırıldı'
               ELSE 'Şirket yetkisi: ' || cardinality(p_sirketler) || ' şirket' END, '', '');
END $$;

REVOKE ALL ON FUNCTION hukuk.kullanici_sirketleri_ayarla(uuid, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hukuk.kullanici_sirketleri_ayarla(uuid, uuid[]), hukuk.sirket_erisimi(uuid) TO hukuk_uygulama;

COMMIT;
