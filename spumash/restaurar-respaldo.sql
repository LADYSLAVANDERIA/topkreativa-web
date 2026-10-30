-- Spumash · vuelve la base demo a un respaldo guardado con "respaldar" (ver abajo).
-- Hoy existe el esquema respaldo_lpp (La Pancha Plancha, guardado el 30-oct-2026 antes de cargar JM).
-- La base demo es de un solo local: para mostrarle la demo a La Pancha Plancha el lunes 2-nov hay que
-- correr esto antes; para volver a JM, se corre de nuevo datos-jm.sql (jm-antofagasta/datos-jm.sql).
--
-- Cómo respaldar el estado actual en otro esquema (por ejemplo respaldo_jm):
--   igual que el bloque de abajo pero con CREATE TABLE respaldo_jm.t AS SELECT * FROM ladys.t
--
-- Uso: cambiar 'respaldo_lpp' por el esquema que se quiera restaurar. Se ejecuta completo o nada.

DO $$
DECLARE origen text := 'respaldo_lpp'; t text; seq text; n int := 0;
BEGIN
  IF coalesce((SELECT valor FROM ladys.configuracion WHERE clave = 'es_demo'), 'false') <> 'true' THEN
    RAISE EXCEPTION 'Solo corre en el proyecto demo';
  END IF;
  SET LOCAL session_replication_role = replica;  -- sin triggers mientras se copia
  FOR t IN SELECT table_name FROM information_schema.tables WHERE table_schema = origen ORDER BY table_name LOOP
    EXECUTE format('DELETE FROM ladys.%I', t);
    EXECUTE format('INSERT INTO ladys.%I SELECT * FROM %I.%I', t, origen, t);
    -- secuencia del id, si la tabla tiene una
    SELECT pg_get_serial_sequence('ladys.' || quote_ident(t), 'id') INTO seq;
    IF seq IS NOT NULL THEN
      EXECUTE format('SELECT setval(%L, COALESCE((SELECT max(id) FROM ladys.%I), 1))', seq, t);
    END IF;
    n := n + 1;
  END LOOP;
  RAISE NOTICE 'tablas restauradas desde %: %', origen, n;
END $$;

SELECT (SELECT nombre FROM ladys.locales WHERE id = 1) AS local,
       (SELECT count(*) FROM ladys.servicios WHERE activo) AS servicios_activos,
       (SELECT count(*) FROM ladys.rutas WHERE activo) AS rutas_activas,
       (SELECT count(*) FROM ladys.sectores WHERE activo) AS sectores,
       (SELECT count(*) FROM ladys.ordenes) AS pedidos;
