-- Ejecutar DESPUÉS de schema-pagos.sql y schema-galeria.sql

alter table perfiles add column if not exists avatar_url text;

create table if not exists metricas(
  user_id uuid primary key references auth.users on delete cascade,
  likes int default 0, ventas int default 0, ingresos numeric default 0);
alter table metricas enable row level security;
-- Solo se leen con plan activo y NADIE las escribe desde el navegador (solo el servidor)
create policy "ver con plan" on metricas for select using (auth.uid()=user_id and exists
  (select 1 from suscripciones s where s.user_id=auth.uid() and s.estado='ACTIVE'));

-- AUTO-INICIO: cada cuenta nueva recibe su perfil y métricas al registrarse
create or replace function public.nuevo_usuario() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  insert into perfiles(id,nombre) values (new.id, split_part(new.email,'@',1)) on conflict do nothing;
  insert into metricas(user_id) values (new.id) on conflict do nothing;
  return new;
end $$;
drop trigger if exists al_registrarse on auth.users;
create trigger al_registrarse after insert on auth.users
  for each row execute function public.nuevo_usuario();

-- Cuentas que ya existían
insert into perfiles(id,nombre) select id, split_part(email,'@',1) from auth.users on conflict do nothing;
insert into metricas(user_id) select id from auth.users on conflict do nothing;

-- Fotos de perfil: solo imágenes de hasta 2 MB, cada quien solo en su carpeta
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('avatares','avatares',true,2097152,array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;
create policy "avatar ver" on storage.objects for select using (bucket_id='avatares');
create policy "avatar subir propio" on storage.objects for insert to authenticated
  with check (bucket_id='avatares' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "avatar cambiar propio" on storage.objects for update to authenticated
  using (bucket_id='avatares' and (storage.foldername(name))[1]=auth.uid()::text);
