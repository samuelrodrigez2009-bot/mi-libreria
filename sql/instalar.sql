-- =====================================================================
-- MI LIBRERÍA · INSTALACIÓN COMPLETA DE LA BASE DE DATOS (Supabase)
-- ---------------------------------------------------------------------
-- · Crea TODO desde cero y VACÍO: libros, lista de deseos, valoraciones, lecturas,
--   pendientes, recomendaciones, préstamos, nombres guardados, buzón de sugerencias,
--   portadas (Storage) y notificaciones push.
-- · Todas las tablas, funciones y trabajos llevan el prefijo ml_ (Mi librería). Así se puede
--   instalar en el proyecto que ya usas para Hogar sin mezclar nada: Hogar no ve estas tablas
--   y Mi librería no ve las de Hogar.
-- · Es seguro ejecutarlo varias veces: no borra datos.
-- · Se ejecuta entero en Supabase → SQL Editor → New query → pegar → Run.
--
-- ⚠️ ÚNICO DATO A REVISAR: la dirección del proyecto (la línea marcada con 👉 más abajo).
--    Por defecto es la de tu proyecto actual de Hogar. Si instalas en un proyecto NUEVO,
--    cámbiala por su Project URL (Project Settings → API).
-- =====================================================================

-- Extensiones (si alguna no se puede activar aquí, actívala en Database → Extensions y repite).
create extension if not exists pgcrypto with schema extensions;
do $$ begin
  begin create extension if not exists pg_net with schema extensions; exception when others then raise notice 'pg_net no disponible: %', sqlerrm; end;
  begin create extension if not exists pg_cron; exception when others then raise notice 'pg_cron no disponible: %', sqlerrm; end;
end $$;

-- =====================================================================
-- 1. TABLAS DE LA BIBLIOTECA
-- =====================================================================
create table if not exists public.ml_books (
  id                      uuid primary key default gen_random_uuid(),
  title                   text not null check (char_length(btrim(title)) between 1 and 500),
  subtitle                text,
  authors                 text[] not null default '{}',
  isbn13                  text,
  isbn10                  text,
  publisher               text,
  published_year          int check (published_year is null or published_year between 0 and 2100),
  published_date          text,
  edition                 text,
  pages                   int check (pages is null or pages between 0 and 100000),
  genres                  text[] not null default '{}',
  language                text,
  cover_url               text,
  cover_path              text,
  openlibrary_work_id     text,
  openlibrary_edition_id  text,
  google_books_id         text,
  source                  text,
  owners                  text[] not null default '{}',
  location                text,
  physical_format         text,
  notes                   text,
  synopsis                text check (synopsis is null or char_length(synopsis) <= 8000),
  in_collection           boolean not null default true,   -- false = leído fuera (biblioteca pública, digital…)
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);
create index if not exists ml_books_isbn13_idx on public.ml_books (isbn13);
create index if not exists ml_books_isbn10_idx on public.ml_books (isbn10);

create table if not exists public.ml_wishlist (
  id                      uuid primary key default gen_random_uuid(),
  person                  text not null check (char_length(btrim(person)) between 1 and 60),
  title                   text not null,
  subtitle                text,
  authors                 text[] not null default '{}',
  isbn13                  text,
  isbn10                  text,
  publisher               text,
  published_year          int,
  published_date          text,
  edition                 text,
  pages                   int,
  genres                  text[] not null default '{}',
  language                text,
  cover_url               text,
  openlibrary_work_id     text,
  openlibrary_edition_id  text,
  google_books_id         text,
  source                  text,
  synopsis                text,
  created_at              timestamptz not null default now()
);

create table if not exists public.ml_ratings (
  id          uuid primary key default gen_random_uuid(),
  book_id     uuid not null references public.ml_books(id) on delete cascade,
  person      text not null check (char_length(btrim(person)) between 1 and 60),
  rating      numeric(2,1) not null check (rating >= 0 and rating <= 5 and rating * 2 = floor(rating * 2)),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (book_id, person)
);

