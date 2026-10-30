-- schema-social-ig.sql
-- Ejecutar DESPUÉS de schema-social.sql. Se puede correr varias veces sin errores.

-- Likes de obras
create table if not exists public.obra_likes (
  obra_id uuid not null references public.obras(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key (obra_id, user_id)
);
alter table public.obra_likes enable row level security;
drop policy if exists "like_ver" on public.obra_likes;
drop policy if exists "like_dar" on public.obra_likes;
drop policy if exists "like_quitar" on public.obra_likes;
create policy "like_ver" on public.obra_likes for select to authenticated using (user_id = auth.uid());
create policy "like_dar" on public.obra_likes for insert to authenticated with check (user_id = auth.uid());
create policy "like_quitar" on public.obra_likes for delete to authenticated using (user_id = auth.uid());

-- Feed con total de likes (columna nueva al final)
create or replace view public.feed_obras as
select o.id, o.user_id, o.titulo, o.tecnica, o.medidas, o.precio_final, o.imagen_path, o.created_at,
       p.nombre, p.avatar_url,
       coalesce((select case
                   when lower(s.plan) ~ 'vip|anual' then 3
                   when lower(s.plan) like '%pro%' then 2
                   when lower(s.plan) like '%creator%' then 1
                   else 0 end
                 from public.suscripciones s
                 where s.user_id = o.user_id and s.estado = 'ACTIVE' limit 1), 0) as rango,
       (select count(*) from public.obra_likes l where l.obra_id = o.id) as likes
from public.obras o
left join public.perfiles p on p.id = o.user_id;
grant select on public.feed_obras to authenticated;

-- Contadores de cada perfil: publicaciones, seguidores y siguiendo
create or replace view public.perfil_conteos as
select p.id,
       (select count(*) from public.seguidores s where s.seguido_id = p.id) as seguidores,
       (select count(*) from public.seguidores s where s.seguidor_id = p.id) as siguiendo,
       (select count(*) from public.obras o where o.user_id = p.id) as publicaciones
from public.perfiles p;
grant select on public.perfil_conteos to authenticated;
