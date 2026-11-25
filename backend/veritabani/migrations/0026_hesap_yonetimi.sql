-- Hesap ve ekip yönetimi: rol değiştirme (hesap türüne uygun roller, koltuk sınırı, en az bir yönetici kalır),
-- işten ayrılanın pasifleştirilmesi (açık süreler ve dosyalar önce devredilir), şifre değiştirme ve oturum yönetimi.
BEGIN;

CREATE FUNCTION hukuk.hesap_rolleri(p_tur text) RETURNS text[]
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_tur
    WHEN 'avukatlikBurosu' THEN ARRAY['buroSahibi', 'sekreter', 'stajyer', 'muvekkil']
    WHEN 'hukukBurosu' THEN ARRAY['yoneticiOrtak', 'ortak', 'avukat', 'stajyer', 'sekreter', 'muhasebe', 'muvekkil', 'muhabirAvukat']
    WHEN 'kurumsal' THEN ARRAY['hukukDirektoru', 'sirketAvukati', 'hukukUzmani', 'talepEden', 'onayci', 'finansVeSatinAlma',
                               'disAvukat', 'btYoneticisi', 'denetci', 'uyumSorumlusu']
  END
$$;

CREATE FUNCTION hukuk._yonetici_mi(p_kullanici uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT EXISTS (SELECT 1 FROM hukuk.kullanici_rol r JOIN hukuk.kullanici u ON u.id = r.kullanici_id
                 WHERE r.kullanici_id = p_kullanici AND u.aktif AND r.rol IN ('buroSahibi', 'yoneticiOrtak', 'hukukDirektoru'))
$$;

-- Kiracıda hiç aktif yönetici kalmayacaksa hata.
CREATE FUNCTION hukuk._yonetici_kalmali(p_kiraci uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hukuk.kullanici u WHERE u.kiraci_id = p_kiraci AND hukuk._yonetici_mi(u.id)) THEN
    RAISE EXCEPTION 'Kurumda en az bir aktif yönetici kalmalıdır.' USING ERRCODE = '23514';
  END IF;
END $$;

CREATE FUNCTION hukuk._yonetim_kontrol(p_kullanici uuid) RETURNS hukuk.kullanici
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  u hukuk.kullanici;
BEGIN
  IF NOT hukuk.tum_yetkili() THEN
    RAISE EXCEPTION 'Bu işlemi yalnızca yöneticiler yapabilir.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO u FROM hukuk.kullanici WHERE id = p_kullanici AND kiraci_id = hukuk.aktif_kiraci();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kullanıcı bulunamadı.' USING ERRCODE = 'P0002';
  END IF;
  IF u.id = hukuk.aktif_kullanici() THEN
    RAISE EXCEPTION 'Kendi rolünüzü ya da hesabınızı değiştiremezsiniz; başka bir yönetici yapmalıdır.' USING ERRCODE = '42501';
  END IF;
  IF u.kisi_id IS NOT NULL THEN
    RAISE EXCEPTION 'Müvekkil hesapları portal paylaşımından yönetilir.' USING ERRCODE = '23514';
  END IF;
  RETURN u;
END $$;

-- Rolleri bütünüyle değiştirir. Ücretli role geçişte koltuk sınırı denetlenir (kilit altında).
CREATE FUNCTION hukuk.kullanici_rolleri_degistir(p_kullanici uuid, p_roller text[]) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  u hukuk.kullanici;
  tur text;
  ucretsiz text[] := ARRAY['talepEden', 'onayci', 'muvekkil', 'denetci'];
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

-- İşten ayrılış: açık süreler, görevler ve sorumlu olduğu açık dosyalar devralana geçer; sonra hesap pasifleşir
-- (oturumları anında kapanır). Devralan verilmezse ve devredilecek iş varsa hata (iş sahipsiz kalmaz).
CREATE FUNCTION hukuk.kullanici_pasiflestir(p_kullanici uuid, p_devralan uuid, p_gerekce text) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  u hukuk.kullanici;
  n integer := 0;
  x integer;
BEGIN
  u := hukuk._yonetim_kontrol(p_kullanici);
  IF NOT u.aktif THEN
    RAISE EXCEPTION 'Hesap zaten pasif.' USING ERRCODE = '23514';
  END IF;
  IF coalesce(length(trim(p_gerekce)), 0) < 3 THEN
    RAISE EXCEPTION 'Gerekçe yazılmalıdır.' USING ERRCODE = '23514';
  END IF;
  IF p_devralan IS NOT NULL AND (p_devralan = u.id OR NOT EXISTS (
      SELECT 1 FROM hukuk.kullanici WHERE id = p_devralan AND kiraci_id = u.kiraci_id AND aktif AND kisi_id IS NULL)) THEN
    RAISE EXCEPTION 'Devralan aynı kurumda aktif bir kullanıcı olmalıdır.' USING ERRCODE = '23514';
  END IF;
  IF p_devralan IS NULL AND (
      EXISTS (SELECT 1 FROM hukuk.sure_kaydi WHERE asil_sorumlu = u.id AND durum IN ('teyitBekliyor', 'teyitli'))
      OR EXISTS (SELECT 1 FROM hukuk.dosya WHERE sorumlu = u.id AND kapanis IS NULL)
      OR EXISTS (SELECT 1 FROM hukuk.gorev WHERE atanan = u.id AND durum = 'acik')) THEN
    RAISE EXCEPTION 'Açık süre, görev ya da dosyası var; önce devralacak kişiyi seçin.' USING ERRCODE = '23514';
  END IF;
  IF p_devralan IS NOT NULL THEN
    -- Yedek, yeni asılla aynı kişi olamaz: o durumda yedek boşaltılır.
    UPDATE hukuk.sure_kaydi SET asil_sorumlu = p_devralan,
           yedek_sorumlu = CASE WHEN yedek_sorumlu = p_devralan THEN NULL ELSE yedek_sorumlu END
    WHERE asil_sorumlu = u.id AND durum IN ('teyitBekliyor', 'teyitli');
    GET DIAGNOSTICS x = ROW_COUNT; n := n + x;
    UPDATE hukuk.sure_kaydi SET yedek_sorumlu = CASE WHEN asil_sorumlu = p_devralan THEN NULL ELSE p_devralan END
    WHERE yedek_sorumlu = u.id AND durum IN ('teyitBekliyor', 'teyitli');
    GET DIAGNOSTICS x = ROW_COUNT; n := n + x;
    UPDATE hukuk.dosya SET sorumlu = p_devralan,
           yedek_sorumlu = CASE WHEN yedek_sorumlu = p_devralan THEN NULL ELSE yedek_sorumlu END
    WHERE sorumlu = u.id AND kapanis IS NULL;
    GET DIAGNOSTICS x = ROW_COUNT; n := n + x;
    UPDATE hukuk.dosya SET yedek_sorumlu = CASE WHEN sorumlu = p_devralan THEN NULL ELSE p_devralan END
    WHERE yedek_sorumlu = u.id AND kapanis IS NULL;
    GET DIAGNOSTICS x = ROW_COUNT; n := n + x;
    UPDATE hukuk.gorev SET atanan = p_devralan, yedek = CASE WHEN yedek = p_devralan THEN NULL ELSE yedek END
    WHERE atanan = u.id AND durum = 'acik';
    GET DIAGNOSTICS x = ROW_COUNT; n := n + x;
  END IF;
  UPDATE hukuk.kullanici SET aktif = false WHERE id = u.id;
  PERFORM hukuk._yonetici_kalmali(u.kiraci_id);
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  VALUES (u.kiraci_id, hukuk.aktif_kullanici(), 'degisiklik', 'kullanici', u.id::text,
          'Pasifleştirildi: ' || trim(p_gerekce) || CASE WHEN p_devralan IS NULL THEN '' ELSE ' · ' || n || ' kayıt devredildi' END,
          '', '');
  RETURN n;
END $$;

CREATE FUNCTION hukuk.kullanici_aktiflestir(p_kullanici uuid) RETURNS void
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
             AND rol NOT IN ('talepEden', 'onayci', 'muvekkil', 'denetci')) THEN
    SELECT * INTO k FROM hukuk.koltuk_durumu();
    IF k.dolu >= k.lisans THEN
      RAISE EXCEPTION 'Lisans koltuğu dolu (% / %). Önce koltuk ekleyin.', k.dolu, k.lisans USING ERRCODE = '23514';
    END IF;
  END IF;
  UPDATE hukuk.kullanici SET aktif = true WHERE id = u.id;
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  VALUES (u.kiraci_id, hukuk.aktif_kullanici(), 'degisiklik', 'kullanici', u.id::text, 'Yeniden etkinleştirildi', '', '');
END $$;

