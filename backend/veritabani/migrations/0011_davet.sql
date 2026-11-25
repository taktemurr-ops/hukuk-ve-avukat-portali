-- Ekip ve müvekkil daveti: kod yalnızca bağlantıda; sunucuda özeti. Davet edilen kişi şifresini kendisi belirler.

ALTER TABLE hukuk.kullanici ADD COLUMN kisi_id uuid REFERENCES hukuk.kisi(id);
ALTER TABLE hukuk.davet
  ADD COLUMN kisi_id uuid REFERENCES hukuk.kisi(id),
  ADD COLUMN kullanan uuid,
  -- Müvekkil daveti hangi kişi kartına bağlanacağını bilmelidir; diğer davetler kişiye bağlanmaz.
  ADD CONSTRAINT davet_muvekkil_kisi CHECK (('muvekkil' = ANY (roller)) = (kisi_id IS NOT NULL)),
  ADD CONSTRAINT davet_muvekkil_tek_rol CHECK (NOT ('muvekkil' = ANY (roller)) OR cardinality(roller) = 1);

-- Davet oluşturma ve iptal yalnızca tüm dosyalara yetkili yöneticilere açık.
DROP POLICY kiraci_ayrimi ON hukuk.davet;
CREATE POLICY davet_okuma ON hukuk.davet FOR SELECT USING (kiraci_id = hukuk.aktif_kiraci() AND hukuk.tum_yetkili());
CREATE POLICY davet_yazma ON hukuk.davet FOR INSERT
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci() AND hukuk.tum_yetkili() AND davet_eden = hukuk.aktif_kullanici());
CREATE POLICY davet_iptal ON hukuk.davet FOR UPDATE
  USING (kiraci_id = hukuk.aktif_kiraci() AND hukuk.tum_yetkili()) WITH CHECK (kiraci_id = hukuk.aktif_kiraci());

-- Lisans koltuğu: aktif kullanıcılar + bekleyen davetler (ücretsiz roller hariç). Sabit pakette (bireysel büro) 3.
CREATE FUNCTION hukuk.koltuk_durumu(OUT lisans integer, OUT dolu integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT
    CASE WHEN k.hesap_turu = 'avukatlikBurosu' THEN 3 ELSE coalesce(a.ucretli_koltuk, 1) END,
    (SELECT count(DISTINCT u.id) FROM hukuk.kullanici u JOIN hukuk.kullanici_rol r ON r.kullanici_id = u.id
      WHERE u.kiraci_id = k.id AND u.aktif AND r.rol NOT IN ('talepEden', 'onayci', 'muvekkil', 'denetci'))::integer
    + (SELECT count(*) FROM hukuk.davet d WHERE d.kiraci_id = k.id AND d.kullanildi IS NULL AND d.iptal IS NULL
         AND d.son_gecerlilik > now()
         AND EXISTS (SELECT 1 FROM unnest(d.roller) r WHERE r NOT IN ('talepEden', 'onayci', 'muvekkil', 'denetci')))::integer
  FROM hukuk.kiraci k LEFT JOIN hukuk.abonelik a ON a.kiraci_id = k.id
  WHERE k.id = hukuk.aktif_kiraci()
$$;

-- Davet kabulü (oturumsuz): kod özeti, e-posta eşleşmesi, süre ve tek kullanım kontrol edilir; kullanıcı ve roller açılır.
CREATE FUNCTION hukuk.davet_kabul(p_kod_ozeti text, p_eposta text, p_ad_soyad text, p_sifre_ozeti text)
RETURNS TABLE (kiraci_id uuid, kullanici_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  d hukuk.davet%ROWTYPE;
  u uuid := gen_random_uuid();
  r text;
BEGIN
  SELECT * INTO d FROM hukuk.davet WHERE kod_ozeti = p_kod_ozeti FOR UPDATE;
  IF NOT FOUND OR d.iptal IS NOT NULL OR d.kullanildi IS NOT NULL OR d.son_gecerlilik <= now()
     OR lower(trim(p_eposta)) <> lower(d.eposta) THEN
    -- Hangi koşulun tuttuğu söylenmez (davet kodu tahminine karşı).
    RAISE EXCEPTION 'Davet geçersiz, süresi dolmuş veya bu e-posta için değil' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM hukuk.kullanici x WHERE x.kiraci_id = d.kiraci_id AND lower(x.eposta) = lower(d.eposta)) THEN
    RAISE EXCEPTION 'Bu e-postayla kurumda zaten bir hesap var' USING ERRCODE = 'unique_violation';
  END IF;
  INSERT INTO hukuk.kullanici (id, kiraci_id, eposta, ad_soyad, sifre_ozeti, kisi_id)
    VALUES (u, d.kiraci_id, lower(d.eposta), trim(p_ad_soyad), p_sifre_ozeti, d.kisi_id);
  FOREACH r IN ARRAY d.roller LOOP
    INSERT INTO hukuk.kullanici_rol (kiraci_id, kullanici_id, rol) VALUES (d.kiraci_id, u, r);
  END LOOP;
  UPDATE hukuk.davet SET kullanildi = now(), kullanan = u WHERE id = d.id;
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
    VALUES (d.kiraci_id, u, 'olusturma', 'kullanici', u::text, 'Davet kabul edildi: ' || array_to_string(d.roller, ', '), '', '');
  RETURN QUERY SELECT d.kiraci_id, u;
END $$;
GRANT EXECUTE ON FUNCTION hukuk.koltuk_durumu(), hukuk.davet_kabul(text, text, text, text) TO hukuk_uygulama;

-- Oturum çözülürken: kullanıcı müvekkil ise bağlı kişi kartı (portal oturumu). Portal oturumları büro verisine
-- erişen uçları kullanamaz; yalnızca kendi kişisine paylaşılan dosyalara SECURITY DEFINER portal fonksiyonlarıyla erişir.
CREATE FUNCTION hukuk.portal_kisisi(p_kullanici uuid) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT u.kisi_id FROM hukuk.kullanici u
  WHERE u.id = p_kullanici AND EXISTS (SELECT 1 FROM hukuk.kullanici_rol r WHERE r.kullanici_id = u.id AND r.rol = 'muvekkil')
$$;
GRANT EXECUTE ON FUNCTION hukuk.portal_kisisi(uuid) TO hukuk_uygulama;
