-- Spumash · demo con los datos de Lavandería Industrial JM Antofagasta
-- Reconfigura la base de la demo (proyecto Supabase spumash-demo) para que la app
-- muestre el catálogo, las zonas y los horarios de JM. Es un reemplazo: la demo
-- es de un solo local, así que al correr esto deja de mostrar al cliente anterior.
--
-- Fuentes (30-oct-2026): perfil de WhatsApp Business, catálogo Kyte
-- (lavanderiaindustrialjm.kyte.site), Instagram @lavanderia_jm.antofagasta,
-- agenda SumUp (Lavandería industrial JM Chile SPA).
-- Precios con dos versiones públicas: Kyte (1 cob. $13.000 / 2 $22.000 / 3 $32.000 / 4 $40.000)
-- e Instagram (1 $12.000 / 2 $20.000 / 3 $28.000 + combos con sábanas). Se cargan los de
-- Instagram por ser la promoción vigente que ellos mismos repiten; confirmar en la reunión.
--
-- Seguro de correr varias veces. Se ejecuta completo o no se ejecuta (una transacción).
-- CORRIDO el 30-oct-2026 16:05. Antes se respaldó La Pancha Plancha en el esquema respaldo_lpp;
-- para volver a ella: spumash/restaurar-respaldo.sql.

BEGIN;
SET search_path = ladys, public;

-- 1) El local ---------------------------------------------------------------
UPDATE locales SET
  nombre        = 'Lavandería Industrial JM Antofagasta',
  slogan        = 'Lavandería industrial · atención 24/7 · boleta y factura',
  telefono      = '+56 9 5010 5984',
  whatsapp      = '+56 9 4991 4233',
  email         = 'lavanderiajmantofagasta@gmail.com',
  razon_social  = 'Lavandería Industrial JM Chile SpA',
  horario       = 'Lunes a sábado 9:00 a 20:00 · retiro y entrega a domicilio en Antofagasta',
  tipo_servicio = 'local_y_delivery',
  dir_salida    = 'Av. Edmundo Pérez Zujovic 8360, Antofagasta (sector norte)',
  logo_url      = 'https://topkreativa.com/spumash/jm-antofagasta/logo-jm.png'
WHERE id = 1;

-- 2) Catálogo ---------------------------------------------------------------
UPDATE categorias SET activo = false WHERE local_id = 1;
UPDATE servicios  SET activo = false WHERE local_id = 1;

INSERT INTO categorias (local_id, nombre, orden, activo)
SELECT 1, n, o, true FROM (VALUES
  ('ROPA POR KILO', 1), ('COBERTORES Y PROMOCIONES', 2), ('ROPA DE CAMA Y BAÑO', 3),
  ('PRENDAS', 4), ('EMPRESAS', 5), ('DESPACHO', 6)) v(n, o)
WHERE NOT EXISTS (SELECT 1 FROM categorias c WHERE c.local_id = 1 AND c.nombre = v.n);
UPDATE categorias SET activo = true, orden = v.o
FROM (VALUES ('ROPA POR KILO', 1), ('COBERTORES Y PROMOCIONES', 2), ('ROPA DE CAMA Y BAÑO', 3),
  ('PRENDAS', 4), ('EMPRESAS', 5), ('DESPACHO', 6)) v(n, o)
WHERE categorias.local_id = 1 AND categorias.nombre = v.n;

-- Servicios de JM (ids 700+ para no chocar con los anteriores)
DELETE FROM orden_items WHERE servicio_id BETWEEN 700 AND 799;
DELETE FROM servicios WHERE id BETWEEN 700 AND 799;
INSERT INTO servicios (id, local_id, categoria_id, nombre, precio, precio_lav_planch, precio_lav_secado,
  precio_solo_planch, precio_productos, activo, dias_habiles, trabajo, es_adicional, es_producto, es_por_kilo, familia)
SELECT v.id, 1, c.id, v.nombre, v.precio,
  CASE WHEN v.modo = 'LP' THEN v.precio ELSE 0 END,
  CASE WHEN v.modo = 'L'  THEN v.precio ELSE 0 END,
  0, CASE WHEN v.modo = 'P' THEN v.precio ELSE 0 END,
  true, v.dias, v.trabajo, false, false, v.kilo, v.familia
