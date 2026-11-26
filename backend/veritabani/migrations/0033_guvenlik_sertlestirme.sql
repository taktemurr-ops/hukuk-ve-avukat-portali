-- Güvenlik sertleştirme (iç güvenlik testi, 26.11.2026).
-- 1) Kiracılar arası bağlantı: yabancı anahtar denetimi satır güvenliğini aşar; bir kurum, başka bir kurumun
--    kaydının kimliğini bilirse kendi satırını ona bağlayabiliyordu (ör. portal paylaşımıyla başka kurumun dosyasını
--    kendi müvekkiline göstermek). Artık kiraci_id taşıyan her tabloda, kiraci_id taşıyan bir tabloya giden tek
--    sütunlu her yabancı anahtar aynı kuruma ait olmak zorunda.
-- 2) Fonksiyonlar PUBLIC'e kapatılır; yalnızca uygulama rolü çalıştırır (bugünkü erişim aynen korunur).
BEGIN;

CREATE FUNCTION hukuk.ayni_kiraci_kontrol() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  i int := 0;
  v_deger uuid;
  v_kiraci uuid;
  v_yeni jsonb := to_jsonb(NEW);
BEGIN
  WHILE i < TG_NARGS LOOP
    v_deger := (v_yeni ->> TG_ARGV[i])::uuid;
    IF v_deger IS NOT NULL THEN
      EXECUTE format('SELECT kiraci_id FROM hukuk.%I WHERE id = $1', TG_ARGV[i + 1]) INTO v_kiraci USING v_deger;
      IF v_kiraci IS DISTINCT FROM (v_yeni ->> 'kiraci_id')::uuid THEN
        RAISE EXCEPTION 'Kayıt bulunamadı.' USING ERRCODE = '23503',
          DETAIL = format('%s.%s başka bir kuruma ait kayda bağlanamaz', TG_TABLE_NAME, TG_ARGV[i]);
      END IF;
    END IF;
    i := i + 2;
  END LOOP;
  RETURN NEW;
END $$;

DO $$
DECLARE
  r record;
  v_arg text;
BEGIN
  FOR r IN
    SELECT c.conrelid::regclass AS tablo, cr.relname AS tablo_ad,
           string_agg(format('%L, %L', a.attname, pr.relname), ', ' ORDER BY a.attname) AS argumanlar
    FROM pg_constraint c
    JOIN pg_class cr ON cr.oid = c.conrelid
    JOIN pg_class pr ON pr.oid = c.confrelid
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
    WHERE c.contype = 'f' AND c.connamespace = 'hukuk'::regnamespace AND cardinality(c.conkey) = 1
      AND pr.relname <> 'kiraci'
      AND EXISTS (SELECT 1 FROM pg_attribute x WHERE x.attrelid = c.conrelid AND x.attname = 'kiraci_id' AND NOT x.attisdropped)
      AND EXISTS (SELECT 1 FROM pg_attribute x WHERE x.attrelid = c.confrelid AND x.attname = 'kiraci_id' AND NOT x.attisdropped)
    GROUP BY c.conrelid, cr.relname
  LOOP
    EXECUTE format('CREATE TRIGGER ayni_kiraci BEFORE INSERT OR UPDATE ON %s FOR EACH ROW EXECUTE FUNCTION hukuk.ayni_kiraci_kontrol(%s)',
                   r.tablo, r.argumanlar);
  END LOOP;
END $$;

-- PUBLIC'e açık fonksiyonlar: uygulama rolüne açıkça verilip PUBLIC'ten alınır.
DO $$
DECLARE
  f record;
BEGIN
  FOR f IN SELECT p.oid::regprocedure AS imza FROM pg_proc p
           WHERE p.pronamespace = 'hukuk'::regnamespace AND has_function_privilege('public', p.oid, 'EXECUTE')
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO hukuk_uygulama', f.imza);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', f.imza);
  END LOOP;
END $$;
ALTER DEFAULT PRIVILEGES IN SCHEMA hukuk REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
REVOKE ALL ON FUNCTION hukuk.ayni_kiraci_kontrol() FROM PUBLIC;

COMMIT;
