-- 마이그레이션 스모크 테스트 (Docker 없는 로컬 Postgres + supabase_stub.sql 용)
-- 정식 RLS 테스트(pgTAP)는 7단계에서 supabase/tests/database/ 에 추가한다.
\set ON_ERROR_STOP on
\o /dev/null
\set adult_a '''aaaaaaaa-0000-0000-0000-000000000001'''
\set adult_b '''aaaaaaaa-0000-0000-0000-000000000002'''
\set teen_t  '''bbbbbbbb-0000-0000-0000-000000000001'''
\set teen_t2 '''bbbbbbbb-0000-0000-0000-000000000002'''
\set teen_t3 '''bbbbbbbb-0000-0000-0000-000000000003'''
\set child_c '''cccccccc-0000-0000-0000-000000000001'''
\set outsider '''dddddddd-0000-0000-0000-000000000001'''
\set admin_m '''eeeeeeee-0000-0000-0000-000000000001'''

create function pg_temp.expect_error(p_sql text, p_like text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'EXPECTED ERROR (%), but succeeded: %', p_like, p_sql;
exception when others then
  if sqlerrm like 'EXPECTED ERROR%' then raise; end if;
  if sqlerrm not like p_like then
    raise exception 'wrong error for %: got "%", expected like "%"', p_sql, sqlerrm, p_like;
  end if;
end $$;
grant execute on function pg_temp.expect_error(text, text) to anon, authenticated;

create function pg_temp.expect_eq(p_actual bigint, p_expected bigint, p_label text) returns void language plpgsql as $$
begin
  if p_actual is distinct from p_expected then
    raise exception 'FAIL %: expected %, got %', p_label, p_expected, p_actual;
  end if;
  raise notice 'ok - %', p_label;
end $$;
grant execute on function pg_temp.expect_eq(bigint, bigint, text) to anon, authenticated;

-- ---------------------------------------------------------------- 가입
insert into public.banned_words (word) values ('바보');
insert into auth.users (id, email, raw_user_meta_data) values
  (:adult_a, 'a@example.com', '{"nickname":"선생님","birth_year":"1985"}'),
  (:adult_b, 'b@example.com', '{"nickname":"어른B","birth_year":"1990"}'),
  (:teen_t, 't@example.com', '{"nickname":"학생T","birth_year":"2010"}'),
  (:teen_t2, 't2@example.com', '{"nickname":"학생T2","birth_year":"2009"}'),
  (:teen_t3, 't3@example.com', '{"nickname":"학생T3","birth_year":"2009"}'),
  (:child_c, 'c@example.com', '{"nickname":"어린이C","birth_year":"2014","guardian_email":"Parent@Example.com"}'),
  (:outsider, 'o@example.com', '{"nickname":"외부인","birth_year":"1980"}'),
  (:admin_m, 'm@example.com', '{"nickname":"관리자","birth_year":"1980"}');
update public.profiles set role = 'admin' where id = :admin_m;

select pg_temp.expect_eq((select count(*) from public.profiles where age_group = 'teen'), 3, 'teens classified');
select pg_temp.expect_eq((select count(*) from public.profiles where id = :child_c and age_group = 'child_u14' and status = 'pending_guardian'), 1, 'child is pending_guardian');
select pg_temp.expect_eq((select count(*) from auth.users where raw_user_meta_data ? 'birth_year' or raw_user_meta_data ? 'guardian_email'), 0, 'sensitive metadata stripped');
select pg_temp.expect_eq((select count(*) from public.profile_private where id = :child_c and guardian_email = 'parent@example.com'), 1, 'guardian email stored lowercased');
select pg_temp.expect_error($$insert into auth.users (email, raw_user_meta_data) values ('x@example.com', '{"nickname":"꼬마","birth_year":"2015"}')$$, 'guardian_email_required');
select pg_temp.expect_error($$insert into auth.users (email, raw_user_meta_data) values ('y@example.com', '{"nickname":"바보야","birth_year":"1990"}')$$, 'nickname_banned_word');
-- 2012년생: 올해(2026) 13세 또는 14세 → 보수적으로 child_u14
select pg_temp.expect_eq((select count(*) from (select private.compute_age_group(2012, date '2026-10-13') = 'child_u14' as ok) s where ok), 1, 'age boundary 2012 -> child_u14');
select pg_temp.expect_eq((select count(*) from (select private.compute_age_group(2007, date '2026-10-13') = 'teen' as ok) s where ok), 1, 'age boundary 2007 -> teen');
select pg_temp.expect_eq((select count(*) from (select private.compute_age_group(2006, date '2026-10-13') = 'adult' as ok) s where ok), 1, 'age boundary 2006 -> adult');

-- ---------------------------------------------------------------- 그룹·챌린지 (교사 A)
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated, anon;

set role authenticated;
select set_config('request.jwt.claim.sub', :adult_a, false);
insert into public.groups (name) values ('3학년 2반');
insert into ids select 'group', id from public.groups where name = '3학년 2반';
insert into public.challenges (group_id, title, start_date, end_date, goal_type, goal_value, visibility, target_age)
  select v, '청소년 30일 독서', private.kst_today() - 3, private.kst_today() + 30, 'days', 2, 'group_only', 'teen_only'
  from ids where k = 'group';
insert into ids select 'teen_ch', id from public.challenges where title = '청소년 30일 독서';
insert into public.challenges (title, start_date, end_date, goal_type, goal_value, visibility, target_age)
  values ('성인 북클럽', private.kst_today(), private.kst_today() + 30, 'books', 3, 'public', 'adult_only');
insert into ids select 'adult_ch', id from public.challenges where title = '성인 북클럽';
select pg_temp.expect_eq((select count(*) from public.group_members), 1, 'owner auto-joined group');
-- 교사(그룹 운영자)는 teen_only 챌린지에 참여할 수 있다
insert into public.challenge_members (challenge_id) select v from ids where k = 'teen_ch';
select pg_temp.expect_error($$update public.profiles set role = 'admin' where id = auth.uid()$$, 'permission denied%');
select pg_temp.expect_error($$update public.profiles set status = 'active' where id = auth.uid()$$, 'permission denied%');
reset role;

-- 학생들: 초대 코드로 그룹 가입 후 챌린지 참여
select set_config('test.code', (select invite_code from public.groups limit 1), false);
set role authenticated;
select set_config('request.jwt.claim.sub', :teen_t, false);
select public.join_group_by_code(lower(current_setting('test.code'))) is not null as joined;
insert into public.challenge_members (challenge_id) select v from ids where k = 'teen_ch';
select pg_temp.expect_error($$insert into public.challenge_members (challenge_id) select v from ids where k = 'adult_ch'$$, '%row-level security%');
select set_config('request.jwt.claim.sub', :teen_t2, false);
select public.join_group_by_code(current_setting('test.code'));
insert into public.challenge_members (challenge_id) select v from ids where k = 'teen_ch';
select set_config('request.jwt.claim.sub', :teen_t3, false);
select public.join_group_by_code(current_setting('test.code'));
insert into public.challenge_members (challenge_id) select v from ids where k = 'teen_ch';
select set_config('request.jwt.claim.sub', :child_c, false);
select public.join_group_by_code(current_setting('test.code'));
insert into public.challenge_members (challenge_id) select v from ids where k = 'teen_ch';

-- 성인 B: 그룹에 가입해도 teen_only 챌린지는 참여 불가
select set_config('request.jwt.claim.sub', :adult_b, false);
select public.join_group_by_code(current_setting('test.code'));
select pg_temp.expect_error($$insert into public.challenge_members (challenge_id) select v from ids where k = 'teen_ch'$$, '%row-level security%');
insert into public.challenge_members (challenge_id) select v from ids where k = 'adult_ch';
-- 미성년자는 그룹·챌린지를 만들 수 없다
select set_config('request.jwt.claim.sub', :teen_t, false);
select pg_temp.expect_error($$insert into public.groups (name) values ('몰래 그룹')$$, '%row-level security%');
reset role;
select pg_temp.expect_eq((select member_count from public.challenges where title = '청소년 30일 독서'), 5, 'member_count maintained');

-- ---------------------------------------------------------------- 독서 인증
set role authenticated;
select set_config('request.jwt.claim.sub', :teen_t, false);
insert into public.books (title, author) values ('어린 왕자', '생텍쥐페리');
insert into ids select 'book', id from public.books limit 1;
insert into storage.objects (bucket_id, name) values ('reading-photos', current_setting('request.jwt.claim.sub') || '/p1.jpg');
select pg_temp.expect_error($$insert into storage.objects (bucket_id, name) values ('reading-photos', 'aaaaaaaa-0000-0000-0000-000000000001/x.jpg')$$, '%row-level security%');
-- 날짜는 클라이언트가 정할 수 없다(컬럼 권한 없음 + 트리거가 KST 오늘로 고정)
select pg_temp.expect_error($$insert into public.reading_logs (challenge_id, book_id, pages_read, image_path, image_hash, log_date)
  select (select v from ids where k = 'teen_ch'), (select v from ids where k = 'book'), 1, auth.uid() || '/p0.jpg', repeat('0', 64), date '2000-01-01'$$, 'permission denied%');
insert into public.reading_logs (challenge_id, book_id, page_from, page_to, pages_read, comment, image_path, image_hash)
  select (select v from ids where k = 'teen_ch'), (select v from ids where k = 'book'), 10, 29, 999, '재밌다',
         current_setting('request.jwt.claim.sub') || '/p1.jpg', repeat('a', 64);
insert into ids select 'log', id from public.reading_logs limit 1;
select pg_temp.expect_eq((select count(*) from public.reading_logs where log_date = private.kst_today() and pages_read = 20), 1, 'log_date forced to KST today, pages from range');
select pg_temp.expect_error($$insert into public.reading_logs (challenge_id, book_id, pages_read, image_path, image_hash)
  select (select v from ids where k = 'teen_ch'), (select v from ids where k = 'book'), 5, auth.uid() || '/p2.jpg', repeat('b', 64)$$, '%reading_logs_one_per_day%');
select pg_temp.expect_error($$insert into public.reading_logs (challenge_id, book_id, pages_read, image_path, image_hash, user_id)
  select (select v from ids where k = 'teen_ch'), (select v from ids where k = 'book'), 5, auth.uid() || '/p3.jpg', repeat('c', 64), auth.uid()$$, 'permission denied%');
select pg_temp.expect_eq((select count(*) from public.user_badges where badge_code = 'first_log'), 1, 'first_log badge awarded by trigger');
select pg_temp.expect_error($$insert into public.user_badges (user_id, badge_code) values (auth.uid(), 'streak_30')$$, 'permission denied%');
select pg_temp.expect_error($$insert into public.comments (reading_log_id, body) select v, '이 바 보야' from ids where k = 'log'$$, 'banned_word');

-- 보호자 동의 전 어린이는 인증·댓글 불가
select set_config('request.jwt.claim.sub', :child_c, false);
select pg_temp.expect_error($$insert into public.comments (reading_log_id, body) select v, '멋져요' from ids where k = 'log'$$, '%row-level security%');
select pg_temp.expect_eq((select count(*) from public.reading_logs), 1, 'pending child (member) can read feed');

-- ---------------------------------------------------------------- 공개 범위
select set_config('request.jwt.claim.sub', :outsider, false);
select pg_temp.expect_eq((select count(*) from public.reading_logs), 0, 'non-member cannot see teen log');
select pg_temp.expect_eq((select count(*) from storage.objects), 0, 'non-member cannot see teen photo');
select pg_temp.expect_eq((select count(*) from public.profiles), 1, 'non-member sees only own profile');
select pg_temp.expect_eq((select count(*) from public.challenges), 1, 'non-member sees only public challenge');
select pg_temp.expect_eq((select count(*) from public.banned_words), 0, 'non-admin cannot read banned_words');
select pg_temp.expect_error($$select public.admin_review_content((select v from ids where k = 'log'), null, 'restore')$$, 'forbidden');
select pg_temp.expect_error($$select public.admin_set_suspension(auth.uid(), true)$$, 'forbidden');
select set_config('request.jwt.claim.sub', :adult_b, false);
select pg_temp.expect_eq((select count(*) from public.reading_logs), 0, 'group member but not challenge member cannot see log');
select set_config('request.jwt.claim.sub', :adult_a, false);
select pg_temp.expect_eq((select count(*) from public.reading_logs), 1, 'teacher (staff) sees student log');
select pg_temp.expect_eq((select count(*) from storage.objects), 1, 'teacher sees student photo');
select pg_temp.expect_eq((select count(*) from public.profile_private), 1, 'profile_private only own');
reset role;
set role anon;
select set_config('request.jwt.claim.sub', '', false);
select pg_temp.expect_error($$select count(*) from public.reading_logs$$, 'permission denied%');
select pg_temp.expect_error($$select count(*) from public.profiles$$, 'permission denied%');
select pg_temp.expect_eq((select count(*) from public.challenges), 1, 'anon sees public challenge only');
select pg_temp.expect_eq((select count(*) from storage.objects), 0, 'anon sees no photos');
reset role;

-- ---------------------------------------------------------------- 신고 3건 → 자동 숨김
set role authenticated;
select set_config('request.jwt.claim.sub', :teen_t, false);
select pg_temp.expect_error($$insert into public.reports (reading_log_id, reason) select v, 'spam' from ids where k = 'log'$$, '%row-level security%');
select set_config('request.jwt.claim.sub', :teen_t2, false);
insert into public.reports (reading_log_id, reason) select v, 'spam' from ids where k = 'log';
select pg_temp.expect_error($$insert into public.reports (reading_log_id, reason) select v, 'abuse' from ids where k = 'log'$$, '%reports_unique_log%');
select set_config('request.jwt.claim.sub', :teen_t3, false);
insert into public.reports (reading_log_id, reason) select v, 'spam' from ids where k = 'log';
select set_config('request.jwt.claim.sub', :adult_a, false);
insert into public.reports (reading_log_id, reason) select v, 'inappropriate' from ids where k = 'log';
select pg_temp.expect_eq((select count(*) from public.reading_logs), 0, 'auto-hidden after 3 reports (teacher view)');
select set_config('request.jwt.claim.sub', :teen_t, false);
select pg_temp.expect_eq((select count(*) from public.reading_logs where is_hidden and review_status = 'pending_review'), 1, 'author still sees own hidden log');
select set_config('request.jwt.claim.sub', :admin_m, false);
select pg_temp.expect_eq((select count(*) from public.reports where status = 'pending'), 3, 'admin sees reports');
select public.admin_review_content((select v from ids where k = 'log'), null, 'restore');
select set_config('request.jwt.claim.sub', :adult_a, false);
select pg_temp.expect_eq((select count(*) from public.reading_logs), 1, 'restored log visible again');

-- ---------------------------------------------------------------- 차단
select set_config('request.jwt.claim.sub', :teen_t2, false);
insert into public.blocks (blocked_id) values (:teen_t);
select pg_temp.expect_eq((select count(*) from public.reading_logs), 0, 'blocker does not see blocked user log');
select set_config('request.jwt.claim.sub', :teen_t, false);
select pg_temp.expect_eq((select count(*) from public.blocks), 0, 'blocked user cannot see block rows');
reset role;

-- ---------------------------------------------------------------- 이미지 재사용
update public.reading_logs set log_date = log_date - 1;  -- 어제 올린 것으로 만든다
set role authenticated;
select set_config('request.jwt.claim.sub', :teen_t, false);
select pg_temp.expect_error($$insert into public.reading_logs (challenge_id, book_id, pages_read, image_path, image_hash)
  select (select v from ids where k = 'teen_ch'), (select v from ids where k = 'book'), 5, auth.uid() || '/p9.jpg', repeat('a', 64)$$, 'duplicate_image');
insert into public.reading_logs (challenge_id, book_id, pages_read, image_path, image_hash, is_finished)
  select (select v from ids where k = 'teen_ch'), (select v from ids where k = 'book'), 5, auth.uid() || '/p10.jpg', repeat('d', 64), true;
select pg_temp.expect_eq((select count(*) from public.user_badges where user_id = auth.uid() and badge_code in ('first_finish', 'challenge_complete')), 2, 'first_finish + challenge_complete (2 days goal)');
select pg_temp.expect_eq(public.my_current_streak(), 2, 'streak = 2');
select pg_temp.expect_eq(public.my_challenge_progress((select v from ids where k = 'teen_ch')), 2, 'progress = 2 days');
reset role;

-- ---------------------------------------------------------------- 보호자 동의 / 정지
insert into public.guardian_consents (user_id, guardian_email, token_hash, expires_at)
  values (:child_c, 'parent@example.com', encode(sha256(convert_to('secret-token', 'UTF8')), 'hex'), now() + interval '1 day');
set role authenticated;
select pg_temp.expect_error($$select public.confirm_guardian_consent('secret-token')$$, 'permission denied%');
reset role;
set role service_role;
select public.confirm_guardian_consent('secret-token');
reset role;
select pg_temp.expect_eq((select count(*) from public.profiles where id = :child_c and status = 'active'), 1, 'guardian consent activates child');
set role authenticated;
select set_config('request.jwt.claim.sub', :admin_m, false);
select public.admin_set_suspension(:teen_t, true);
select set_config('request.jwt.claim.sub', :teen_t, false);
select pg_temp.expect_error($$insert into public.comments (reading_log_id, body) select v, '안녕' from ids where k = 'log'$$, '%row-level security%');
reset role;

-- 그룹 운영자는 그룹을 떠날 수 없지만, 그룹 삭제는 가능
set role authenticated;
select set_config('request.jwt.claim.sub', :adult_a, false);
select pg_temp.expect_error($$delete from public.group_members where user_id = auth.uid()$$, 'group_owner_cannot_leave');
reset role;
\o
\echo 'ALL SMOKE TESTS PASSED'
