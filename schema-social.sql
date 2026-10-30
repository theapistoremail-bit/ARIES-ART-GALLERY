-- schema-social.sql
-- Ejecutar DESPUÉS de schema-pagos.sql y schema-galeria.sql. Se puede correr varias veces sin errores.

-- 1) Perfiles: columnas y permisos (todos los miembros ven perfiles; solo tú editas el tuyo)
alter table public.perfiles
  add column if not exists nombre text,
  add column if not exists bio text,
  add column if not exists avatar_url text;
alter table public.perfiles enable row level security;
drop policy if exists "perfil_ver" on public.perfiles;
drop policy if exists "perfil_insertar" on public.perfiles;
drop policy if exists "perfil_actualizar" on public.perfiles;
create policy "perfil_ver" on public.perfiles for select to authenticated using (true);
create policy "perfil_insertar" on public.perfiles for insert to authenticated with check (auth.uid() = id);
create policy "perfil_actualizar" on public.perfiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

-- 2) Obras (ficha técnica + precio). El 10% de la galería lo calcula la base de datos, no el navegador.
create table if not exists public.obras (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  titulo text not null check (char_length(titulo) <= 120),
  tecnica text check (char_length(tecnica) <= 120),
  medidas text check (char_length(medidas) <= 60),
  precio_base numeric(10,2) not null check (precio_base >= 0),
  precio_final numeric(10,2) generated always as (round(precio_base * 1.10, 2)) stored,
  imagen_path text not null,
  created_at timestamptz default now()
);
alter table public.obras enable row level security;
drop policy if exists "obras_ver" on public.obras;
drop policy if exists "obras_publicar" on public.obras;
drop policy if exists "obras_borrar" on public.obras;
create policy "obras_ver" on public.obras for select to authenticated using (true);
-- Solo con plan activo se puede publicar
create policy "obras_publicar" on public.obras for insert to authenticated
  with check (user_id = auth.uid() and exists
    (select 1 from public.suscripciones s where s.user_id = auth.uid() and s.estado = 'ACTIVE'));
create policy "obras_borrar" on public.obras for delete to authenticated using (user_id = auth.uid());

-- 3) Seguidores
create table if not exists public.seguidores (
  seguidor_id uuid not null references auth.users(id) on delete cascade,
  seguido_id uuid not null references auth.users(id) on delete cascade,
  primary key (seguidor_id, seguido_id),
  check (seguidor_id <> seguido_id)
);
alter table public.seguidores enable row level security;
drop policy if exists "seg_ver" on public.seguidores;
drop policy if exists "seg_crear" on public.seguidores;
drop policy if exists "seg_borrar" on public.seguidores;
create policy "seg_ver" on public.seguidores for select to authenticated using (seguidor_id = auth.uid());
create policy "seg_crear" on public.seguidores for insert to authenticated with check (seguidor_id = auth.uid());
create policy "seg_borrar" on public.seguidores for delete to authenticated using (seguidor_id = auth.uid());

-- 4) Feed: obras + artista + rango por plan (3 VIP/Anual, 2 Pro, 1 Creator, 0 gratis).
--    Solo expone el rango, nunca el plan ni el precio base.
create or replace view public.feed_obras as
select o.id, o.user_id, o.titulo, o.tecnica, o.medidas, o.precio_final, o.imagen_path, o.created_at,
       p.nombre, p.avatar_url,
       coalesce((select case
                   when lower(s.plan) ~ 'vip|anual' then 3
                   when lower(s.plan) like '%pro%' then 2
                   when lower(s.plan) like '%creator%' then 1
                   else 0 end
                 from public.suscripciones s
                 where s.user_id = o.user_id and s.estado = 'ACTIVE' limit 1), 0) as rango
from public.obras o
left join public.perfiles p on p.id = o.user_id;
grant select on public.feed_obras to authenticated;

-- 5) Imágenes de las obras (público, hasta 5 MB, cada quien en su carpeta)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('obras', 'obras', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;
drop policy if exists "obras_img_ver" on storage.objects;
drop policy if exists "obras_img_subir" on storage.objects;
drop policy if exists "obras_img_borrar" on storage.objects;
create policy "obras_img_ver" on storage.objects for select using (bucket_id = 'obras');
create policy "obras_img_subir" on storage.objects for insert to authenticated
  with check (bucket_id = 'obras' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "obras_img_borrar" on storage.objects for delete to authenticated
  using (bucket_id = 'obras' and (storage.foldername(name))[1] = auth.uid()::text);
