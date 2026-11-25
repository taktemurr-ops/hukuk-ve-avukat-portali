-- Dış avukat portalı: anlaşmalı büronun kullanıcısı (rolü disAvukat, dis_avukat kaydına bağlı) yalnızca kendi
-- bürosuna açılmış işleri görür ve bunlara fatura yükler. Portal oturumunda app.kiraci_id boştur; kurum tabloları
-- hiçbir satır döndürmez, erişim yalnızca aşağıdaki SECURITY DEFINER fonksiyonlarıyladır. Dosya ve talep
-- başlıkları gösterilmez; yalnızca işin konusu.
BEGIN;

ALTER TABLE hukuk.dis_avukat ADD COLUMN kullanici_id uuid UNIQUE REFERENCES hukuk.kullanici(id);
GRANT UPDATE (kullanici_id) ON hukuk.dis_avukat TO hukuk_uygulama;

-- Yalnızca disAvukat rolündeki kullanıcı kurum verisine hiç erişemez (sunucu oturumunu portal uçlarıyla sınırlar);
-- bu yüzden lisans koltuğu tüketmez. Başka bir rol de taşıyorsa koltuk tüketir.
CREATE FUNCTION hukuk.yalniz_dis_avukat(p_kullanici uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT EXISTS (SELECT 1 FROM hukuk.kullanici_rol WHERE kullanici_id = p_kullanici AND rol = 'disAvukat')
     AND NOT EXISTS (SELECT 1 FROM hukuk.kullanici_rol WHERE kullanici_id = p_kullanici AND rol <> 'disAvukat')
$$;

CREATE OR REPLACE FUNCTION hukuk.koltuk_durumu(OUT lisans integer, OUT dolu integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT
    CASE WHEN k.hesap_turu = 'avukatlikBurosu' THEN 3 ELSE coalesce(a.ucretli_koltuk, 1) END,
    (SELECT count(DISTINCT u.id) FROM hukuk.kullanici u JOIN hukuk.kullanici_rol r ON r.kullanici_id = u.id
      WHERE u.kiraci_id = k.id AND u.aktif AND r.rol NOT IN ('talepEden', 'onayci', 'muvekkil', 'denetci', 'disAvukat'))::integer
    + (SELECT count(*) FROM hukuk.davet d WHERE d.kiraci_id = k.id AND d.kullanildi IS NULL AND d.iptal IS NULL
         AND d.son_gecerlilik > now()
         AND EXISTS (SELECT 1 FROM unnest(d.roller) r WHERE r NOT IN ('talepEden', 'onayci', 'muvekkil', 'denetci', 'disAvukat')))::integer
  FROM hukuk.kiraci k LEFT JOIN hukuk.abonelik a ON a.kiraci_id = k.id
  WHERE k.id = hukuk.aktif_kiraci()
$$;

CREATE OR REPLACE FUNCTION hukuk.kullanici_rolleri_degistir(p_kullanici uuid, p_roller text[]) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  u hukuk.kullanici;
  tur text;
  ucretsiz text[] := ARRAY['talepEden', 'onayci', 'muvekkil', 'denetci', 'disAvukat'];
  eski text[];
  k record;
BEGIN
  u := hukuk._yonetim_kontrol(p_kullanici);
  SELECT hesap_turu INTO tur FROM hukuk.kiraci WHERE id = u.kiraci_id;
  IF p_roller IS NULL OR cardinality(p_roller) = 0 THEN
    RAISE EXCEPTION 'En az bir rol seçilmelidir.' USING ERRCODE = '23514';
  END IF;
  IF 'muvekkil' = ANY(p_roller) OR NOT p_roller <@ hukuk.hesap_rolleri(tur) THEN
    RAISE EXCEPTION 'Seçilen rol bu hesap türünde kullanılamaz.' USING ERRCODE = '23514';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('koltuk' || u.kiraci_id::text, 0));
  SELECT coalesce(array_agg(rol), '{}') INTO eski FROM hukuk.kullanici_rol WHERE kullanici_id = u.id;
  IF u.aktif AND NOT (p_roller <@ ucretsiz) AND (eski <@ ucretsiz) THEN
    SELECT * INTO k FROM hukuk.koltuk_durumu();
    IF k.dolu >= k.lisans THEN
      RAISE EXCEPTION 'Lisans koltuğu dolu (% / %). Önce koltuk ekleyin.', k.dolu, k.lisans USING ERRCODE = '23514';
    END IF;
  END IF;
  DELETE FROM hukuk.kullanici_rol WHERE kullanici_id = u.id;
  INSERT INTO hukuk.kullanici_rol (kiraci_id, kullanici_id, rol) SELECT u.kiraci_id, u.id, unnest(p_roller);
  PERFORM hukuk._yonetici_kalmali(u.kiraci_id);
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  VALUES (u.kiraci_id, hukuk.aktif_kullanici(), 'rolVerme', 'kullanici', u.id::text,
          array_to_string(eski, ', ') || ' → ' || array_to_string(p_roller, ', '), '', '');
END $$;

CREATE OR REPLACE FUNCTION hukuk.kullanici_aktiflestir(p_kullanici uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  u hukuk.kullanici;
  k record;
BEGIN
  u := hukuk._yonetim_kontrol(p_kullanici);
  IF u.aktif THEN
    RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('koltuk' || u.kiraci_id::text, 0));
  IF EXISTS (SELECT 1 FROM hukuk.kullanici_rol WHERE kullanici_id = u.id
             AND rol NOT IN ('talepEden', 'onayci', 'muvekkil', 'denetci', 'disAvukat')) THEN
    SELECT * INTO k FROM hukuk.koltuk_durumu();
    IF k.dolu >= k.lisans THEN
      RAISE EXCEPTION 'Lisans koltuğu dolu (% / %). Önce koltuk ekleyin.', k.dolu, k.lisans USING ERRCODE = '23514';
    END IF;
  END IF;
  UPDATE hukuk.kullanici SET aktif = true WHERE id = u.id;
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  VALUES (u.kiraci_id, hukuk.aktif_kullanici(), 'degisiklik', 'kullanici', u.id::text, 'Yeniden etkinleştirildi', '', '');
END $$;

-- Oturum doğrulamasında: kullanıcı aktif, disAvukat rolünde ve aktif bir dış avukat kaydına bağlıysa o kaydın kimliği.
CREATE FUNCTION hukuk.dis_avukat_kimligi(p_kullanici uuid) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT d.id FROM hukuk.dis_avukat d
  JOIN hukuk.kullanici u ON u.id = d.kullanici_id AND u.kiraci_id = d.kiraci_id AND u.aktif
  WHERE d.kullanici_id = p_kullanici AND d.aktif
    AND EXISTS (SELECT 1 FROM hukuk.kullanici_rol r WHERE r.kullanici_id = u.id AND r.rol = 'disAvukat')
$$;

CREATE FUNCTION hukuk.dis_portal_isleri()
RETURNS TABLE (id uuid, konu text, baslangic date, kapali boolean, butce_kurus bigint, onaylanan_kurus bigint,
               bekleyen_kurus bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT i.id, i.konu, i.baslangic, i.kapali,
         i.ilk_butce_kurus + coalesce((SELECT sum(b.tutar_kurus) FROM hukuk.dis_avukat_butce_artisi b WHERE b.isi_id = i.id), 0),
         coalesce((SELECT sum(f.tutar_kurus) FROM hukuk.dis_avukat_faturasi f
                   WHERE f.isi_id = i.id AND f.durum IN ('onaylandi', 'finansaGonderildi')), 0),
         coalesce((SELECT sum(f.tutar_kurus) FROM hukuk.dis_avukat_faturasi f WHERE f.isi_id = i.id AND f.durum = 'bekliyor'), 0)
  FROM hukuk.dis_avukat_isi i
  WHERE i.dis_avukat_id = hukuk.dis_avukat_kimligi(hukuk.aktif_kullanici())
  ORDER BY i.kapali, i.baslangic DESC
$$;

CREATE FUNCTION hukuk.dis_portal_faturalari(p_is uuid)
RETURNS TABLE (id uuid, no text, tarih date, tutar_kurus bigint, aciklama text, durum text, ret_gerekcesi text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT f.id, f.no, f.tarih, f.tutar_kurus, f.aciklama, f.durum, f.ret_gerekcesi
  FROM hukuk.dis_avukat_faturasi f
  JOIN hukuk.dis_avukat_isi i ON i.id = f.isi_id
  WHERE f.isi_id = p_is AND i.dis_avukat_id = hukuk.dis_avukat_kimligi(hukuk.aktif_kullanici())
  ORDER BY f.tarih DESC, f.no
$$;

CREATE FUNCTION hukuk.dis_portal_fatura_ekle(p_is uuid, p_no text, p_tarih date, p_tutar bigint, p_aciklama text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  v_kiraci uuid;
  v_id uuid;
BEGIN
  SELECT i.kiraci_id INTO v_kiraci FROM hukuk.dis_avukat_isi i
   WHERE i.id = p_is AND i.dis_avukat_id = hukuk.dis_avukat_kimligi(hukuk.aktif_kullanici());
  IF v_kiraci IS NULL THEN
    RAISE EXCEPTION 'İş bulunamadı.' USING ERRCODE = 'P0002';
  END IF;
  IF p_tarih > current_date THEN
    RAISE EXCEPTION 'Fatura tarihi ileri bir tarih olamaz.' USING ERRCODE = '23514';
  END IF;
  INSERT INTO hukuk.dis_avukat_faturasi (kiraci_id, isi_id, no, tarih, tutar_kurus, aciklama, ekleyen)
  VALUES (v_kiraci, p_is, p_no, p_tarih, p_tutar, coalesce(p_aciklama, ''), hukuk.aktif_kullanici())
  RETURNING id INTO v_id;
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  VALUES (v_kiraci, hukuk.aktif_kullanici(), 'olusturma', 'dis_avukat_faturasi', v_id::text,
          'Dış avukat portalından fatura', '', '');
  RETURN v_id;
END $$;

-- Kurum tarafı: hukuk ekibi bir dış avukat kaydını, disAvukat rolündeki bir kullanıcıya bağlar (null: bağı kaldırır).
CREATE FUNCTION hukuk.dis_avukat_hesabi_bagla(p_dis_avukat uuid, p_kullanici uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  v_kiraci uuid := hukuk.aktif_kiraci();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hukuk.kullanici_rol r WHERE r.kullanici_id = hukuk.aktif_kullanici()
                 AND r.rol IN ('hukukDirektoru', 'sirketAvukati')) THEN
    RAISE EXCEPTION 'Dış avukat hesabını yalnızca hukuk direktörü veya şirket avukatı bağlayabilir.' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hukuk.dis_avukat WHERE id = p_dis_avukat AND kiraci_id = v_kiraci) THEN
    RAISE EXCEPTION 'Dış avukat bulunamadı.' USING ERRCODE = 'P0002';
  END IF;
  IF p_kullanici IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM hukuk.kullanici u JOIN hukuk.kullanici_rol r ON r.kullanici_id = u.id AND r.rol = 'disAvukat'
      WHERE u.id = p_kullanici AND u.kiraci_id = v_kiraci) THEN
    RAISE EXCEPTION 'Kullanıcı bu kurumda dış avukat rolünde değil.' USING ERRCODE = '23514';
  END IF;
  UPDATE hukuk.dis_avukat SET kullanici_id = p_kullanici WHERE id = p_dis_avukat;
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  VALUES (v_kiraci, hukuk.aktif_kullanici(), 'rolVerme', 'dis_avukat', p_dis_avukat::text,
          CASE WHEN p_kullanici IS NULL THEN 'Portal hesabı kaldırıldı' ELSE 'Portal hesabı bağlandı' END, '', '');
END $$;

REVOKE ALL ON FUNCTION hukuk.dis_portal_fatura_ekle(uuid, text, date, bigint, text),
                       hukuk.dis_avukat_hesabi_bagla(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hukuk.yalniz_dis_avukat(uuid), hukuk.dis_avukat_kimligi(uuid), hukuk.dis_portal_isleri(), hukuk.dis_portal_faturalari(uuid),
  hukuk.dis_portal_fatura_ekle(uuid, text, date, bigint, text), hukuk.dis_avukat_hesabi_bagla(uuid, uuid) TO hukuk_uygulama;

COMMIT;
