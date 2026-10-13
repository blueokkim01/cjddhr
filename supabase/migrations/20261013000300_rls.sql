-- 권한과 RLS
-- Supabase는 public 스키마의 새 테이블에 anon/authenticated 전체 권한을 기본으로 준다.
-- 먼저 모두 회수한 뒤, 필요한 명령과 컬럼만 다시 부여한다(컬럼 권한 + RLS 이중 방어).
-- 예: profiles.role/status는 어떤 정책으로도 사용자가 직접 바꿀 수 없다.

do $$
declare
  t text;
begin
  foreach t in array array[
    'profiles', 'profile_private', 'guardian_consents', 'groups', 'group_members',
    'challenges', 'challenge_members', 'books', 'reading_logs', 'reactions', 'comments',
    'reports', 'blocks', 'badges', 'user_badges', 'banned_words'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from anon, authenticated', t);
  end loop;
end $$;

grant usage on schema private to anon, authenticated, service_role;

-- 함수는 기본적으로 PUBLIC에 실행 권한이 있다. 관리용·서버 전용 RPC는 막는다.
revoke execute on function public.confirm_guardian_consent(text) from public, anon, authenticated;
grant execute on function public.confirm_guardian_consent(text) to service_role;
revoke execute on function private.refresh_age_groups() from public, anon, authenticated;
revoke execute on function public.join_group_by_code(text) from public, anon;
revoke execute on function public.regenerate_invite_code(uuid) from public, anon;
revoke execute on function public.admin_review_content(uuid, uuid, text) from public, anon;
revoke execute on function public.admin_set_suspension(uuid, boolean) from public, anon;
revoke execute on function public.my_challenge_progress(uuid) from public, anon;
revoke execute on function public.my_current_streak() from public, anon;
revoke execute on function public.check_banned_words(text) from public, anon;
grant execute on function public.join_group_by_code(text) to authenticated;
grant execute on function public.regenerate_invite_code(uuid) to authenticated;
grant execute on function public.admin_review_content(uuid, uuid, text) to authenticated;
grant execute on function public.admin_set_suspension(uuid, boolean) to authenticated;
grant execute on function public.my_challenge_progress(uuid) to authenticated;
grant execute on function public.my_current_streak() to authenticated;
grant execute on function public.check_banned_words(text) to authenticated;

-- ---------------------------------------------------------------------------
-- profiles: 본인, 관리자, 같은 챌린지·그룹 사람만 조회. 공개 프로필은 없다.
-- ---------------------------------------------------------------------------
grant select on public.profiles to authenticated;
grant update (nickname) on public.profiles to authenticated;

create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or (select private.is_admin())
    or private.shares_community(id)
  );

create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = (select auth.uid()) or (select private.is_admin()))
  with check (id = (select auth.uid()) or (select private.is_admin()));

-- ---------------------------------------------------------------------------
-- profile_private: 본인만 조회. 관리자도 볼 수 없다(필요 시 service_role 사용).
-- ---------------------------------------------------------------------------
grant select on public.profile_private to authenticated;

create policy profile_private_select_self on public.profile_private
  for select to authenticated
  using (id = (select auth.uid()));

-- guardian_consents: 정책 없음 → service_role 전용

-- ---------------------------------------------------------------------------
-- groups / group_members
-- 그룹은 성인만 만들 수 있다(교사·북클럽 운영자). 가입은 join_group_by_code RPC로만.
-- ---------------------------------------------------------------------------
grant select, delete on public.groups to authenticated;
grant insert (name, description) on public.groups to authenticated;
grant update (name, description) on public.groups to authenticated;

create policy groups_select on public.groups
  for select to authenticated
  using (
    owner_id = (select auth.uid())
    or private.is_group_member(id)
    or (select private.is_admin())
  );

create policy groups_insert on public.groups
  for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and (select private.is_active_user())
    and (select private.is_adult())
  );

create policy groups_update on public.groups
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy groups_delete on public.groups
  for delete to authenticated
  using (owner_id = (select auth.uid()) or (select private.is_admin()));

grant select, delete on public.group_members to authenticated;