FROM (VALUES
  -- id, categoría, nombre, precio, modo (L lavado / LP lavado y planchado / P producto), días, trabajo, por kilo, familia
  (701, 'ROPA POR KILO',            'ROPA POR KILO · LAVADO Y SECADO',              3200,  'L',  2, 'LAVA',      true,  'GRANEL'),
  (702, 'ROPA POR KILO',            'ROPA POR KILO · EXPRESS (MISMO DÍA)',          4200,  'L',  0, 'LAVA',      true,  'GRANEL'),
  (711, 'COBERTORES Y PROMOCIONES', 'COBERTOR · CUALQUIER TAMAÑO',                  12000, 'L',  3, 'LAVA',      false, 'COBERTOR_2P'),
  (712, 'COBERTORES Y PROMOCIONES', 'PROMO 2 COBERTORES',                           20000, 'L',  3, 'LAVA',      false, 'COBERTOR_2P'),
  (713, 'COBERTORES Y PROMOCIONES', 'PROMO 3 COBERTORES',                           28000, 'L',  3, 'LAVA',      false, 'COBERTOR_2P'),
  (714, 'COBERTORES Y PROMOCIONES', 'COMBO COBERTOR + 1 JUEGO DE SÁBANAS',          15000, 'L',  3, 'LAVA',      false, 'COBERTOR_2P'),
  (715, 'COBERTORES Y PROMOCIONES', 'COMBO COBERTOR + 2 JUEGOS DE SÁBANAS',         20000, 'L',  3, 'LAVA',      false, 'COBERTOR_2P'),
  (716, 'COBERTORES Y PROMOCIONES', 'COBERTOR DELICADO · PLUMAS',                   22590, 'L',  4, 'LAVA',      false, 'COBERTOR_2P'),
  (721, 'ROPA DE CAMA Y BAÑO',      'MANTA',                                        5990,  'L',  3, 'LAVA',      false, 'COBERTOR_CHICO'),
  (722, 'ROPA DE CAMA Y BAÑO',      'TOALLA PERSONAL',                              1490,  'L',  2, 'LAVA',      false, 'PRENDA_SUELTA'),
  (723, 'ROPA DE CAMA Y BAÑO',      'FUNDA DE ALMOHADA',                            1290,  'L',  2, 'LAVA',      false, 'PRENDA_SUELTA'),
  (731, 'PRENDAS',                  'PRENDA DE ROPA · LAVADO',                      1080,  'L',  2, 'LAVA',      false, 'PRENDA_SUELTA'),
  (741, 'EMPRESAS',                 'ROPA DE TRABAJO Y UNIFORMES · POR KILO',       3200,  'L',  2, 'LAVA',      true,  'GRANEL'),
  (742, 'EMPRESAS',                 'ROPA DE CAMA HOTELERA · POR KILO',             3200,  'L',  2, 'LAVA',      true,  'GRANEL'),
  (751, 'DESPACHO',                 'RETIRO Y ENTREGA A DOMICILIO · ANTOFAGASTA',   0,     'P',  0, 'NO_PRENDA', false, 'NO_CONSUME')
) v(id, cat, nombre, precio, modo, dias, trabajo, kilo, familia)
JOIN categorias c ON c.local_id = 1 AND c.nombre = v.cat;

-- 3) Zonas y rutas -------------------------------------------------------------
-- Antofagasta es una sola comuna: los sectores se definen por polígono (norte / centro / sur).
DELETE FROM sectores;
INSERT INTO sectores (codigo, nombre, poligonos, comunas, minimo_pedido, activo, nota) VALUES
  ('AFTA_NORTE',  'Antofagasta norte',  '[[[-23.50,-70.46],[-23.50,-70.36],[-23.625,-70.36],[-23.625,-70.46]]]'::jsonb, '{}', NULL, true, 'La Chimba, Trocadero, Bonilla, Pérez Zujovic · base de JM'),
  ('AFTA_CENTRO', 'Antofagasta centro', '[[[-23.625,-70.46],[-23.625,-70.36],[-23.675,-70.36],[-23.675,-70.46]]]'::jsonb, '{}', NULL, true, 'Centro, Brasil, Argentina, Angamos'),
  ('AFTA_SUR',    'Antofagasta sur',    '[[[-23.675,-70.46],[-23.675,-70.36],[-23.76,-70.36],[-23.76,-70.46]]]'::jsonb, '{}', NULL, true, 'Jardines del Sur, Coviefi, Huáscar, Coloso');

