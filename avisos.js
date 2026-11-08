/* =====================================================================
   MI LIBRERÍA · AVISOS (notificaciones push)
   · La primera vez que se entra se piden las notificaciones. Sin ellas no se entra.
     (Si están permitidas pero el servidor falla, se entra y se reintenta al volver.)
   · No hay usuarios: TODOS los dispositivos que hayan entrado una vez reciben todos los avisos
     (recomendaciones, recordatorios de préstamos, sugerencias del buzón y novedades).
   · Arriba a la derecha queda una campana: estado, probar un aviso y reactivarlos.
   · Sin librerías: fetch a la API REST con la publishable key.
   ===================================================================== */
(function () {
  'use strict';
  if (window.MisAvisos) return;

  const APP = 'Mi librería';
  const PUSH_FN = 'ml-push';
  const VAPID_KEY = 'mlVapid';
  const st = { cfg: null, pushState: 'unknown', pushError: '', reg: null, vapid: null };
  let readyResolve;
  const ready = new Promise((r) => { readyResolve = r; });

  const $ = (q, el = document) => el.querySelector(q);
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const lsGet = (k) => { try { return localStorage.getItem(k); } catch { return null; } };
  const lsSet = (k, v) => { try { if (v == null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch { /* sin almacenamiento */ } };

  const isIOS = () => /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const isStandalone = () => navigator.standalone === true || matchMedia('(display-mode: standalone)').matches;
  const pushSupported = () => 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;

  /* ---------- Supabase ---------- */
  function loadConfig() {
    if (st.cfg) return Promise.resolve(st.cfg);
    const c = window.LIBRERIA_SUPABASE;
    const key = c && (c.publishableKey || c.anonKey);
    if (c?.url && key) { st.cfg = { url: String(c.url).replace(/\/+$/, ''), key }; return Promise.resolve(st.cfg); }
    return Promise.reject(new Error('Falta la configuración de Supabase (supabase-config.js).'));
  }
  async function call(path, { method = 'POST', body = null } = {}) {
    const cfg = await loadConfig();
    const c = new AbortController();
    const t = setTimeout(() => c.abort(), 12000);
    try {
      const res = await fetch(`${cfg.url}${path}`, { method, headers: { apikey: cfg.key, Accept: 'application/json', ...(body ? { 'Content-Type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : null, cache: 'no-store', signal: c.signal });
      const text = await res.text();
      const data = text ? JSON.parse(text) : null;
      if (!res.ok) throw Object.assign(new Error(data?.message || `Error ${res.status}`), { status: res.status, code: data?.code });
      return data;
    } finally { clearTimeout(t); }
  }
  const rpc = (name, args) => call(`/rest/v1/rpc/${name}`, { body: args });

  async function vapidKey() {
    const cached = lsGet(VAPID_KEY);
    if (cached) return cached;
    let k = null;
    try { k = await rpc('ml_push_public_key', {}); } catch { k = null; }
    if (!k) { const r = await call(`/functions/v1/${PUSH_FN}?action=key`, { method: 'GET' }); k = r?.publicKey || null; }
    if (!k) throw new Error(`Los avisos todavía no están preparados en Supabase (falta la función ${PUSH_FN}).`);
    lsSet(VAPID_KEY, k);
    return k;
  }
  const keyBytes = (b64) => { const t = b64.replace(/-/g, '+').replace(/_/g, '/'); const bin = atob(t + '='.repeat((4 - (t.length % 4)) % 4)); return Uint8Array.from(bin, (c) => c.charCodeAt(0)); };
  const toB64u = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

  function swReady(ms = 10000) {
    // El service worker lo registra app.js; si aún no lo ha hecho, se registra aquí.
    navigator.serviceWorker.getRegistration('./').then((r) => r || navigator.serviceWorker.register('./service-worker.js', { scope: './' })).catch(() => {});
    return Promise.race([navigator.serviceWorker.ready, new Promise((_, rej) => setTimeout(() => rej(new Error(`El servicio de ${APP} no ha arrancado en este navegador.`)), ms))]);
  }

  /** Prepara el servicio y la clave antes de pedir permiso (en iPhone, suscribirse tiene que ir pegado al toque). */
  async function prepare() {
    try { st.reg = await swReady(); st.vapid = await vapidKey(); } catch (e) { st.prepError = e; }
  }
  async function register(sub) {
    const j = sub.toJSON();
    await rpc('ml_push_register', { p_endpoint: j.endpoint, p_p256dh: j.keys.p256dh, p_auth: j.keys.auth, p_ua: navigator.userAgent.slice(0, 400) });
    st.pushState = 'ok';
    st.pushError = '';
    paintBell();
  }
  async function subscribeAndRegister() {
    const reg = st.reg || await swReady();
    st.reg = reg;
    let sub = await reg.pushManager.getSubscription();
    const key = st.vapid || await vapidKey();
    st.vapid = key;
    if (sub) {
      // Si la suscripción es de otra clave (por ejemplo, se rehicieron las claves), se rehace.
      const k = sub.options?.applicationServerKey;
      if (k && toB64u(k) !== key) { await sub.unsubscribe().catch(() => {}); sub = null; }
    }
    if (!sub) sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(key) });
    await register(sub);
  }

  /* ---------- Estilos ---------- */
  function injectStyles() {
    if ($('#avStyles')) return;
    const el = document.createElement('style');
    el.id = 'avStyles';
    el.textContent = `
#avGate{position:fixed;inset:0;z-index:5000;display:grid;place-items:center;padding:18px;background:radial-gradient(circle at 20% 10%,#ffd9e6 0,transparent 40%),radial-gradient(circle at 90% 90%,#d9e8ff 0,transparent 45%),#fff8eb;overflow:auto;font:16px/1.4 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:#243047}
#avGate *{box-sizing:border-box}
#avGate .av-box{width:min(520px,100%);background:#fffdf8;border-radius:28px;padding:26px 22px;box-shadow:0 22px 60px #4b3b2630;text-align:center}
#avGate .av-ico{font-size:52px;line-height:1;margin-bottom:8px}
#avGate h2{margin:0 0 6px;font-size:clamp(24px,6vw,30px)}
#avGate p{margin:0 0 14px;color:#687086}
#avGate .av-btn{appearance:none;border:0;border-radius:15px;padding:13px 18px;min-height:50px;font:inherit;font-weight:900;cursor:pointer;background:#c95c93;color:#fff;width:100%;margin-top:8px;font-size:17px}
#avGate .av-btn.grey{background:#f1ece3;color:#243047}
#avGate .av-steps{text-align:left;background:#f8f5ef;border-radius:16px;padding:12px 14px 12px 34px;margin:0 0 12px;color:#243047}
#avGate .av-steps li{margin:4px 0}
#avGate .av-err{color:#c0392b;font-weight:800;min-height:1.2em;margin:8px 0 0}
.av-bell{appearance:none;-webkit-appearance:none;border:0;padding:0;background:#fff;color:inherit;width:42px;height:42px;border-radius:50%;margin-left:auto;flex:0 0 auto;cursor:pointer;position:relative;z-index:5;font-size:20px;line-height:1;display:grid;place-items:center;box-shadow:0 2px 8px #0002}
.sync-status:not([hidden])+.av-bell{margin-left:8px}
.av-bell:focus-visible{outline:3px solid #c95c93;outline-offset:2px}
.av-bell .av-dot{position:absolute;right:1px;bottom:1px;width:12px;height:12px;border-radius:50%;border:2px solid #fff;background:#2fae86}
.av-bell .av-dot.warn{background:#e5a93d}
#avMenu{position:fixed;z-index:4800;width:min(300px,calc(100vw - 24px));background:#fffdf8;border-radius:20px;box-shadow:0 18px 50px #2430473a;padding:14px;font:15px/1.35 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:#243047;border:1px solid #efe6d6}
#avMenu[hidden]{display:none}
#avMenu .av-status{font-size:14px;color:#687086;margin:0 0 8px;font-weight:700}
#avMenu .av-status.warn{color:#9a5b00}
#avMenu button.av-item{appearance:none;display:flex;align-items:center;gap:10px;width:100%;border:0;border-radius:12px;background:transparent;padding:11px 10px;font:inherit;font-weight:850;color:#243047;cursor:pointer;text-align:left;min-height:44px}
#avMenu button.av-item:hover,#avMenu button.av-item:focus-visible{background:#f8f2e6;outline:0}
html.av-locked,html.av-locked body{overflow:hidden!important}`;
    document.head.appendChild(el);
  }

  /* ---------- Pantalla de entrada ---------- */
  function gate(html) {
    injectStyles();
    let g = $('#avGate');
    if (!g) {
      g = document.createElement('div');
      g.id = 'avGate';
      g.setAttribute('role', 'dialog');
      g.setAttribute('aria-modal', 'true');
      document.body.appendChild(g);
    }
    g.innerHTML = `<div class="av-box">${html}</div>`;
    document.documentElement.classList.add('av-locked');
    return g;
  }
  function closeGate() { $('#avGate')?.remove(); document.documentElement.classList.remove('av-locked'); }

  function gateChoice(html, buttons, error = '') {
    return new Promise((resolve) => {
      const g = gate(`${html}${buttons.map((b, i) => `<button type="button" class="av-btn${b.grey ? ' grey' : ''}" data-av-choice="${i}">${esc(b.label)}</button>`).join('')}<p class="av-err" role="alert">${esc(error)}</p>`);
      g.onclick = (e) => {
        const el = e.target.closest('[data-av-choice]');
        if (!el) return;
        const b = buttons[Number(el.dataset.avChoice)];
        g.onclick = null;
        let pressed = null;
        if (b.press) { try { pressed = b.press(); } catch (err) { pressed = Promise.reject(err); } }
        if (pressed) pressed.catch(() => {});
        resolve({ value: b.value, pressed });
      };
      setTimeout(() => g.querySelector('.av-btn')?.focus(), 50);
    });
  }

  const installSteps = () => `<ol class="av-steps"><li>Abre esta página en <b>Safari</b>.</li><li>Pulsa <b>Compartir</b> (el cuadrado con la flecha ↑).</li><li>Elige <b>«Añadir a pantalla de inicio»</b>.</li><li>Abre ${APP} desde su icono.</li></ol>`;
  function deniedSteps() {
    if (isIOS()) return `<ol class="av-steps"><li>Abre <b>Ajustes</b> del iPhone o iPad.</li><li>Entra en <b>Notificaciones</b> → <b>${APP}</b>.</li><li>Activa <b>Permitir notificaciones</b>.</li><li>Vuelve aquí y pulsa «Ya las he activado».</li></ol>`;
    if (/Android/i.test(navigator.userAgent)) return `<ol class="av-steps"><li>Mantén pulsado el icono de <b>${APP}</b> → <b>Información de la app</b> (o Ajustes → Aplicaciones → Chrome).</li><li>Entra en <b>Notificaciones</b> y actívalas.</li><li>Si la usas en Chrome: toca el candado junto a la dirección → <b>Permisos</b> → <b>Notificaciones: Permitir</b>.</li><li>Vuelve aquí y pulsa «Ya las he activado».</li></ol>`;
    return `<ol class="av-steps"><li>Haz clic en el <b>candado</b> (o el icono de ajustes) junto a la dirección.</li><li>En <b>Notificaciones</b>, elige <b>Permitir</b>.</li><li>Comprueba que las notificaciones del navegador están activadas en los ajustes del ordenador.</li><li>Pulsa «Ya las he activado».</li></ol>`;
  }
  const INTRO = `<div class="av-ico">🔔</div><h2>Activa las notificaciones</h2><p>Antes de empezar, activa las notificaciones. Solo avisan de lo importante: recomendaciones, préstamos, buzón y novedades.</p>`;

  /** Solo se sale de aquí con las notificaciones permitidas. */
  async function ensurePush() {
    let deniedTries = 0;
    for (;;) {
      if (!pushSupported()) {
        if (isIOS() && !isStandalone()) {
          await gateChoice(`<div class="av-ico">📲</div><h2>Instala ${APP} para entrar</h2><p>En iPhone y iPad las notificaciones solo funcionan con la app en la pantalla de inicio.</p>${installSteps()}`, [{ label: 'Ya la he instalado', value: 'retry' }]);
          continue;
        }
        await gateChoice(`<div class="av-ico">🔕</div><h2>Este navegador no admite notificaciones</h2><p>Abre ${APP} con Chrome, Edge, Firefox o Safari (actualizados) para poder entrar.</p>`, [{ label: 'Reintentar', value: 'retry' }]);
        continue;
      }
      const perm = Notification.permission;
      if (perm === 'granted') {
        try { await subscribeAndRegister(); } catch (e) {
          if (e?.name === 'NotAllowedError' && st.reg && st.vapid) {
            // Safari pide que la suscripción vaya justo después de un toque.
            const r = await gateChoice('<div class="av-ico">🔔</div><h2>Un último paso</h2><p>Pulsa para terminar de activar las notificaciones en este dispositivo.</p>', [{ label: '🔔 Terminar de activar', value: 'sub', press: () => st.reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(st.vapid) }) }]);
            try { await register(await r.pressed); return; } catch (e2) { st.pushError = e2?.message || String(e2); }
          }
          // Problema técnico (sin conexión, falta la función…): se entra y se reintenta al volver.
          st.pushState = 'error';
          st.pushError = st.pushError || e?.message || String(e);
          console.warn('[Avisos]', st.pushError);
        }
        return;
      }
      if (perm === 'default') {
        await prepare();
        const r = await gateChoice(INTRO, [{ label: '🔔 Activar notificaciones', value: 'ask', press: () => askAndSubscribe() }]);
        try {
          const sub = await r.pressed;
          if (sub) { await register(sub); return; }
        } catch (e) { console.warn('[Avisos]', e?.message || e); }
        continue;
      }
      // Denegadas
      await gateChoice(`<div class="av-ico">🔕</div><h2>Las notificaciones están desactivadas</h2><p>Sin notificaciones no se puede entrar. Actívalas así:</p>${deniedSteps()}`, [{ label: 'Ya las he activado', value: 'retry' }], deniedTries ? 'Siguen desactivadas. Revisa los ajustes y vuelve a probar.' : '');
      deniedTries += 1;
    }
  }
  /** Pide permiso y, si se concede, se suscribe enseguida (todo dentro del mismo toque). */
  function askAndSubscribe() {
    const ask = Notification.requestPermission ? Notification.requestPermission() : Promise.resolve(Notification.permission);
    return Promise.resolve(ask).then((perm) => {
      if (perm !== 'granted') return null;
      if (!st.reg || !st.vapid) return null;   // se terminará en el siguiente paso
      return st.reg.pushManager.getSubscription().then((old) => old || st.reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(st.vapid) }));
    });
  }

  /* ---------- Campana de la cabecera ---------- */
  function mountBell() {
    const header = $('header.top');
    if (!header || header.querySelector(':scope > .av-bell')) return;
    injectStyles();
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'av-bell';
    b.addEventListener('click', (e) => { e.stopPropagation(); toggleMenu(b); });
    header.appendChild(b);
    paintBell();
  }
  function paintBell() {
    const b = $('.av-bell');
    if (!b) return;
    b.innerHTML = `🔔<span class="av-dot ${st.pushState === 'ok' ? '' : 'warn'}" aria-hidden="true"></span>`;
    b.setAttribute('aria-label', st.pushState === 'ok' ? 'Notificaciones activadas' : 'Notificaciones con problemas');
  }
  function statusText() {
    if (st.pushState === 'ok') return { t: '🔔 Notificaciones activadas en este dispositivo.', warn: false };
    if (st.pushState === 'error') return { t: `⚠️ Notificaciones sin registrar: ${st.pushError}`, warn: true };
    return { t: 'Comprobando las notificaciones…', warn: false };
  }
  function toggleMenu(anchor) {
    injectStyles();
    let m = $('#avMenu');
    if (m && !m.hidden) { closeMenu(); return; }
    if (!m) {
      m = document.createElement('div');
      m.id = 'avMenu';
      m.setAttribute('role', 'menu');
      document.body.appendChild(m);
      m.addEventListener('click', onMenu);
      document.addEventListener('click', (e) => { if (!e.target.closest('#avMenu, .av-bell')) closeMenu(); });
      document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeMenu(); });
    }
    const s = statusText();
    m.innerHTML = `<p class="av-status ${s.warn ? 'warn' : ''}" id="avStatus">${esc(s.t)}</p>
      ${st.pushState !== 'ok' ? '<button type="button" class="av-item" role="menuitem" data-av-act="retry">🔄 Volver a activar</button>' : '<button type="button" class="av-item" role="menuitem" data-av-act="test">🔔 Probar una notificación</button>'}`;
    m.hidden = false;
    const r = anchor.getBoundingClientRect();
    m.style.top = `${Math.round(r.bottom + 8)}px`;
    m.style.right = `${Math.max(12, Math.round(window.innerWidth - r.right))}px`;
    setTimeout(() => m.querySelector('button')?.focus(), 30);
  }
  function closeMenu() { const m = $('#avMenu'); if (m) m.hidden = true; }
  async function onMenu(e) {
    const b = e.target.closest('[data-av-act]');
    if (!b) return;
    const status = $('#avStatus');
    if (b.dataset.avAct === 'retry') {
      closeMenu();
      await ensurePush();
      closeGate();
      paintBell();
      return;
    }
    status.textContent = 'Enviando una notificación de prueba…';
    try {
      const reg = await swReady(4000);
      const sub = await reg.pushManager.getSubscription();
      const r = await rpc('ml_push_test', { p_endpoint: sub?.endpoint || '' });
      status.textContent = r?.ok ? '✅ Enviada. Debería llegarte en unos segundos.' : `⚠️ ${r?.message || 'No se pudo enviar.'}`;
    } catch (err) { status.textContent = `⚠️ ${err.message}`; }
  }

  /* ---------- Arranque ---------- */
  async function start() {
    mountBell();
    await ensurePush();
    closeGate();
    paintBell();
    readyResolve();
  }

  // Al volver a la app (por ejemplo, tras activar las notificaciones en Ajustes) se comprueba otra vez.
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'visible') return;
    if (pushSupported() && Notification.permission !== 'granted') { ensurePush().then(() => { closeGate(); paintBell(); }); return; }
    if (st.pushState === 'error' && pushSupported()) subscribeAndRegister().catch(() => {});
  });

  // El navegador renovó la suscripción: se registra otra vez.
  if ('serviceWorker' in navigator) navigator.serviceWorker.addEventListener?.('message', (e) => {
    if (e.data?.type === 'ml-push-renew' && Notification.permission === 'granted') subscribeAndRegister().catch(() => {});
  });

  window.MisAvisos = { ready: () => ready, _state: st };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
