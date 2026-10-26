#!/usr/bin/env bash
# Compila la app de Spumash (Lavandería Demo) desde el MISMO código de la app de Ladys.
# No es una app aparte: toma ladys-laundry-app/frontend tal como está y solo cambia
# a qué servidor apunta (proyecto Supabase spumash-demo), la ruta donde se publica
# (topkreativa.com/spumash/app/) y la marca visible (Lavandería Demo).
#
# Uso: build-demo.sh <ruta a ladys-laundry-app> <ruta a topkreativa-web>
# Resultado: reemplaza <topkreativa-web>/spumash/app/ con el build nuevo.
set -euo pipefail

APP="${1:?ruta a ladys-laundry-app}"
WEB="${2:?ruta a topkreativa-web}"
DEMO_REF="zgqerwslkdbeicvnunuc"
PROD_REF="vhjsizkbmabznupkfzji"
MARCA="Lavandería Demo"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp -r "$APP/frontend" "$TMP/fe"
cd "$TMP/fe"

# 1) Servidor: todo lo que apunta al proyecto de Ladys pasa al proyecto demo.
grep -rl "$PROD_REF" src | xargs -r sed -i "s/$PROD_REF/$DEMO_REF/g"

# 2) Ruta de publicación.
sed -i "s#base: '/app/'#base: '/spumash/app/'#" vite.config.ts
grep -rl "['\"\`]/app/" src | xargs -r sed -i \
  -e "s#\"/app/logo-ladys-completo.png#\"/spumash/app/logo-demo.svg#g" \
  -e "s#\"/app/logo-ladys.png#\"/spumash/app/logo-demo.svg#g" \
  -e "s#'/app/sw.js#'/spumash/app/sw.js#g" \
  -e "s#'/app/'#'/spumash/app/'#g" \
  -e "s#\`/app/index.html#\`/spumash/app/index.html#g"

# 3) Marca visible para el cliente final.
grep -rl "Ladys" src | xargs -r sed -i \
  -e "s/Ladys Lavandería Concón SpA/$MARCA SpA/g" \
  -e "s/Ladys Lavanderia Concon SpA/$MARCA SpA/g" \
  -e "s/Ladys Lavandería/$MARCA/g" \
  -e "s/Local Ladys/Local/g" \
  -e "s/WhatsApp oficial de Ladys/WhatsApp oficial de la lavandería/g" \
  -e "s/WhatsApp de Ladys/WhatsApp de la lavandería/g" \
  -e "s/La camioneta de Ladys/La camioneta/g" \
  -e "s/Club Ladys/Club/g" \
  -e "s/App Ladys/App/g"
sed -i \
  -e "s#contacto@ladyslavanderia.cl#contacto@topkreativa.com#g" \
  -e "s#<div>ladyslavanderia.cl</div>#<div>topkreativa.com/spumash</div>#g" \
  -e "s#'+56 9 7541 0232'#'+56 9 3874 0153'#g" \
  src/components/OtCarta.tsx
sed -i "s#https://ladyslavanderia.cl/ruta/#https://topkreativa.com/spumash/app/ruta/#g" src/lib/google.ts

# 4) Íconos, manifest y logo de la demo (los que ya están publicados).
rm -f public/logo-ladys*.png
for f in icono-192.png icono-512.png icono-mask-512.png logo-demo.svg manifest.webmanifest; do
  [ -f "$WEB/spumash/app/$f" ] && cp "$WEB/spumash/app/$f" public/
done
sed -i -e "s#/app/sw.js#/spumash/app/sw.js#g" -e "s#'/app/'#'/spumash/app/'#g" public/sw.js 2>/dev/null || true
sed -i \
  -e "s#href=\"/app/#href=\"/spumash/app/#g" \
  -e "s#<title>[^<]*</title>#<title>$MARCA</title>#" \
  -e "s#apple-mobile-web-app-title\" content=\"[^\"]*\"#apple-mobile-web-app-title\" content=\"$MARCA\"#" \
  index.html

# 5) Variables del build.
MAPS_KEY="$(grep -E '^VITE_GOOGLE_MAPS_KEY=' "$APP/frontend/.env" | cut -d= -f2- || true)"
cat > .env <<EOF
VITE_API_URL=https://$DEMO_REF.supabase.co/functions/v1/ladys/api
VITE_GOOGLE_MAPS_KEY=$MAPS_KEY
EOF

# 6) Comprobaciones antes de compilar: no puede quedar nada apuntando a Ladys.
if grep -rn "$PROD_REF" src index.html .env; then echo "ERROR: queda una referencia al proyecto de Ladys"; exit 1; fi

ln -s "$APP/frontend/node_modules" node_modules
npx vite build --logLevel warn

if grep -rl "$PROD_REF" dist; then echo "ERROR: el build apunta al proyecto de Ladys"; exit 1; fi

# 7) Publicar en el sitio.
rm -rf "$WEB/spumash/app"
cp -r dist "$WEB/spumash/app"
echo "OK: $(ls "$WEB/spumash/app/assets" | tr '\n' ' ')"
