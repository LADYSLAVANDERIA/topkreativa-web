// Service worker de Ladys.
//
// Existe por una sola razon: Chrome en Android solo ofrece el dialogo nativo de
// instalacion si el sitio tiene un service worker activo con un manejador de
// fetch. Sin esto, el boton "Tenla a mano en tu telefono" nunca recibe el
// evento y siempre cae al instructivo manual.
//
// A proposito NO guarda nada en cache. La app se publica copiando el build a
// otro repositorio, y un cache aqui haria que el cliente siguiera viendo una
// version vieja despues de cada despliegue, sin manera evidente de darse
// cuenta. Ese error es mucho mas caro que el poco que se ganaria offline.

self.addEventListener('install', () => self.skipWaiting())
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()))

// Deja pasar todo a la red, tal cual. El manejador tiene que existir, pero no
// tiene que hacer nada.
self.addEventListener('fetch', () => {})
