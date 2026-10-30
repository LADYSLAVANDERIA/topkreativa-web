#!/usr/bin/env python3
"""Spumash multi-local: parcha una edge function para que use el esquema de la lavandería
que corresponde (ladys = local 1, ladys_2 = local 2, ...), elegido por request.

Qué hace con index.ts:
 1. Reemplaza `const SQL = postgres(URL, {... search_path: "ladys, public" ...})` por un proxy
    que entrega un pool por esquema, con las MISMAS opciones originales salvo el search_path.
 2. Envuelve el handler de Deno.serve en AsyncLocalStorage con el esquema del request:
    claim `esquema` del JWT → cabecera x-local → ?local= → "ladys".
 3. Propaga el esquema en llamadas internas a otras funciones (fetch a /functions/v1/…) con x-local.
 4. En la función `ladys`, el login firma el JWT con el esquema (claim `esquema`).

Uso: parchar_funcion.py <carpeta de la función>   (deja index.ts parchado e index.ts.orig)
Idempotente: si ya está parchado, no hace nada.
"""
import re, sys, pathlib

MARCA = "// ── Spumash multi-local"

CABECERA = '''
// ── Spumash multi-local: un esquema por lavandería (ladys = local 1, ladys_2 = local 2, …).
//    El esquema se decide por request: claim "esquema" del JWT → cabecera x-local → ?local= → "ladys".
//    SQL es un proxy: cada esquema tiene su propio pool con las mismas opciones, solo cambia el search_path.
import { AsyncLocalStorage } from "node:async_hooks";
const __als = new AsyncLocalStorage<string>();
const __pools: Record<string, any> = {};
const __esquemaValido = (e: unknown) => /^ladys(_[0-9]{1,4})?$/.test(String(e || ""));
const __esquema = (): string => __als.getStore() || "ladys";
function __pool(e: string = __esquema()) {
  if (!__pools[e]) {
    const o: any = __OPCIONES__;
    o.connection = { ...(o.connection || {}), search_path: `${e}, public` };
    __pools[e] = postgres(Deno.env.get("SUPABASE_DB_URL")!, o);
  }
  return __pools[e];
}
const SQL: any = new Proxy(function () {} as any, {
  apply: (_t, _this, args) => __pool()(...args),
  get: (_t, prop) => { const p = __pool(); const v = p[prop as any]; return typeof v === "function" ? v.bind(p) : v; },
});
function __esquemaDe(req: Request): string {
  const url = new URL(req.url);
  const h = req.headers.get("authorization") || "";
  const tok = h.startsWith("Bearer ") ? h.slice(7) : (url.searchParams.get("t") || "");
  if (tok && tok.split(".").length === 3) {
    try {
      const p = JSON.parse(atob(tok.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
      if (__esquemaValido(p?.esquema)) return String(p.esquema);
    } catch { /* token ajeno o ilegible: se sigue con la cabecera */ }
  }
  const x = req.headers.get("x-local") || url.searchParams.get("local") || "";
  if (__esquemaValido(x)) return x;
  if (/^[0-9]{1,4}$/.test(x)) return Number(x) <= 1 ? "ladys" : `ladys_${Number(x)}`;
  return "ladys";
}
// Las llamadas internas entre funciones llevan el esquema del request.
const __fetch0 = globalThis.fetch;
globalThis.fetch = ((input: any, init: any = {}) => {
  const u = typeof input === "string" ? input : (input?.url || "");
  if (u.includes("/functions/v1/")) {
    const hdr = new Headers(init.headers || (input instanceof Request ? input.headers : undefined));
    if (!hdr.has("x-local")) hdr.set("x-local", __esquema());
    init = { ...init, headers: hdr };
  }
  return __fetch0(input, init);
}) as typeof fetch;
'''

def parchar(carpeta: str) -> str:
    p = pathlib.Path(carpeta) / "index.ts"
    src = p.read_text(encoding="utf-8")
    if MARCA in src:
        return "ya parchado"
    # 1) const SQL = postgres(URL, { ... });  (puede ocupar varias líneas; la llave de cierre va seguida de ");")
    m = re.search(r'const SQL\s*=\s*postgres\(\s*Deno\.env\.get\("SUPABASE_DB_URL"\)!?\s*,\s*(\{.*?\})\s*\);', src, re.S)
    if not m:
        return "NO ENCONTRÉ const SQL = postgres(...)"
    opciones = m.group(1)
    if "search_path" not in opciones:
        return "las opciones no traen search_path: revisar a mano"
    opciones = re.sub(r'search_path\s*:\s*["\'][^"\']*["\']\s*,?\s*', "", opciones)
    opciones = re.sub(r',\s*}', " }", opciones)  # coma colgante que pudo quedar
    cabecera = CABECERA.replace("__OPCIONES__", opciones)
    src = src[: m.start()] + cabecera.strip("\n") + "\n" + src[m.end():]
    # 1b) CORS: el navegador manda la cabecera x-local → debe estar permitida en el preflight
    def _cors(mm):
        lista = mm.group(2)
        if "*" in lista or "x-local" in lista.lower():
            return mm.group(0)
        return f'{mm.group(1)}x-local, {lista}{mm.group(3)}'
    src, ncors = re.subn(r'(["\']?access-control-allow-headers["\']?\s*:\s*["\'])([^"\']*)(["\'])', _cors, src, flags=re.I)
    # 2) Deno.serve(async (req: Request) => { ... });  → handler + serve envuelto
    n = src.count("Deno.serve(")
    if n != 1:
        return f"Deno.serve aparece {n} veces: revisar a mano"
    src2 = re.sub(r'Deno\.serve\(\s*async\s*\((req)(\s*:\s*Request)?\)(\s*:\s*Promise<Response>)?\s*=>\s*\{', "const __handler = async (req: Request) => {", src, count=1)
    if src2 == src:
        return "no reconocí la forma de Deno.serve(async (req) => {"
    src = src2
    # el cierre: la última ocurrencia de "});" en el archivo
    i = src.rstrip().rfind("});")
    if i < 0:
        return "no encontré el cierre });"
    src = src[:i] + "};\nDeno.serve((req: Request) => __als.run(__esquemaDe(req), () => __handler(req)));\n"
    # 3b) referencias calificadas "ladys.xxx" dentro del SQL (funciones o tablas): el search_path ya apunta al esquema
    src, nq = re.subn(r'(?<=[\s(,=`])ladys\.(?!cl\b|com\b|net\b)(?=[a-z_][a-z0-9_]*)', "", src)
    # 4) login de la función principal: el JWT lleva el esquema
    src = src.replace("const token = await firmar({ id: u.id, local_id: u.local_id, perfil: u.perfil, nombre: u.nombre });",
                      "const token = await firmar({ id: u.id, local_id: u.local_id, perfil: u.perfil, nombre: u.nombre, esquema: __esquema() });")
    (pathlib.Path(carpeta) / "index.ts.orig").write_text(p.read_text(encoding="utf-8"), encoding="utf-8")
    p.write_text(src, encoding="utf-8")
    return f"ok (referencias ladys. quitadas: {nq}, cors ajustados: {ncors})"

if __name__ == "__main__":
    for c in sys.argv[1:]:
        print(f"{c}: {parchar(c)}")