UPDATE rutas_base SET activo = false WHERE local_id = 1;
INSERT INTO rutas_base (local_id, nombre, tipo, dia_semana, hora_inicio, hora_fin, hrs_anticipacion, puntos_disp, activo)
SELECT 1, r.nombre, 'RETIROS_Y_ENTREGAS', d.dia, r.ini, r.fin, 3, 15, true
FROM (VALUES ('LUNES'), ('MARTES'), ('MIERCOLES'), ('JUEVES'), ('VIERNES'), ('SABADO')) d(dia)
CROSS JOIN (VALUES ('Mañana 09:00-13:00', '09:00'::time, '13:00'::time), ('Tarde 15:00-20:00', '15:00'::time, '20:00'::time)) r(nombre, ini, fin);

-- 4) Configuración visible en la app y en la asistente -------------------------
UPDATE configuracion SET valor = 'Lunes a sábado de 9:00 a 20:00. Atención por WhatsApp 24/7. Local en Av. Edmundo Pérez Zujovic 8360, sector norte de Antofagasta.' WHERE clave = 'horario_local';
UPDATE configuracion SET valor = 'Retiros y entregas de lunes a sábado: mañana 9:00 a 13:00 y tarde 15:00 a 20:00, en toda Antofagasta.' WHERE clave = 'horario_ruta';
UPDATE configuracion SET valor = 'Av. Edmundo Pérez Zujovic 8360, Antofagasta (sector norte). También retiramos y entregamos a domicilio.' WHERE clave = 'direccion_local';
UPDATE configuracion SET valor = 'lavanderiajmantofagasta@gmail.com' WHERE clave = 'email_contacto';
UPDATE configuracion SET valor = '56949914233' WHERE clave = 'whatsapp_local';
UPDATE configuracion SET valor = '3200' WHERE clave = 'precio_kilo';
UPDATE configuracion SET valor = '4200' WHERE clave = 'precio_kilo_express';
UPDATE configuracion SET valor = 'Lavandería Industrial JM Chile SpA · transferencia o pago en el local · emitimos boleta y factura' WHERE clave = 'datos_transferencia';
UPDATE configuracion SET valor = 'https://topkreativa.com/spumash/jm-antofagasta/app/' WHERE clave = 'url_app';
UPDATE configuracion SET valor = 'https://www.instagram.com/lavanderia_jm.antofagasta/' WHERE clave = 'resena_link';
UPDATE configuracion SET valor = '{"lat_min":-23.76,"lat_max":-23.50,"lng_min":-70.46,"lng_max":-70.36}' WHERE clave = 'domicilio_zona_sin_minimo';
UPDATE configuracion SET valor = '[
 {"tipo":"SIN_MINIMO","color":"#1E6FD9","codigo":"AFTA_NORTE","minimo":0,"nombre":"Antofagasta norte","detalle":"La Chimba, Trocadero, Bonilla y Pérez Zujovic · sin mínimo","poligono":[[-23.50,-70.46],[-23.50,-70.36],[-23.625,-70.36],[-23.625,-70.46]],"sector_rutas":null},
 {"tipo":"SIN_MINIMO","color":"#16a34a","codigo":"AFTA_CENTRO","minimo":0,"nombre":"Antofagasta centro","detalle":"Centro, Brasil, Argentina y Angamos · sin mínimo","poligono":[[-23.625,-70.46],[-23.625,-70.36],[-23.675,-70.36],[-23.675,-70.46]],"sector_rutas":null},
 {"tipo":"SIN_MINIMO","color":"#7C5CFF","codigo":"AFTA_SUR","minimo":0,"nombre":"Antofagasta sur","detalle":"Jardines del Sur, Coviefi, Huáscar y Coloso · sin mínimo","poligono":[[-23.675,-70.46],[-23.675,-70.36],[-23.76,-70.36],[-23.76,-70.46]],"sector_rutas":null}
]' WHERE clave = 'zonas_cobertura';
-- Textos de la asistente, campañas y reseñas: cambian el nombre del local y la ciudad.
UPDATE configuracion SET valor = replace(replace(replace(replace(replace(valor,
  'Lavandería Demo Concón', 'Lavandería JM'), 'Lavandería Demo', 'Lavandería JM'),
  'Concón y Reñaca', 'Antofagasta'), 'en Concón', 'en Antofagasta'), 'Concón', 'Antofagasta')
