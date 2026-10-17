-- Ejecuta DESPUÉS de schema.sql y schema-extra.sql (usa la función es_pro())

create table posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  author text,
  canal text not null default 'aries',
  body text check (char_length(body) <= 300),
  media_path text,
  media_type text check (media_type in ('image','video')),
  price numeric(10,2),
  created_at timestamptz default now()
);
create table post_likes (
  post_id uuid references posts(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  primary key (post_id, user_id)
);
create table post_comments (
  id bigint generated always as identity primary key,
  post_id uuid not null references posts(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  author text,
  body text not null check (char_length(body) <= 300),
  created_at timestamptz default now()
);
create table news (
  id bigint generated always as identity primary key,
  title text not null,
  body text,
  created_at timestamptz default now()
);

alter table posts enable row level security;
alter table post_likes enable row level security;
alter table post_comments enable row level security;
alter table news enable row level security;

create policy "posts visibles" on posts for select to authenticated using (true);
-- Cualquier miembro publica; solo owner/pro pueden poner precio
create policy "publicar" on posts for insert to authenticated
  with check (user_id = auth.uid() and (price is null or es_pro()));
create policy "borrar mi post" on posts for delete to authenticated using (user_id = auth.uid());

create policy "likes de posts visibles" on post_likes for select to authenticated using (true);
create policy "dar like a post" on post_likes for insert to authenticated with check (user_id = auth.uid());
create policy "quitar like a post" on post_likes for delete to authenticated using (user_id = auth.uid());

create policy "comentarios de posts visibles" on post_comments for select to authenticated using (true);
create policy "comentar post" on post_comments for insert to authenticated with check (user_id = auth.uid());
create policy "borrar mi comentario de post" on post_comments for delete to authenticated using (user_id = auth.uid());

-- Noticias del carrusel: todos leen, solo owner escribe
create policy "noticias visibles" on news for select to authenticated using (true);
create policy "owner publica noticias" on news for insert to authenticated
  with check ((select role from profiles where id = auth.uid()) = 'owner');
create policy "owner borra noticias" on news for delete to authenticated
  using ((select role from profiles where id = auth.uid()) = 'owner');

-- Medios de la red social (imágenes y videos)
insert into storage.buckets (id, name, public) values ('posts','posts',true);
create policy "ver medios" on storage.objects for select using (bucket_id = 'posts');
create policy "subir medios a mi carpeta" on storage.objects for insert to authenticated
  with check (bucket_id = 'posts' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "borrar mis medios" on storage.objects for delete to authenticated
  using (bucket_id = 'posts' and (storage.foldername(name))[1] = auth.uid()::text);

-- Ejemplo: publicar una noticia en el carrusel (como owner, desde el SQL Editor)
-- insert into news (title, body) values ('Gran inauguración', 'La galería comunitaria abre el 31 de octubre.');
