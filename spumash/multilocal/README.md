# Spumash · un esquema por lavandería (proyecto Supabase `spumash-demo`, ref `zgqerwslkdbeicvnunuc`)

Spumash es **aparte de Ladys**: nada de esto toca el proyecto de Ladys (`vhjsizkbmabznupkfzji`) ni su app.

## Cómo funciona
- Una sola base (un solo proyecto Supabase, sin costo extra). Cada lavandería vive en su propio
  esquema de Postgres con las mismas tablas, funciones, vistas y triggers:
  - `ladys`   → local 1 · demo genérica
  - `ladys_2` → local 2 · Lavandería Industrial JM Antofagasta
  - `ladys_3` → local 3 · La Pancha Plancha
- Las edge functions son las mismas para todas. En cada request eligen el esquema así:
  1. claim `esquema` del JWT (lo firma el login de la función `ladys`),
  2. cabecera `x-local` (`ladys_2`, o el número `2`),
  3. `?local=` en la URL,
  4. si no hay nada: `ladys`.
  Las llamadas internas entre funciones heredan el esquema (cabecera `x-local`).
- La app de cada cliente se compila con `LOCAL=<n>` en `build-demo.sh`: manda `x-local` en todas las
  llamadas (axios y fetch). Un usuario de JM no puede ver datos de otra lavandería aunque cambie la
  cabecera: el esquema viaja firmado dentro de su token.

## Archivos
- `01_clonar_esquema.sql` — `public.spumash_clonar_esquema(origen, destino, con_datos)`: crea un esquema
  nuevo copiando todo (109 tablas, 79 secuencias, 90 FK, 147 funciones, 32 vistas, 62 triggers).
  Ya está instalada en la base demo.
- `02_cargar_la_pancha.sql` — cómo se llenó `ladys_3` desde el respaldo `respaldo_lpp` (tablas sin
  respaldo se copiaron desde `ladys`: usuarios, máquinas, parámetros…).
- `parchar_funcion.py` — parche que convierte una edge function a multi-local. Se corre sobre una copia del
  código vivo (bajado con `get_edge_function` a `../funciones/<slug>/`, carpeta ignorada por git porque las
  funciones traen valores de respaldo de claves). Deja `index.ts.orig` con el original. El código vivo de
  referencia es siempre el que está desplegado en spumash-demo.

## Agregar una lavandería nueva
1. `select public.spumash_clonar_esquema('ladys', 'ladys_4', false);`
2. Cargar sus datos (local, catálogo, rutas, sectores, configuración, usuarios) en `ladys_4`.
3. Compilar su app: `LOCAL=4 MARCA=… CARPETA=… bash spumash/build-demo.sh …`

## Pendientes conocidos
- Las funciones de Postgres que llaman a edge functions por `pg_net` (avisos, WhatsApp) no mandan
  `x-local`: caen en `ladys`. En la demo SofIA y WhatsApp están apagados, así que no afecta.
- `ladys` (local 1) quedó con los datos de JM del 30-oct; conviene volver a ponerle los datos de
  "Lavandería Demo" cuando haya tiempo (hay que correr DELETE, que pide confirmación en Supabase).
- La FK `cajas_usuario_id_fkey` no se pudo recrear en `ladys_2` porque la demo trae una caja con un
  usuario que no existe (dato de ejemplo); no afecta al funcionamiento.
