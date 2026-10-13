-- Storage: 인증 사진 버킷(비공개). 이미지는 서버에서 만든 signed URL로만 제공한다.
-- 경로 규칙: {user_id}/{uuid}.{ext}

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('reading-photos', 'reading-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- 업로드: 본인 폴더에만, 활성 사용자만
create policy reading_photos_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'reading-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select private.is_active_user())
  );

-- 조회(signed URL 발급 포함): 본인 사진, 또는 내가 볼 수 있는 인증 글에 연결된 사진.
-- reading_logs 서브쿼리에는 호출자의 RLS가 적용되므로 피드 공개 범위와 사진 공개 범위가 항상 같다.
create policy reading_photos_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'reading-photos'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or exists (select 1 from public.reading_logs rl where rl.image_path = name)
    )
  );

-- 삭제: 본인 사진만 (인증 글 삭제 시 함께 정리)
create policy reading_photos_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'reading-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
