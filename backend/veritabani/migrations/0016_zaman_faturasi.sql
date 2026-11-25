-- Zaman kaydı faturası numarası (ZF-yıl-sıra) tüm kurum genelinde tekil olmalı; uygulama rolü görmediği dosyaların
-- kayıtlarını göremediği için sıra SECURITY DEFINER fonksiyonda hesaplanır.
CREATE FUNCTION hukuk.sonraki_zaman_fatura_no(p_yil integer) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT 'ZF-' || p_yil || '-' || lpad((coalesce(max(CAST(split_part(fatura_no, '-', 3) AS integer)), 0) + 1)::text, 4, '0')
  FROM hukuk.zaman_kaydi WHERE kiraci_id = hukuk.aktif_kiraci() AND fatura_no LIKE 'ZF-' || p_yil || '-%'
$$;
GRANT EXECUTE ON FUNCTION hukuk.sonraki_zaman_fatura_no(integer) TO hukuk_uygulama;