create table if not exists public.ml_reading_journeys (
  id          uuid primary key default gen_random_uuid(),
  book_id     uuid not null references public.ml_books(id) on delete cascade,
  person      text not null check (char_length(btrim(person)) between 1 and 60),
  status      text not null default 'reading' check (status in ('reading', 'finished')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists ml_reading_journeys_book_idx on public.ml_reading_journeys (book_id, person);

create table if not exists public.ml_reading_sessions (
  id          uuid primary key default gen_random_uuid(),
  journey_id  uuid not null references public.ml_reading_journeys(id) on delete cascade,
  book_id     uuid not null references public.ml_books(id) on delete cascade,
  person      text not null check (char_length(btrim(person)) between 1 and 60),
  read_on     date not null,
  page        int not null check (page >= 0),
  finished    boolean not null default false,
  notes       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists ml_reading_sessions_journey_idx on public.ml_reading_sessions (journey_id);
create index if not exists ml_reading_sessions_day_idx on public.ml_reading_sessions (person, read_on);

create table if not exists public.ml_reading_pending (
  id          uuid primary key default gen_random_uuid(),
  book_id     uuid not null references public.ml_books(id) on delete cascade,
  person      text not null check (char_length(btrim(person)) between 1 and 60),
  created_at  timestamptz not null default now(),
  unique (book_id, person)
);

create table if not exists public.ml_recommendations (
  id              uuid primary key default gen_random_uuid(),
  book_id         uuid not null references public.ml_books(id) on delete cascade,
  person          text not null check (char_length(btrim(person)) between 1 and 60),
  recommended_by  text not null check (char_length(btrim(recommended_by)) between 1 and 60),
  note            text check (note is null or char_length(note) <= 500),
  created_at      timestamptz not null default now(),
  unique (book_id, person)
);

create table if not exists public.ml_loans (
  id                uuid primary key default gen_random_uuid(),
  book_id           uuid not null unique references public.ml_books(id) on delete cascade,
  lender            text check (lender is null or char_length(lender) <= 200),
  borrower          text not null check (char_length(btrim(borrower)) between 1 and 60),
  lent_on           date not null default current_date,
  last_reminder_at  timestamptz,
  created_at        timestamptz not null default now()
);

create table if not exists public.ml_people (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(btrim(name)) between 1 and 60),
  name_key    text not null unique check (char_length(name_key) between 1 and 60),
  created_at  timestamptz not null default now()
);

-- updated_at automático
create or replace function public.ml_touch() returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end $$;
do $$
declare t text;
begin
  foreach t in array array['ml_books', 'ml_ratings', 'ml_reading_journeys', 'ml_reading_sessions'] loop
    execute format('drop trigger if exists ml_touch on public.%I', t);
    execute format('create trigger ml_touch before update on public.%I for each row execute function public.ml_touch()', t);
  end loop;
end $$;

-- Ciclos de lectura: el estado sigue a sus sesiones; un ciclo sin sesiones se borra.
create or replace function public.ml_journey_sync() returns trigger language plpgsql security definer set search_path = '' as $$
declare j uuid := coalesce(new.journey_id, old.journey_id);
begin
  if tg_op = 'UPDATE' and old.journey_id is distinct from new.journey_id then
    perform public.ml_journey_refresh(old.journey_id);
  end if;
  perform public.ml_journey_refresh(j);
  return null;
end $$;
create or replace function public.ml_journey_refresh(p_id uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_id is null then return; end if;
  if not exists (select 1 from public.ml_reading_sessions where journey_id = p_id) then
    delete from public.ml_reading_journeys where id = p_id
      and created_at < now() - interval '2 seconds';            -- deja tiempo a la primera sesión
    return;
  end if;
  update public.ml_reading_journeys
     set status = case when exists (select 1 from public.ml_reading_sessions where journey_id = p_id and finished) then 'finished' else 'reading' end
   where id = p_id;
end $$;
drop trigger if exists ml_journey_sync on public.ml_reading_sessions;
create trigger ml_journey_sync after insert or update or delete on public.ml_reading_sessions
  for each row execute function public.ml_journey_sync();
revoke all on function public.ml_journey_refresh(uuid) from public, anon, authenticated;

-- Acceso desde la app (publishable key, sin login), igual que en Hogar.
do $$
declare t text;
begin
  foreach t in array array['ml_books', 'ml_wishlist', 'ml_ratings', 'ml_reading_journeys', 'ml_reading_sessions',
                           'ml_reading_pending', 'ml_recommendations', 'ml_loans', 'ml_people'] loop
    execute format('alter table public.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = t || '_app') then
      execute format('create policy %I on public.%I for all to anon, authenticated using (true) with check (true)', t || '_app', t);
    end if;
    execute format('grant select, insert, update, delete on public.%I to anon, authenticated', t);
    execute format('alter table public.%I replica identity full', t);
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
       and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- =====================================================================
-- 2. PORTADAS (Storage: bucket público «ml-portadas»)
-- =====================================================================
insert into storage.buckets (id, name, public) values ('ml-portadas', 'ml-portadas', true)
on conflict (id) do update set public = true;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'ml_portadas_leer') then
    create policy ml_portadas_leer on storage.objects for select to anon, authenticated using (bucket_id = 'ml-portadas');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'ml_portadas_subir') then
    create policy ml_portadas_subir on storage.objects for insert to anon, authenticated with check (bucket_id = 'ml-portadas');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'ml_portadas_borrar') then
    create policy ml_portadas_borrar on storage.objects for delete to anon, authenticated using (bucket_id = 'ml-portadas');
  end if;
end $$;

-- =====================================================================
-- 3. BUZÓN DE SUGERENCIAS (misma contraseña que el buzón de Hogar)
-- =====================================================================
create table if not exists public.ml_suggestions (
  id           uuid primary key default gen_random_uuid(),
  body         text not null check (char_length(btrim(body)) between 3 and 2000),
  status       text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  created_at   timestamptz not null default now(),
  resolved_at  timestamptz
);
create index if not exists ml_suggestions_status_idx on public.ml_suggestions (status, created_at desc);

-- Datos privados (huella de la contraseña, claves de las notificaciones) e intentos fallidos:
-- RLS activo y sin políticas → la app no puede leerlos.
create table if not exists public.ml_private (key text primary key, value text not null);
create table if not exists public.ml_pin_failures (id bigint generated always as identity primary key, at timestamptz not null default now());

insert into public.ml_private (key, value) values
  ('buzon_pin_salt', '543f073fef0e45ebf05f162a82444cb6'),
  ('buzon_pin_sha256', '1188dd25ef879c485dd3a8af97e15959a4f5c2adabf331016d414244e41c76a3')
on conflict (key) do nothing;

alter table public.ml_suggestions enable row level security;
alter table public.ml_private enable row level security;
alter table public.ml_pin_failures enable row level security;
revoke all on public.ml_suggestions, public.ml_private, public.ml_pin_failures from anon, authenticated;
grant select on public.ml_suggestions to anon, authenticated;
drop policy if exists ml_suggestions_leer on public.ml_suggestions;
create policy ml_suggestions_leer on public.ml_suggestions for select to anon, authenticated using (true);

create or replace function public.ml_check_pin(p_pin text)
returns text language plpgsql security definer set search_path = '' as $$
declare salt text; hash text;
begin
  delete from public.ml_pin_failures where at < now() - interval '1 day';
  if (select count(*) from public.ml_pin_failures where at > now() - interval '10 minutes') >= 8 then return 'demasiados_intentos'; end if;
  select value into salt from public.ml_private where key = 'buzon_pin_salt';
  select value into hash from public.ml_private where key = 'buzon_pin_sha256';
  if salt is null or hash is null or encode(sha256(convert_to(salt || coalesce(p_pin, ''), 'UTF8')), 'hex') <> hash then
    insert into public.ml_pin_failures default values;
    return 'contrasena_incorrecta';
  end if;
  return null;
end $$;

create or replace function public.ml_buzon_error(p_code text)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object('ok', false, 'code', p_code, 'message', case p_code
    when 'contrasena_incorrecta' then 'La contraseña no es correcta.'
    when 'demasiados_intentos' then 'Demasiados intentos fallidos. Espera unos minutos y vuelve a probar.'
    when 'sugerencia_corta' then 'Escribe un poco más (al menos 3 letras).'
    when 'sugerencia_larga' then 'La sugerencia no puede pasar de 2000 caracteres.'
    when 'demasiadas_sugerencias' then 'Se han enviado muchas sugerencias seguidas. Prueba dentro de un rato.'
    when 'ya_resuelta' then 'Esa sugerencia ya no está pendiente.'
    when 'no_existe' then 'Esa sugerencia ya no existe.'
    else 'No se ha podido completar.' end)
$$;

create or replace function public.ml_suggestion_add(p_body text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare txt text := btrim(coalesce(p_body, '')); r public.ml_suggestions;
begin
  if char_length(txt) < 3 then return public.ml_buzon_error('sugerencia_corta'); end if;
  if char_length(txt) > 2000 then return public.ml_buzon_error('sugerencia_larga'); end if;
  if (select count(*) from public.ml_suggestions where created_at > now() - interval '1 hour') >= 40 then return public.ml_buzon_error('demasiadas_sugerencias'); end if;
  insert into public.ml_suggestions (body) values (txt) returning * into r;
  return jsonb_build_object('ok', true, 'row', to_jsonb(r));
end $$;

create or replace function public.ml_suggestion_resolve(p_id uuid, p_status text, p_pin text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.ml_suggestions; err text;
begin
  if p_status not in ('accepted', 'rejected') then return public.ml_buzon_error('estado_no_valido'); end if;
  err := public.ml_check_pin(p_pin);
  if err is not null then return public.ml_buzon_error(err); end if;
  update public.ml_suggestions set status = p_status, resolved_at = now() where id = p_id and status = 'pending' returning * into r;
  if r.id is null then return public.ml_buzon_error('ya_resuelta'); end if;
  return jsonb_build_object('ok', true, 'row', to_jsonb(r));
end $$;

create or replace function public.ml_suggestion_delete(p_id uuid, p_pin text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare st text; err text;
begin
  select status into st from public.ml_suggestions where id = p_id for update;
  if st is null then return public.ml_buzon_error('no_existe'); end if;
  if st <> 'pending' then
    err := public.ml_check_pin(p_pin);
    if err is not null then return public.ml_buzon_error(err); end if;
  end if;
  delete from public.ml_suggestions where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.ml_check_pin(text) from public, anon, authenticated;
revoke all on function public.ml_buzon_error(text) from public, anon, authenticated;
revoke all on function public.ml_suggestion_add(text), public.ml_suggestion_resolve(uuid, text, text), public.ml_suggestion_delete(uuid, text) from public;
grant execute on function public.ml_suggestion_add(text), public.ml_suggestion_resolve(uuid, text, text), public.ml_suggestion_delete(uuid, text) to anon, authenticated;

-- =====================================================================
-- 4. NOTIFICACIONES PUSH (todas llegan a TODOS los dispositivos registrados)
-- =====================================================================
create table if not exists public.ml_push_subs (
  endpoint    text primary key check (char_length(endpoint) between 20 and 2000 and endpoint like 'https://%'),
  p256dh      text not null check (char_length(p256dh) between 40 and 200),
  auth        text not null check (char_length(auth) between 10 and 100),
  user_agent  text check (user_agent is null or char_length(user_agent) <= 400),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  last_ok_at  timestamptz,
  fail_count  int not null default 0
);
create table if not exists public.ml_push_outbox (
  id          bigint generated always as identity primary key,
  endpoint    text,                         -- solo para la prueba de un dispositivo; null = todos
  title       text not null,
  body        text not null default '',
  url         text not null default 'index.html',
  tag         text,
  created_at  timestamptz not null default now(),
  sent_at     timestamptz,
  attempts    int not null default 0,
  last_error  text
);
create index if not exists ml_push_outbox_pending_idx on public.ml_push_outbox (id) where sent_at is null;

alter table public.ml_push_subs enable row level security;
alter table public.ml_push_outbox enable row level security;
revoke all on public.ml_push_subs, public.ml_push_outbox from anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant select, insert, update, delete on public.ml_push_subs, public.ml_push_outbox, public.ml_private to service_role;
  end if;
end $$;

-- Clave que firma las llamadas de la base de datos a la función y dirección de la función.
insert into public.ml_private (key, value)
  values ('push_secret', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
  on conflict (key) do nothing;
insert into public.ml_private (key, value)
  -- 👉 Si instalas en un proyecto NUEVO, cambia aquí la dirección por la suya (…supabase.co/functions/v1/ml-push)
  values ('push_url', 'https://ravnuggmkypkrcfgfeip.supabase.co/functions/v1/ml-push')
  on conflict (key) do update set value = excluded.value;

/** Llama a la función ml-push (una vez por transacción). Nunca hace fallar lo que la dispara. */
create or replace function public.ml_push_kick() returns void language plpgsql security definer set search_path = '' as $$
declare u text; s text;
begin
  if coalesce(current_setting('ml.push_kicked', true), '') = '1' then return; end if;
  perform set_config('ml.push_kicked', '1', true);
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'net' and p.proname = 'http_post') then return; end if;
  select value into u from public.ml_private where key = 'push_url';
  select value into s from public.ml_private where key = 'push_secret';
  if u is null or s is null then return; end if;
  begin
    execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := 15000)'
      using u, jsonb_build_object('action', 'send'), jsonb_build_object('Content-Type', 'application/json', 'x-ml-secret', s);
  exception when others then
    raise warning 'Mi librería: no se pudo llamar a la función de avisos: %', sqlerrm;
  end;
end $$;

/** Apunta una notificación para todos los dispositivos (o solo uno, si p_endpoint). */
create or replace function public.ml_push_queue(p_title text, p_body text, p_url text default 'index.html', p_tag text default null, p_endpoint text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.ml_push_outbox (endpoint, title, body, url, tag)
  values (p_endpoint, left(coalesce(p_title, 'Mi librería'), 120), left(coalesce(p_body, ''), 300), left(coalesce(p_url, 'index.html'), 300), left(p_tag, 80));
  perform public.ml_push_kick();
end $$;

create or replace function public.ml_push_kick_pending() returns void language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.ml_push_outbox where sent_at is null and attempts < 5) then perform public.ml_push_kick(); end if;
end $$;

-- Desde la app (anon)
create or replace function public.ml_push_register(p_endpoint text, p_p256dh text, p_auth text, p_ua text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if p_endpoint is null or p_endpoint not like 'https://%' or char_length(p_endpoint) > 2000 then
    return jsonb_build_object('ok', false, 'message', 'Suscripción no válida.');
  end if;
  insert into public.ml_push_subs (endpoint, p256dh, auth, user_agent)
  values (p_endpoint, p_p256dh, p_auth, left(p_ua, 400))
  on conflict (endpoint) do update set p256dh = excluded.p256dh, auth = excluded.auth,
    user_agent = excluded.user_agent, updated_at = now(), fail_count = 0;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ml_push_unregister(p_endpoint text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin delete from public.ml_push_subs where endpoint = p_endpoint; return jsonb_build_object('ok', true); end $$;

create or replace function public.ml_push_public_key()
returns text language sql stable security definer set search_path = '' as $$
  select value from public.ml_private where key = 'vapid_public'
$$;

create or replace function public.ml_push_test(p_endpoint text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.ml_push_subs where endpoint = p_endpoint) then
    return jsonb_build_object('ok', false, 'message', 'Este dispositivo no está registrado para recibir notificaciones.');
  end if;
  if (select count(*) from public.ml_push_outbox where endpoint = p_endpoint and created_at > now() - interval '10 minutes') >= 5 then
    return jsonb_build_object('ok', false, 'message', 'Ya se han enviado varias pruebas. Espera unos minutos.');
  end if;
  perform public.ml_push_queue('🔔 Notificación de prueba', 'Si ves esto, las notificaciones de Mi librería funcionan en este dispositivo.', 'index.html', 'prueba', p_endpoint);
  return jsonb_build_object('ok', true);
end $$;

-- Para la función ml-push (solo service_role)
create or replace function public.ml_push_config()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'secret', (select value from public.ml_private where key = 'push_secret'),
    'vapid_public', (select value from public.ml_private where key = 'vapid_public'),
    'vapid_private', (select value from public.ml_private where key = 'vapid_private'))
$$;

create or replace function public.ml_push_set_vapid(p_public text, p_private text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  insert into public.ml_private (key, value) values ('vapid_public', p_public) on conflict (key) do nothing;
  insert into public.ml_private (key, value) values ('vapid_private', p_private) on conflict (key) do nothing;
  return public.ml_push_config();
end $$;

/** Reserva hasta p_limit notificaciones pendientes con los dispositivos a los que van. */
create or replace function public.ml_push_claim(p_limit int default 50)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare out jsonb;
begin
  with picked as (
    select o.id from public.ml_push_outbox o
     where o.sent_at is null and o.attempts < 5
     order by o.id limit greatest(1, least(coalesce(p_limit, 50), 200))
     for update skip locked
  ), bumped as (
    update public.ml_push_outbox o set attempts = o.attempts + 1 from picked where o.id = picked.id returning o.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', b.id, 'title', b.title, 'body', b.body, 'url', b.url, 'tag', b.tag,
      'subs', coalesce((select jsonb_agg(jsonb_build_object('endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth))
                          from public.ml_push_subs s
                         where b.endpoint is null or s.endpoint = b.endpoint), '[]'::jsonb)
    ) order by b.id), '[]'::jsonb)
    into out from bumped b;
  return out;
end $$;

create or replace function public.ml_push_done(p_results jsonb, p_gone text[] default '{}', p_ok text[] default '{}')
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.ml_push_outbox o
     set sent_at = case when coalesce((r->>'ok')::boolean, false) then now() else o.sent_at end,
         last_error = case when coalesce((r->>'ok')::boolean, false) then null else left(r->>'error', 300) end
    from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) r
   where o.id = (r->>'id')::bigint;
  delete from public.ml_push_subs where endpoint = any (coalesce(p_gone, '{}'));
  update public.ml_push_subs set last_ok_at = now(), fail_count = 0 where endpoint = any (coalesce(p_ok, '{}'));
  delete from public.ml_push_outbox where sent_at < now() - interval '30 days' or (sent_at is null and created_at < now() - interval '7 days');
end $$;

revoke all on function public.ml_push_kick(), public.ml_push_queue(text, text, text, text, text), public.ml_push_kick_pending(),
  public.ml_push_config(), public.ml_push_set_vapid(text, text), public.ml_push_claim(int), public.ml_push_done(jsonb, text[], text[])
  from public, anon, authenticated;
revoke all on function public.ml_push_register(text, text, text, text), public.ml_push_unregister(text), public.ml_push_public_key(), public.ml_push_test(text) from public;
grant execute on function public.ml_push_register(text, text, text, text), public.ml_push_unregister(text), public.ml_push_public_key(), public.ml_push_test(text) to anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.ml_push_config(), public.ml_push_set_vapid(text, text), public.ml_push_claim(int),
      public.ml_push_done(jsonb, text[], text[]) to service_role;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Qué avisa (un fallo aquí nunca impide guardar)
-- ---------------------------------------------------------------------
-- 💌 Recomendaciones de libros
create or replace function public.ml_av_recommendation() returns trigger language plpgsql security definer set search_path = '' as $$
declare t text;
begin
  begin
    select title into t from public.ml_books where id = new.book_id;
    perform public.ml_push_queue(format('💌 %s te recomienda un libro', new.recommended_by), format('«%s»', coalesce(t, 'Un libro')), 'index.html#pending', 'recomendacion');
  exception when others then raise warning 'Mi librería avisos: %', sqlerrm; end;
  return new;
end $$;
drop trigger if exists ml_av on public.ml_recommendations;
create trigger ml_av after insert on public.ml_recommendations for each row execute function public.ml_av_recommendation();

-- 📮 Sugerencia nueva en el buzón
create or replace function public.ml_av_suggestion_new() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  begin
    perform public.ml_push_queue('📮 Nueva sugerencia en el buzón', left(new.body, 160), 'index.html?abrir=buzon', 'buzon');
  exception when others then raise warning 'Mi librería avisos: %', sqlerrm; end;
  return new;
end $$;
drop trigger if exists ml_av_new on public.ml_suggestions;
create trigger ml_av_new after insert on public.ml_suggestions for each row execute function public.ml_av_suggestion_new();

-- 🎉 Sugerencia aceptada = actualización del programa
create or replace function public.ml_av_suggestion_done() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  begin
    if old.status = 'pending' and new.status = 'accepted' then
      perform public.ml_push_queue('🎉 Novedad en Mi librería', left(new.body, 160), 'index.html', 'novedad');
    end if;
  exception when others then raise warning 'Mi librería avisos: %', sqlerrm; end;
  return new;
end $$;
drop trigger if exists ml_av_done on public.ml_suggestions;
create trigger ml_av_done after update of status on public.ml_suggestions for each row execute function public.ml_av_suggestion_done();

-- ⏰ Recordatorios: cada 30 días que un libro siga prestado
create or replace function public.ml_push_reminders() returns int language plpgsql security definer set search_path = '' as $$
declare r record; days int; n int := 0;
begin
  for r in select l.id, l.borrower, l.lent_on, b.title from public.ml_loans l join public.ml_books b on b.id = l.book_id
            where coalesce(l.last_reminder_at, l.lent_on::timestamptz) <= now() - interval '30 days' for update of l skip locked loop
    days := current_date - r.lent_on;
    perform public.ml_push_queue(format('⏰ «%s» lleva %s días prestado', r.title, days),
      format('Lo tiene %s desde el %s. ¡Que no se te olvide reclamarlo!', r.borrower, to_char(r.lent_on, 'DD/MM/YYYY')), 'index.html#loans', 'recordatorio');
    update public.ml_loans set last_reminder_at = now() where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.ml_push_reminders() from public, anon, authenticated;

-- 📣 Anunciar una actualización a mano (solo desde el SQL Editor):
--    select public.ml_anunciar('🎉 Novedad en Mi librería', 'Ya puedes ordenar los libros por año');
create or replace function public.ml_anunciar(p_title text, p_body text) returns void language plpgsql security definer set search_path = '' as $$
begin perform public.ml_push_queue(p_title, p_body, 'index.html', 'novedad'); end $$;
revoke all on function public.ml_anunciar(text, text) from public, anon, authenticated;

-- Trabajos programados (hora UTC): recordatorios cada día a las 9:00 (10:00 en invierno en España)
-- y reintento de notificaciones pendientes cada 15 minutos.
do $$ begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'cron' and p.proname = 'schedule') then
    perform cron.schedule('ml-recordatorios', '0 9 * * *', 'select public.ml_push_reminders()');
    perform cron.schedule('ml-avisos-reintento', '*/15 * * * *', 'select public.ml_push_kick_pending()');
  else
    raise notice 'pg_cron no está activo: actívalo en Database → Extensions y vuelve a ejecutar este archivo para los recordatorios.';
  end if;
end $$;

notify pgrst, 'reload schema';

-- Comprobación rápida (debe salir 0 en todo: la base de datos empieza vacía)
select (select count(*) from public.ml_books) as libros, (select count(*) from public.ml_wishlist) as deseos,
       (select count(*) from public.ml_loans) as prestamos, (select count(*) from public.ml_suggestions) as sugerencias;