WHERE valor LIKE '%Lavandería Demo%' OR valor LIKE '%Concón%';

-- 5) Clientes y direcciones de ejemplo, ahora en Antofagasta -------------------
UPDATE direcciones_clientes d SET ciudad = 'Antofagasta', sector = v.sector, calle = v.calle, numero = v.numero,
  otro = v.otro, lat = v.lat, lng = v.lng, comuna_geo = 'Antofagasta'
FROM (VALUES
  (1,  'Antofagasta norte',  'Av. Edmundo Pérez Zujovic', '8360', 'Local',            -23.5648, -70.3990),
  (2,  'Antofagasta norte',  'Av. Pedro Aguirre Cerda',   '9596', NULL,               -23.5690, -70.3930),
  (3,  'Antofagasta norte',  'Av. Antonio Rendic',        '6840', 'Casa 12',          -23.5880, -70.3950),
  (4,  'Antofagasta centro', 'Av. Grecia',                '690',  'Depto 1203',       -23.6460, -70.4010),
  (5,  'Antofagasta centro', 'Av. Argentina',             '1810', NULL,               -23.6530, -70.3960),
  (6,  'Antofagasta centro', 'Av. Brasil',                '1420', 'Depto 504',        -23.6490, -70.3990),
  (7,  'Antofagasta centro', 'Av. Angamos',               '2170', NULL,               -23.6620, -70.4000),
  (8,  'Antofagasta sur',    'Av. Jaime Guzmán',          '5560', 'Casa',             -23.6920, -70.4120),
  (9,  'Antofagasta sur',    'Av. Séptimo de Línea',      '3400', NULL,               -23.6850, -70.4050),
  (10, 'Antofagasta norte',  'Av. Edmundo Pérez Zujovic', '7900', 'Bodega 3',         -23.5700, -70.3970),
  (11, 'Antofagasta centro', 'Av. Balmaceda',             '2575', 'Recepción',        -23.6420, -70.4030),
  (12, 'Antofagasta norte',  'Av. Salvador Allende',      '4300', 'Portería faena',   -23.5790, -70.3900)
) v(id, sector, calle, numero, otro, lat, lng) WHERE d.id = v.id;

-- Tres clientes de ejemplo pasan a ser empresas (uniformes, hotel, faena), con factura.
UPDATE clientes SET tipo = 'EMPRESA', tipo_doc = 'FACTURA', iva = true,
  razon_social = v.rs, giro = v.giro, id_fiscal = v.rut, nombre = v.nom, apellido = v.ape, plazo_pago = 30, regla_facturacion = 'CREDITO_RETIRO'
FROM (VALUES
  (10, 'Transportes del Norte Ltda. (ejemplo)', 'Transporte y logística', '76.111.222-3', 'Transportes del Norte', 'Uniformes'),
  (11, 'Hotel Costa Pacífico SpA (ejemplo)',    'Hotelería',              '76.333.444-5', 'Hotel Costa Pacífico', 'Ropa de cama'),
  (12, 'Servicios Mineros Atacama SpA (ejemplo)','Servicios a la minería','76.555.666-7', 'Servicios Mineros Atacama', 'Ropa de trabajo')
) v(id, rs, giro, rut, nom, ape) WHERE clientes.id = v.id;