create policy group_members_select on public.group_members
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or private.is_group_member(group_id)
    or (select private.is_admin())
  );

-- 본인 탈퇴, 또는 운영자가 내보내기
create policy group_members_delete on public.group_members
  for delete to authenticated
  using (
    user_id = (select auth.uid())
    or private.is_group_owner(group_id)
    or (select private.is_admin())
  );

-- ---------------------------------------------------------------------------
-- challenges
-- 공개 챌린지는 비로그인도 목록·상세(제목, 설명, 기간, 참여자 수)를 볼 수 있다.
-- ---------------------------------------------------------------------------
grant select on public.challenges to anon, authenticated;
grant insert (group_id, title, description, start_date, end_date, goal_type, goal_value, visibility, target_age)
  on public.challenges to authenticated;
grant update (title, description) on public.challenges to authenticated;
grant delete on public.challenges to authenticated;

create policy challenges_select_public on public.challenges
  for select to anon
  using (visibility = 'public');

create policy challenges_select on public.challenges
  for select to authenticated
  using (
    visibility = 'public'
    or created_by = (select auth.uid())
    or private.is_group_member(group_id)
    or private.is_challenge_member(id)
    or (select private.is_admin())
  );

create policy challenges_insert on public.challenges
  for insert to authenticated
  with check (
    created_by = (select auth.uid())
    and (select private.is_active_user())
    and (select private.is_adult())
    and (group_id is null or private.is_group_owner(group_id))
  );

create policy challenges_update on public.challenges
  for update to authenticated
  using (private.is_challenge_staff(id) or (select private.is_admin()))
  with check (private.is_challenge_staff(id) or (select private.is_admin()));

create policy challenges_delete on public.challenges
  for delete to authenticated
  using (private.is_challenge_staff(id) or (select private.is_admin()));

-- ---------------------------------------------------------------------------
-- challenge_members: 연령 제한은 can_join_challenge에서 강제
-- ---------------------------------------------------------------------------
grant select, delete on public.challenge_members to authenticated;
grant insert (challenge_id) on public.challenge_members to authenticated;

create policy challenge_members_select on public.challenge_members
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or private.is_challenge_member(challenge_id)
    or private.is_challenge_staff(challenge_id)
    or (select private.is_admin())
  );

create policy challenge_members_insert on public.challenge_members
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and private.can_join_challenge(challenge_id)
  );

create policy challenge_members_delete on public.challenge_members
  for delete to authenticated
  using (
    user_id = (select auth.uid())
    or private.is_challenge_staff(challenge_id)
    or (select private.is_admin())
  );

-- ---------------------------------------------------------------------------
-- books: 로그인 사용자 누구나 조회·등록 (수정·삭제 없음)
-- ---------------------------------------------------------------------------
grant select on public.books to authenticated;
grant insert (isbn, title, author, publisher, thumbnail_url, source) on public.books to authenticated;

create policy books_select on public.books
  for select to authenticated
  using (true);

create policy books_insert on public.books
  for insert to authenticated
  with check ((select private.current_status()) <> 'suspended');

-- ---------------------------------------------------------------------------
-- reading_logs
-- 인증 게시물은 연령과 관계없이 같은 챌린지 참여자·운영자·관리자에게만 보인다.
-- (미성년자 게시물 비공개 규칙을 포함하면서 더 단순하다. anon에게는 select 권한 자체가 없다.)
-- 숨김 처리된 글은 작성자 본인과 관리자만 본다.
-- ---------------------------------------------------------------------------
grant select, delete on public.reading_logs to authenticated;
grant insert (challenge_id, book_id, page_from, page_to, pages_read, minutes, comment, is_finished, image_path, image_hash)
  on public.reading_logs to authenticated;

create policy reading_logs_select on public.reading_logs
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.is_admin())
    or (
      not is_hidden
      and (private.is_challenge_member(challenge_id) or private.is_challenge_staff(challenge_id))
      and not private.is_blocked_between(user_id)
    )
  );

create policy reading_logs_insert on public.reading_logs
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (select private.is_active_user())
    and private.is_challenge_member(challenge_id)
  );

create policy reading_logs_delete on public.reading_logs
  for delete to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));

