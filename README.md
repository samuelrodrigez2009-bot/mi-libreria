# 📚 Mi librería

La biblioteca personal de Bea: libros, lista de deseos, lecturas día a día, valoraciones,
pendientes, recomendaciones, préstamos y buzón de sugerencias. PWA alojada en GitHub Pages
con los datos en Supabase.

## Archivos

| Archivo | Qué es |
|---|---|
| `index.html`, `app.js`, `styles.css` | La aplicación |
| `avisos.js` | Notificaciones push (obligatorias para entrar) y la campana de la cabecera |
| `buzon.js` | Buzón de sugerencias (botón del menú lateral) |
| `supabase-config.js` | Dirección del proyecto de Supabase y clave pública |
| `service-worker.js`, `manifest.webmanifest`, `icons/` | Instalación como app y funcionamiento sin conexión |
| `scanner-core.js` | Lector de códigos de barras (ISBN) |
| `*.gif` | Pantallas de carga (Tom, Hermione, las ovejas y la librería) |
| `sql/instalar.sql` | Crea toda la base de datos, vacía |
| `supabase/functions/ml-push/index.ts` | Función que envía las notificaciones |
| `supabase/functions/agapea/index.ts` | Búsqueda de libros en Agapea (la misma que ya usa Hogar) |

## Instalación paso a paso

### 1. Base de datos (Supabase)

El plan gratuito de Supabase solo permite **2 proyectos activos** y ya tienes 2 (discoteca y
biblioteca/despensa). Por eso Mi librería se instala **dentro del proyecto de la biblioteca de
Hogar** (`ravnuggmkypkrcfgfeip`), pero en tablas propias con el prefijo `ml_`: está vacía y
completamente separada de Hogar, igual que la despensa usa su propio esquema.

1. Entra en <https://supabase.com/dashboard> y abre el proyecto de la biblioteca de Hogar.
2. **SQL Editor → New query**. Pega todo `sql/instalar.sql` y pulsa **Run**.
   Al final debe salir una tabla con `libros 0 · deseos 0 · prestamos 0 · sugerencias 0`.
3. **Edge Functions → Deploy a new function → Via Editor**:
   - Nombre: `ml-push` (exactamente así).
   - Borra el código de ejemplo y pega todo `supabase/functions/ml-push/index.ts`.
   - Pulsa **Deploy**.
   - Abre la función → **Details** (o Settings) → desactiva **Verify JWT** / «Enforce JWT verification» → Save.
     (La base de datos la llama con su propia clave secreta, no con un usuario.)
4. Comprueba la función: abre en el navegador
   `https://ravnuggmkypkrcfgfeip.supabase.co/functions/v1/ml-push?action=key`
   Debe responder `{"ok":true,"publicKey":"B…"}`. La primera vez crea las claves de las notificaciones.
5. La función `agapea` ya está desplegada en ese proyecto (la usa Hogar): no hay que hacer nada.

> **¿Prefieres un proyecto nuevo?** Tendrías que pausar uno de los dos actuales o pasar a Pro.
> Si lo haces: activa `pg_net` y `pg_cron` en Database → Extensions, cambia la línea marcada con 👉
> en `sql/instalar.sql` por la dirección del proyecto nuevo, ejecútalo, despliega `ml-push` **y**
> `agapea` (ambas sin Verify JWT) y pon la Project URL y la publishable key nuevas en `supabase-config.js`.

### 2. Repositorio y web (GitHub Pages)

1. Entra en GitHub con la **otra cuenta** y pulsa **New repository**.
   - Nombre: `mi-libreria` · **Public** · sin README → **Create repository**.
2. En el repositorio vacío: **uploading an existing file** (o Add file → Upload files).
   Arrastra **todo el contenido** de esta carpeta (los archivos y las carpetas `icons`, `sql` y `supabase`,
   no la carpeta que los contiene) → **Commit changes**.
3. **Settings → Pages** → Source: **Deploy from a branch** → Branch: `main` / `(root)` → **Save**.
4. Espera 1–2 minutos. La web queda en `https://NOMBRE-DE-LA-CUENTA.github.io/mi-libreria/`.

### 3. Instalarla en el móvil de Bea

- **Android (Chrome):** abre la dirección → menú ⋮ → **Instalar aplicación** (o «Añadir a pantalla de inicio») → ábrela desde el icono → **Activar notificaciones** → Permitir.
- **iPhone (Safari):** abre la dirección → **Compartir** → **Añadir a pantalla de inicio** → ábrela desde el icono → **Activar notificaciones** → Permitir.
  En iPhone las notificaciones solo funcionan con la app instalada, por eso pide instalarla antes.
- Pulsa la 🔔 de arriba a la derecha → **Probar una notificación** para comprobar que llegan.

Instálala también en tu móvil si quieres recibir las sugerencias del buzón: los avisos llegan a
**todos** los dispositivos que hayan entrado alguna vez.

## Notificaciones

| Cuándo | Aviso |
|---|---|
| Alguien apunta una recomendación | 💌 *Adrián te recomienda un libro* |
| Un préstamo cumple 30 días (y cada 30 días más) | ⏰ *«Título» lleva 30 días prestado* (se revisa cada día a las 10:00) |
| Nueva sugerencia en el buzón | 📮 *Nueva sugerencia en el buzón* |
| Aceptas una sugerencia (con la contraseña) | 🎉 *Novedad en Mi librería* |
| Quieres anunciar una actualización a mano | En el SQL Editor: `select public.ml_anunciar('🎉 Novedad en Mi librería', 'Lo que has cambiado');` |

## Claves

- **Borrar un libro:** la misma de la biblioteca de Hogar.
- **Aceptar, rechazar o borrar sugerencias resueltas del buzón:** la misma contraseña que el buzón de Hogar.

## Actualizar la app más adelante

Sube los archivos cambiados a GitHub y **cambia `CACHE` en `service-worker.js`** (por ejemplo,
`mi-libreria-v2-…`). Al abrir la app saldrá «Hay una versión nueva · Actualizar».
