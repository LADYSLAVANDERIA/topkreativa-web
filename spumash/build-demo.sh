#!/usr/bin/env bash
# Compila la app de Spumash desde el MISMO código de la app de Ladys.
# No es una app aparte: toma ladys-laundry-app/frontend tal como está y solo cambia
# a qué servidor apunta (proyecto Supabase spumash-demo), la ruta donde se publica
# y la marca visible.
#
# Uso: build-demo.sh <ruta a ladys-laundry-app> <ruta a topkreativa-web>
# Variables opcionales (por cliente):
#   MARCA     nombre visible           (por defecto "Lavandería Demo")
#   CARPETA   carpeta en spumash/      (por defecto "app" → topkreativa.com/spumash/app/)
#   LOGO      URL o ruta del logo      (por defecto el logo de la demo)
#   CORREO    correo de ejemplo en el login (por defecto demo@topkreativa.com)
#   CONTACTO_TEL / CONTACTO_MAIL / CONTACTO_WEB  datos que salen en la OT impresa
# Resultado: reemplaza <topkreativa-web>/spumash/<CARPETA>/ con el build nuevo.
set -euo pipefail

APP="${1:?ruta a ladys-laundry-app}"
WEB="${2:?ruta a topkreativa-web}"
DEMO_REF="zgqerwslkdbeicvnunuc"
PROD_REF="vhjsizkbmabznupkfzji"
MARCA="${MARCA:-Lavandería Demo}"
CARPETA="${CARPETA:-app}"
BASE="/spumash/$CARPETA/"
LOGO="${LOGO:-${BASE}logo-demo.svg}"
CORREO="${CORREO:-demo@topkreativa.com}"
CONTACTO_TEL="${CONTACTO_TEL:-+56 9 3874 0153}"
CONTACTO_MAIL="${CONTACTO_MAIL:-contacto@topkreativa.com}"
CONTACTO_WEB="${CONTACTO_WEB:-topkreativa.com/spumash}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp -r "$APP/frontend" "$TMP/fe"
cd "$TMP/fe"

# 1) Servidor: todo lo que apunta al proyecto de Ladys pasa al proyecto demo.
grep -rl "$PROD_REF" src | xargs -r sed -i "s/$PROD_REF/$DEMO_REF/g"

# 2) Ruta de publicación y logo.
sed -i "s#base: '/app/'#base: '$BASE'#" vite.config.ts
grep -rl "['\"\`]/app/" src | xargs -r sed -i \
  -e "s#\"/app/logo-ladys-completo.png#\"$LOGO#g" \
  -e "s#\"/app/logo-ladys.png#\"$LOGO#g" \
  -e "s#'/app/sw.js#'${BASE}sw.js#g" \
  -e "s#'/app/'#'$BASE'#g" \
  -e "s#\`/app/index.html#\`${BASE}index.html#g"

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
  -e "s#contacto@ladyslavanderia.cl#$CONTACTO_MAIL#g" \
  -e "s#<div>ladyslavanderia.cl</div>#<div>$CONTACTO_WEB</div>#g" \
  -e "s#'+56 9 7541 0232'#'$CONTACTO_TEL'#g" \
  src/components/OtCarta.tsx
sed -i "s/useState('admin@ladys.cl')/useState('$CORREO')/" src/pages/Login.tsx
sed -i "s#https://ladyslavanderia.cl/ruta/#https://topkreativa.com${BASE}ruta/#g" src/lib/google.ts

# 4) Íconos, manifest y logo de la demo (los que ya están publicados en spumash/app).
rm -f public/logo-ladys*.png
for f in icono-192.png icono-512.png icono-mask-512.png logo-demo.svg manifest.webmanifest; do
  [ -f "$WEB/spumash/app/$f" ] && cp "$WEB/spumash/app/$f" public/
done
sed -i -e "s#/spumash/app/#$BASE#g" -e "s#\"name\": *\"[^\"]*\"#\"name\": \"$MARCA\"#" -e "s#\"short_name\": *\"[^\"]*\"#\"short_name\": \"$MARCA\"#" public/manifest.webmanifest 2>/dev/null || true
sed -i -e "s#/app/sw.js#${BASE}sw.js#g" -e "s#'/app/'#'$BASE'#g" public/sw.js 2>/dev/null || true
sed -i \
  -e "s#href=\"/app/#href=\"$BASE#g" \
  -e "s#<title>[^<]*</title>#<title>$MARCA</title>#" \
  -e "s#apple-mobile-web-app-title\" content=\"[^\"]*\"#apple-mobile-web-app-title\" content=\"$MARCA\"#" \
  -e "s#</head>#<meta name=\"robots\" content=\"noindex\" /></head>#" \
  index.html

# 4b) Colores de Spumash (no los de Ladys): azul #1E6FD9 en lugar del fucsia,
#     cian #22D3EE en lugar del celeste y violeta #7C5CFF en lugar del lila.
#     Se reemplaza la escala "pink" de Tailwind y la "primary" del proyecto.
cat > tailwind.config.js <<'EOF'
/** @type {import('tailwindcss').Config} */
const azul = { DEFAULT: '#1E6FD9', 50: '#EEF5FE', 100: '#D9E8FC', 200: '#B7D3F9', 300: '#88B6F3', 400: '#5294EA',
  500: '#1E6FD9', 600: '#185CB8', 700: '#144A94', 800: '#123E78', 900: '#0A1530' }
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        primary: azul,
        pink: azul,
        blue:    { DEFAULT: '#22D3EE', 500: '#22D3EE', 600: '#0EB8D4' },
        purple:  { DEFAULT: '#7C5CFF', 500: '#7C5CFF' },
      }
    },
  },
  plugins: [],
}
EOF
grep -rliE "#E8177A|#4AAEE0|#A87BC8|#BE185D" src index.html public | xargs -r sed -i \
  -e "s/#[Ee]8177[Aa]/#1E6FD9/g" -e "s/#4[Aa][Aa][Ee][Ee]0/#22D3EE/g" \
  -e "s/#[Aa]87[Bb][Cc]8/#7C5CFF/g" -e "s/#[Bb][Ee]185[Dd]/#144A94/g"

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
rm -rf "$WEB/spumash/$CARPETA"
cp -r dist "$WEB/spumash/$CARPETA"
echo "OK: $BASE $(ls "$WEB/spumash/$CARPETA/assets" | tr '\n' ' ')"