-- ---------------------------------------------------------------------------
-- reactions: 볼 수 있는 인증 글에만, 활성 사용자만
-- 아래 exists 서브쿼리는 호출자 권한으로 실행되어 reading_logs RLS가 그대로 적용된다.
-- ---------------------------------------------------------------------------
grant select, delete on public.reactions to authenticated;
grant insert (reading_log_id, kind) on public.reactions to authenticated;

create policy reactions_select on public.reactions
  for select to authenticated
  using (
    exists (select 1 from public.reading_logs rl where rl.id = reading_log_id)
    and not private.is_blocked_between(user_id)
  );

create policy reactions_insert on public.reactions
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (select private.is_active_user())
    and exists (select 1 from public.reading_logs rl where rl.id = reading_log_id and not rl.is_hidden)
  );

create policy reactions_delete on public.reactions
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- comments
-- ---------------------------------------------------------------------------
grant select, delete on public.comments to authenticated;
grant insert (reading_log_id, body) on public.comments to authenticated;

create policy comments_select on public.comments
  for select to authenticated
  using (
    exists (select 1 from public.reading_logs rl where rl.id = reading_log_id)
    and (
      user_id = (select auth.uid())
      or (select private.is_admin())
      or (not is_hidden and not private.is_blocked_between(user_id))
    )
  );

create policy comments_insert on public.comments
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (select private.is_active_user())
    and exists (select 1 from public.reading_logs rl where rl.id = reading_log_id and not rl.is_hidden)
  );

-- 본인, 관리자, 그리고 글 작성자는 자기 글에 달린 댓글을 지울 수 있다.
create policy comments_delete on public.comments
  for delete to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.is_admin())
    or private.reading_log_author(reading_log_id) = (select auth.uid())
  );

-- ---------------------------------------------------------------------------
-- reports: 본인 신고만 조회, 관리자는 전체
-- ---------------------------------------------------------------------------
grant select on public.reports to authenticated;
grant insert (reading_log_id, comment_id, reason, detail) on public.reports to authenticated;

create policy reports_select on public.reports
  for select to authenticated
  using (reporter_id = (select auth.uid()) or (select private.is_admin()));

create policy reports_insert on public.reports
  for insert to authenticated
  with check (
    reporter_id = (select auth.uid())
    and (select private.current_status()) <> 'suspended'
    and (
      (reading_log_id is not null and exists (
        select 1 from public.reading_logs rl
        where rl.id = reading_log_id and rl.user_id <> (select auth.uid())
      ))
      or (comment_id is not null and exists (
        select 1 from public.comments c
        where c.id = comment_id and c.user_id <> (select auth.uid())
      ))
    )
  );

-- ---------------------------------------------------------------------------
-- blocks
-- ---------------------------------------------------------------------------
grant select, delete on public.blocks to authenticated;
grant insert (blocked_id) on public.blocks to authenticated;

create policy blocks_select on public.blocks
  for select to authenticated
  using (blocker_id = (select auth.uid()));

create policy blocks_insert on public.blocks
  for insert to authenticated
  with check (blocker_id = (select auth.uid()));

create policy blocks_delete on public.blocks
  for delete to authenticated
  using (blocker_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- badges / user_badges: 지급은 트리거에서만
-- ---------------------------------------------------------------------------
grant select on public.badges to anon, authenticated;

create policy badges_select on public.badges
  for select to anon, authenticated
  using (true);

grant select on public.user_badges to authenticated;

create policy user_badges_select on public.user_badges
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.is_admin())
    or private.shares_community(user_id)
  );

-- ---------------------------------------------------------------------------
-- banned_words: 관리자만
-- ---------------------------------------------------------------------------
grant select, delete on public.banned_words to authenticated;
grant insert (word) on public.banned_words to authenticated;

create policy banned_words_admin_select on public.banned_words
  for select to authenticated
  using ((select private.is_admin()));

create policy banned_words_admin_insert on public.banned_words
  for insert to authenticated
  with check ((select private.is_admin()));

create policy banned_words_admin_delete on public.banned_words
  for delete to authenticated
  using ((select private.is_admin()));
