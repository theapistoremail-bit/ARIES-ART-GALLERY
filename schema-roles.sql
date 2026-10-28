-- 1) Columna de rol en la tabla de perfiles
alter table public.perfiles
  add column if not exists rol text not null default 'comprador'
  check (rol in ('artista', 'comprador'));

-- 2) Trigger: crea el perfil automáticamente al registrarse
--    (funciona aunque el correo aún no esté confirmado)
create or replace function public.crear_perfil_nuevo()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.perfiles (id, nombre, plan, rol)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nombre', ''),
    'free',
    case when new.raw_user_meta_data->>'rol' = 'artista'
         then 'artista' else 'comprador' end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists al_crear_usuario on auth.users;
create trigger al_crear_usuario
  after insert on auth.users
  for each row execute function public.crear_perfil_nuevo();
