-- Spumash · un esquema por lavandería dentro del mismo proyecto Supabase (spumash-demo).
-- public.spumash_clonar_esquema(origen, destino, con_datos) copia TODO lo que hay en el esquema
-- origen (tablas con índices y defaults, secuencias, claves foráneas, vistas, funciones y triggers)
-- a un esquema nuevo, reemplazando las referencias "origen." por "destino." dentro de las
-- definiciones. Con con_datos = true copia también las filas.
--
-- Solo para el proyecto demo. No toca el esquema origen.

CREATE OR REPLACE FUNCTION public.spumash_clonar_esquema(p_origen text, p_destino text, p_con_datos boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  r record; n int; pendientes text[]; intentos int; ok int; res jsonb := '{}'::jsonb;
  q_o text := quote_literal(p_origen); sp_antes text := current_setting('search_path');
BEGIN
  IF p_destino = p_origen OR p_destino !~ '^[a-z_][a-z0-9_]*$' THEN RAISE EXCEPTION 'destino inválido'; END IF;
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = p_destino) THEN RAISE EXCEPTION 'el esquema % ya existe', p_destino; END IF;
  EXECUTE format('CREATE SCHEMA %I', p_destino);

  -- 1) Secuencias propias
  n := 0;
  FOR r IN SELECT c.relname FROM pg_class c WHERE c.relnamespace = p_origen::regnamespace AND c.relkind = 'S' LOOP
    EXECUTE format('CREATE SEQUENCE %I.%I', p_destino, r.relname); n := n + 1;
  END LOOP;
  res := res || jsonb_build_object('secuencias', n);

  -- 2) Tablas (estructura completa) y defaults apuntando a las secuencias nuevas
  n := 0;
  FOR r IN SELECT c.relname FROM pg_class c WHERE c.relnamespace = p_origen::regnamespace AND c.relkind IN ('r','p') ORDER BY c.relname LOOP
    EXECUTE format('CREATE TABLE %I.%I (LIKE %I.%I INCLUDING ALL)', p_destino, r.relname, p_origen, r.relname); n := n + 1;
  END LOOP;
  FOR r IN SELECT c.relname AS tabla, a.attname AS col, pg_get_expr(d.adbin, d.adrelid) AS def
           FROM pg_attrdef d JOIN pg_class c ON c.oid = d.adrelid JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
           WHERE c.relnamespace = p_destino::regnamespace AND pg_get_expr(d.adbin, d.adrelid) LIKE '%' || p_origen || '.%' LOOP
    EXECUTE format('ALTER TABLE %I.%I ALTER COLUMN %I SET DEFAULT %s', p_destino, r.tabla, r.col,
                   replace(r.def, p_origen || '.', p_destino || '.'));
  END LOOP;
  res := res || jsonb_build_object('tablas', n);

  -- 3) Datos (sin triggers ni comprobación de claves foráneas durante la copia)
  IF p_con_datos THEN
    EXECUTE 'SET LOCAL session_replication_role = replica';
    n := 0;
    -- columnas explícitas: las columnas generadas no se pueden insertar
    FOR r IN SELECT c.relname, string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum) AS cols
             FROM pg_class c JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped AND a.attgenerated = ''
             WHERE c.relnamespace = p_origen::regnamespace AND c.relkind IN ('r','p') GROUP BY c.relname LOOP
      EXECUTE format('INSERT INTO %I.%I (%s) SELECT %s FROM %I.%I', p_destino, r.relname, r.cols, r.cols, p_origen, r.relname); n := n + 1;
    END LOOP;
    EXECUTE 'SET LOCAL session_replication_role = origin';
    -- secuencias al día
    FOR r IN SELECT c.relname AS tabla, a.attname AS col, pg_get_serial_sequence(format('%I.%I', p_destino, c.relname), a.attname) AS seq
             FROM pg_class c JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
             WHERE c.relnamespace = p_destino::regnamespace AND c.relkind = 'r'
               AND pg_get_serial_sequence(format('%I.%I', p_destino, c.relname), a.attname) IS NOT NULL LOOP
      EXECUTE format('SELECT setval(%L, GREATEST(COALESCE((SELECT max(%I) FROM %I.%I), 0), 1))', r.seq, r.col, p_destino, r.tabla);
    END LOOP;
    res := res || jsonb_build_object('tablas_con_datos', n);
  END IF;

  -- 4) Claves foráneas
  n := 0;
  FOR r IN SELECT c.conname, cl.relname AS tabla, pg_get_constraintdef(c.oid) AS def
           FROM pg_constraint c JOIN pg_class cl ON cl.oid = c.conrelid
           WHERE c.connamespace = p_origen::regnamespace AND c.contype = 'f' LOOP
    BEGIN
      EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I %s', p_destino, r.tabla, r.conname,
                     replace(replace(r.def, ' ' || p_origen || '.', ' ' || p_destino || '.'), 'REFERENCES ' || p_origen || '.', 'REFERENCES ' || p_destino || '.'));
      n := n + 1;
    EXCEPTION WHEN OTHERS THEN
      res := res || jsonb_build_object('fk_fallida_' || r.conname, SQLERRM);
    END;
  END LOOP;
  res := res || jsonb_build_object('claves_foraneas', n);

  -- 5) Funciones (reintentando hasta que todas pasen: algunas dependen de otras o de vistas).
  --    Se crean con el esquema destino en el search_path: las funciones SQL validan sus tablas al crearse.
  PERFORM set_config('search_path', format('%I, public', p_destino), true);
  pendientes := ARRAY(SELECT replace(replace(pg_get_functiondef(p.oid), p_origen || '.', p_destino || '.'), q_o, quote_literal(p_destino))
                      FROM pg_proc p WHERE p.pronamespace = p_origen::regnamespace AND p.prokind IN ('f','p'));
  -- 6) Vistas, en el mismo lote de reintentos
  pendientes := pendientes || ARRAY(SELECT format('CREATE VIEW %I.%I AS %s', p_destino, c.relname, replace(pg_get_viewdef(c.oid, true), p_origen || '.', p_destino || '.'))
                                    FROM pg_class c WHERE c.relnamespace = p_origen::regnamespace AND c.relkind = 'v');
  intentos := 0;
  WHILE coalesce(array_length(pendientes, 1), 0) > 0 AND intentos < 12 LOOP
    intentos := intentos + 1; ok := 0;
    DECLARE restantes text[] := '{}'; s text;
    BEGIN
      FOREACH s IN ARRAY pendientes LOOP
        BEGIN
          EXECUTE s; ok := ok + 1;
        EXCEPTION WHEN OTHERS THEN
          restantes := restantes || s;
        END;
      END LOOP;
      pendientes := restantes;
    END;
    EXIT WHEN ok = 0;
  END LOOP;
  res := res || jsonb_build_object('funciones', (SELECT count(*) FROM pg_proc WHERE pronamespace = p_destino::regnamespace),
                                   'vistas', (SELECT count(*) FROM pg_class WHERE relnamespace = p_destino::regnamespace AND relkind = 'v'),
                                   'sin_crear', coalesce(array_length(pendientes, 1), 0),
                                   'sin_crear_detalle', (SELECT jsonb_agg(left(x, 160)) FROM unnest(pendientes) x));

  -- 7) Triggers
  n := 0;
  FOR r IN SELECT pg_get_triggerdef(t.oid) AS def FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
           WHERE c.relnamespace = p_origen::regnamespace AND NOT t.tgisinternal LOOP
    BEGIN
      EXECUTE replace(r.def, p_origen || '.', p_destino || '.'); n := n + 1;
    EXCEPTION WHEN OTHERS THEN
      res := res || jsonb_build_object('trigger_fallido_' || n, left(r.def, 120) || ' :: ' || SQLERRM);
    END;
  END LOOP;
  res := res || jsonb_build_object('triggers', n);
  PERFORM set_config('search_path', sp_antes, true);
  RETURN res;
END $$;
