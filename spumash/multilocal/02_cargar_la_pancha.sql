-- Cómo se creó ladys_3 (La Pancha Plancha) el 30-oct-2026, sin borrar nada:
-- 1) estructura vacía clonada desde ladys
select public.spumash_clonar_esquema('ladys', 'ladys_3', false);

-- 2) datos: cada tabla desde el respaldo de La Pancha (respaldo_lpp, 26 tablas) y, si no hay respaldo
--    de esa tabla, desde ladys (datos comunes de la demo: usuarios, máquinas, parámetros, rutinas…)
DO $$
DECLARE t text; cols text; seq text; n int := 0; origen text;
BEGIN
  EXECUTE 'SET LOCAL session_replication_role = replica';
  FOR t IN SELECT c.relname FROM pg_class c WHERE c.relnamespace = 'ladys_3'::regnamespace AND c.relkind = 'r' ORDER BY 1 LOOP
    origen := CASE WHEN to_regclass('respaldo_lpp.' || quote_ident(t)) IS NOT NULL THEN 'respaldo_lpp' ELSE 'ladys' END;
    SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum) INTO cols FROM pg_attribute a
     WHERE a.attrelid = format('ladys_3.%I', t)::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attgenerated = '';
    EXECUTE format('INSERT INTO ladys_3.%I (%s) SELECT %s FROM %I.%I', t, cols, cols, origen, t);
    IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = format('ladys_3.%I', t)::regclass AND attname = 'id' AND NOT attisdropped) THEN
      SELECT pg_get_serial_sequence('ladys_3.' || quote_ident(t), 'id') INTO seq;
      IF seq IS NOT NULL THEN EXECUTE format('SELECT setval(%L, GREATEST(COALESCE((SELECT max(id) FROM ladys_3.%I), 0), 1))', seq, t); END IF;
    END IF;
    n := n + 1;
  END LOOP;
  EXECUTE 'SET LOCAL session_replication_role = origin';
  RAISE NOTICE 'tablas cargadas: %', n;
END $$;

-- Resultado: ladys_3 → "La Pancha Plancha", 77 servicios activos, 10 rutas, 4 sectores, 13 pedidos, 3 usuarios.
