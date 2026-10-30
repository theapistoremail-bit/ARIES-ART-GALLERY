-- schema-social-limites.sql
-- Ejecutar DESPUÉS de schema-social.sql y schema-social-ig.sql. Se puede correr varias veces.
-- Publicar en Social es gratis, con límite mensual. Con plan activo no hay límite de obras.

-- Límites (para cambiarlos, edita el número y vuelve a ejecutar solo estas dos funciones)
create or replace function public.limite_obras_gratis() returns int language sql immutable as $$ select 3 $$;
create or replace function public.limite_estudio_mes() returns int language sql immutable as $$ select 20 $$;

-- Dos tipos de publicación: 'obra' (ficha técnica y precio) y 'estudio' (sin obra terminada, sin precio)
alter table public.obras add column if not exists tipo text not null default 'obra' check (tipo in ('obra','estudio'));
alter table public.obras alter column precio_base drop not null;
alter table public.obras drop constraint if exists obras_tipo_precio;
alter table public.obras add constraint obras_tipo_precio
  check ((tipo = 'obra' and precio_base is not null) or (tipo = 'estudio' and precio_base is null));

-- Quién puede publicar: cualquier miembro, dentro de su límite del mes
drop policy if exists "obras_publicar" on public.obras;
create policy "obras_publicar" on public.obras for insert to authenticated
with check (
  user_id = auth.uid()
  and (
    (tipo = 'obra' and (
      exists (select 1 from public.suscripciones s where s.user_id = auth.uid() and s.estado = 'ACTIVE')
      or (select count(*) from public.obras o
          where o.user_id = auth.uid() and o.tipo = 'obra'
            and o.created_at >= date_trunc('month', now())) < public.limite_obras_gratis()))
    or
    (tipo = 'estudio' and (
      select count(*) from public.obras o
      where o.user_id = auth.uid() and o.tipo = 'estudio'
        and o.created_at >= date_trunc('month', now())) < public.limite_estudio_mes())
  )
);

-- Feed con el tipo de publicación (columna nueva al final)
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
       (select count(*) from public.obra_likes l where l.obra_id = o.id) as likes,
       o.tipo
from public.obras o
left join public.perfiles p on p.id = o.user_id;
grant select on public.feed_obras to authenticated;

-- Cuánto lleva publicado quien tiene la sesión abierta este mes
create or replace view public.mi_cupo as
select
  (select count(*) from public.obras o where o.user_id = auth.uid() and o.tipo = 'obra'
     and o.created_at >= date_trunc('month', now())) as obras_mes,
  (select count(*) from public.obras o where o.user_id = auth.uid() and o.tipo = 'estudio'
     and o.created_at >= date_trunc('month', now())) as estudio_mes,
  exists (select 1 from public.suscripciones s where s.user_id = auth.uid() and s.estado = 'ACTIVE') as con_plan,
  public.limite_obras_gratis() as limite_obras,
  public.limite_estudio_mes() as limite_estudio;
grant select on public.mi_cupo to authenticated;