-- Şifre değiştirme: eski şifre sunucuda (Argon2) doğrulanır; özet yalnızca kendi hesabı için okunur.
CREATE FUNCTION hukuk.kendi_sifre_ozetim() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT sifre_ozeti FROM hukuk.kullanici WHERE id = hukuk.aktif_kullanici() AND aktif
$$;

-- Yeni şifre yazılır; bu oturum dışındaki tüm oturumlar kapanır.
CREATE FUNCTION hukuk.sifre_degistir(p_yeni_ozet text, p_mevcut_oturum char(64)) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
BEGIN
  UPDATE hukuk.kullanici SET sifre_ozeti = p_yeni_ozet WHERE id = hukuk.aktif_kullanici() AND aktif;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Oturum geçersiz.' USING ERRCODE = '42501';
  END IF;
  UPDATE hukuk.oturum SET iptal = now()
  WHERE kullanici_id = hukuk.aktif_kullanici() AND iptal IS NULL AND token_ozeti <> p_mevcut_oturum;
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  VALUES (hukuk.aktif_kiraci(), hukuk.aktif_kullanici(), 'degisiklik', 'kullanici', hukuk.aktif_kullanici()::text,
          'Şifre değiştirildi; diğer oturumlar kapatıldı', '', '');
END $$;

-- Kendi oturumları: tam özet yerine ilk 12 karakter kimlik olarak kullanılır.
CREATE FUNCTION hukuk.kendi_oturumlarim(p_mevcut char(64))
RETURNS TABLE (kimlik text, olusturma timestamptz, son_kullanma timestamptz, istemci text, bu_oturum boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT left(token_ozeti, 12), olusturma, son_kullanma, istemci, token_ozeti = p_mevcut
  FROM hukuk.oturum
  WHERE kullanici_id = hukuk.aktif_kullanici() AND iptal IS NULL AND son_kullanma > now()
  ORDER BY olusturma DESC
$$;

CREATE FUNCTION hukuk.kendi_oturumlarimi_kapat(p_kimlik text, p_mevcut char(64)) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  n integer;
BEGIN
  -- p_kimlik NULL: bu oturum dışındaki tümü.
  UPDATE hukuk.oturum SET iptal = now()
  WHERE kullanici_id = hukuk.aktif_kullanici() AND iptal IS NULL AND token_ozeti <> p_mevcut
    AND (p_kimlik IS NULL OR (length(p_kimlik) = 12 AND left(token_ozeti, 12) = p_kimlik));
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;

REVOKE ALL ON FUNCTION hukuk._yonetici_mi(uuid), hukuk._yonetici_kalmali(uuid), hukuk._yonetim_kontrol(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hukuk.kullanici_rolleri_degistir(uuid, text[]), hukuk.kullanici_pasiflestir(uuid, uuid, text),
  hukuk.kullanici_aktiflestir(uuid), hukuk.kendi_sifre_ozetim(), hukuk.sifre_degistir(text, char),
  hukuk.kendi_oturumlarim(char), hukuk.kendi_oturumlarimi_kapat(text, char), hukuk.hesap_rolleri(text) TO hukuk_uygulama;

COMMIT;
