/* Mi librería · service worker.
   - Solo guarda en caché archivos propios (mismo origen) con respuesta correcta.
   - No toca las peticiones a Supabase (ni a sus funciones), Open Library, Google Books ni CDN: van siempre a la red.
   - Al cambiar CACHE se eliminan solo las cachés antiguas de Mi librería. */
const CACHE = 'mi-libreria-v1-20261108';
const NETWORK_WAIT = 3500; // ms antes de usar la copia guardada si la red va muy lenta
const CORE = [
  './',
  './index.html',
  './manifest.webmanifest',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './supabase-config.js',
  './scanner-core.js',
  './avisos.js',
  './buzon.js',
  './styles.css',
  './app.js',
  './organizando-libreria.gif'
];
const OWN_CACHE = /^mi-libreria/i;

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE)
      .then((cache) => Promise.all(CORE.map((url) => cache.add(new Request(url, { cache: 'reload' })).catch(() => null))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE && OWN_CACHE.test(k)).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

function cacheIfOk(request, response) {
  if (response && response.ok && response.type === 'basic') {
    const copy = response.clone();
    caches.open(CACHE).then((cache) => cache.put(request, copy)).catch(() => {});
  }
  return response;
}

function offlineFallback(request) {
  return caches.match(request, { ignoreSearch: true }).then((hit) => {
    if (hit) return hit;
    if (request.mode === 'navigate') return caches.match('./index.html');
    return Response.error();
  });
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  // Supabase, APIs de libros, portadas externas y CDN: sin intervenir.
  if (url.origin !== self.location.origin) return;

  // GIF grandes: se guardan la primera vez que se usan y luego se sirven desde caché.
  if (url.pathname.endsWith('.gif')) {
    event.respondWith(
      caches.match(request).then((hit) => hit || fetch(request).then((res) => cacheIfOk(request, res)))
    );
    return;
  }

  // HTML, CSS y JavaScript: primero la red (para recibir actualizaciones). Si la red no contesta
  // en NETWORK_WAIT ms y hay copia guardada, se usa la copia (la red sigue y actualiza la caché).
  event.respondWith(networkFirst(request));
});

function networkFirst(request) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (response) => { if (!settled) { settled = true; resolve(response); } };
    const timer = setTimeout(() => {
      caches.match(request).then((hit) => { if (hit) finish(hit); });
    }, NETWORK_WAIT);
    // cache: 'no-cache' obliga a comprobar con GitHub Pages si hay versión nueva (si no, responde 304 y es rápido).
    fetch(request.url, { cache: 'no-cache', credentials: 'same-origin' })
      .then((res) => { clearTimeout(timer); finish(cacheIfOk(request, res)); })
      .catch(() => { clearTimeout(timer); offlineFallback(request).then(finish); });
  });
}


/* =====================================================================
   AVISOS (notificaciones push) de Mi librería
   ===================================================================== */
self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch { data = { title: 'Mi librería', body: event.data ? event.data.text() : '' }; }
  const scope = self.registration.scope;
  const title = data.title || 'Mi librería';
  const options = {
    body: data.body || '',
    icon: new URL('icons/icon-192.png', scope).href,
    badge: new URL('icons/icon-192.png', scope).href,
    tag: data.tag || undefined,
    renotify: !!data.tag,
    data: { url: new URL(data.url || 'index.html', scope).href },
    lang: 'es'
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = event.notification.data?.url || self.registration.scope;
  event.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const same = wins.find((w) => new URL(w.url).origin === new URL(target).origin);
    if (same) {
      try { await same.focus(); } catch { /* nada */ }
      try { return await same.navigate(target); } catch { /* algunos navegadores no dejan: se abre otra */ }
    }
    return self.clients.openWindow(target);
  })());
});

// Si el navegador renueva la suscripción, se avisa a las ventanas abiertas para registrarla otra vez.
self.addEventListener('pushsubscriptionchange', (event) => {
  event.waitUntil(self.clients.matchAll({ type: 'window' }).then((wins) => wins.forEach((w) => w.postMessage({ type: 'ml-push-renew' }))));
});