-- 6) Pedidos de ejemplo con el catálogo de JM ----------------------------------
DELETE FROM orden_items WHERE orden_id IN (SELECT id FROM ordenes);
INSERT INTO orden_items (orden_id, servicio_id, nombre, cantidad, precio_unit, subtotal)
SELECT o.id, s.id, s.nombre, v.cant, s.precio, s.precio * v.cant
FROM (VALUES
  (1001, 712, 1), (1001, 723, 2),
  (1002, 701, 8),
  (1003, 714, 1),
  (1004, 711, 1), (1004, 722, 4),
  (1005, 701, 12), (1005, 731, 3),
  (1006, 713, 1),
  (1007, 716, 1),
  (1008, 701, 6), (1008, 721, 1),
  (1009, 715, 1),
  (1010, 741, 35),
  (1011, 742, 48), (1011, 722, 20),
  (1012, 741, 60),
  (1013, 701, 10)
) v(orden, serv, cant)
JOIN ordenes o ON o.id = v.orden
JOIN servicios s ON s.id = v.serv;

UPDATE ordenes o SET subtotal = t.s, monto_total = t.s + COALESCE(o.monto_delivery, 0),
  saldo_pendiente = CASE WHEN o.estado_pago = 'PAGADO' THEN 0 ELSE t.s + COALESCE(o.monto_delivery, 0) END,
  monto_abonado = CASE WHEN o.estado_pago = 'PAGADO' THEN t.s + COALESCE(o.monto_delivery, 0) ELSE COALESCE(o.monto_abonado, 0) END,
  kilos = t.kg
FROM (SELECT oi.orden_id, SUM(oi.subtotal) s, NULLIF(SUM(CASE WHEN s.es_por_kilo THEN oi.cantidad ELSE 0 END), 0) kg
      FROM orden_items oi JOIN servicios s ON s.id = oi.servicio_id GROUP BY oi.orden_id) t
WHERE o.id = t.orden_id;

-- Los pedidos y paradas apuntan a las rutas nuevas del mismo día y bloque horario.
UPDATE ordenes o SET ruta_recogida_id = n.id
FROM rutas_base v JOIN rutas_base n ON n.activo AND n.dia_semana = v.dia_semana AND n.hora_inicio = CASE WHEN v.hora_inicio < '14:00' THEN '09:00'::time ELSE '15:00'::time END
WHERE o.ruta_recogida_id = v.id AND NOT v.activo;
UPDATE ordenes o SET ruta_entrega_id = n.id
FROM rutas_base v JOIN rutas_base n ON n.activo AND n.dia_semana = v.dia_semana AND n.hora_inicio = CASE WHEN v.hora_inicio < '14:00' THEN '09:00'::time ELSE '15:00'::time END
WHERE o.ruta_entrega_id = v.id AND NOT v.activo;
UPDATE reparto_paradas p SET ruta_id = n.id
FROM rutas_base v JOIN rutas_base n ON n.activo AND n.dia_semana = v.dia_semana AND n.hora_inicio = CASE WHEN v.hora_inicio < '14:00' THEN '09:00'::time ELSE '15:00'::time END
WHERE p.ruta_id = v.id AND NOT v.activo;
UPDATE reparto_paradas p SET lat = d.lat, lng = d.lng FROM direcciones_clientes d WHERE p.direccion_id = d.id;

-- Fechas de ejemplo al presente, en semanas completas para que cada pedido siga en la ruta de su día (función ya existente en la demo).
SELECT demo_mover_fechas( ((current_date - 1 - (SELECT max(creado_en)::date FROM ordenes))::int / 7) * 7 );

-- 7) Comprobación -----------------------------------------------------------------
SELECT (SELECT nombre FROM locales WHERE id = 1) AS local,
       (SELECT count(*) FROM servicios WHERE activo) AS servicios_activos,
       (SELECT count(*) FROM rutas WHERE activo) AS rutas_activas,
       (SELECT count(*) FROM sectores WHERE activo) AS sectores,
       (SELECT count(*) FROM ordenes WHERE subtotal > 0) AS pedidos_con_monto,
       (SELECT count(*) FROM configuracion WHERE valor LIKE '%Lavandería Demo%' OR valor LIKE '%Concón%') AS textos_pendientes;
COMMIT;
