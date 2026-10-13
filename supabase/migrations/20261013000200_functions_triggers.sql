-- 헬퍼 함수와 트리거
-- private 스키마는 PostgREST에 노출되지 않으므로 클라이언트가 직접 호출할 수 없다.
-- RLS 정책에서 쓰는 헬퍼는 security definer로 만든다. 정책 안에서 같은 테이블을 다시 조회하면
-- 무한 재귀가 나기 때문이다. 모든 security definer 함수는 search_path를 비워 탈취를 막는다.

-- ---------------------------------------------------------------------------
-- 날짜·연령
-- ---------------------------------------------------------------------------
create function private.kst_today()
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'Asia/Seoul')::date
$$;

-- 출생연도만 받으므로 만 나이는 (올해 - 출생연도 - 1) 또는 (올해 - 출생연도) 중 하나다.
-- 보호가 필요한 쪽으로 판정한다: 14세 미만일 가능성이 있으면 child_u14,
-- 19세 이상이 확실할 때만 adult. src/features/auth/lib/age-group.ts 와 같은 규칙이어야 한다.
create function private.compute_age_group(p_birth_year integer, p_today date)
returns public.age_group
language sql
immutable
set search_path = ''
as $$
  select case
    when extract(year from p_today)::integer - p_birth_year <= 14 then 'child_u14'
    when extract(year from p_today)::integer - p_birth_year <= 19 then 'teen'
    else 'adult'
  end::public.age_group
$$;

-- ---------------------------------------------------------------------------
-- 권한 판정 헬퍼 (RLS에서 사용)
-- ---------------------------------------------------------------------------
create function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and status <> 'suspended'
  )
$$;

create function private.current_status()
returns public.account_status
language sql
stable
security definer
set search_path = ''
as $$
  select status from public.profiles where id = auth.uid()
$$;

-- 인증·댓글·응원은 보호자 동의를 마치고 정지되지 않은 사용자만 할 수 있다.
create function private.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.current_status() = 'active', false)
$$;

create function private.is_adult()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and age_group = 'adult')
$$;

create function private.is_group_member(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = auth.uid()
  )
$$;

create function private.is_group_owner(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.groups where id = p_group_id and owner_id = auth.uid())
$$;

create function private.is_challenge_member(p_challenge_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.challenge_members
    where challenge_id = p_challenge_id and user_id = auth.uid()
  )
$$;

-- 챌린지 운영자: 만든 사람, 또는 챌린지가 속한 그룹의 운영자(교사)
create function private.is_challenge_staff(p_challenge_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.challenges c
    left join public.groups g on g.id = c.group_id
    where c.id = p_challenge_id
      and (c.created_by = auth.uid() or g.owner_id = auth.uid())
  )
$$;

-- 차단은 양방향으로 적용한다. 차단한 쪽도, 차단당한 쪽도 서로의 글·댓글을 보지 못한다.
create function private.is_blocked_between(p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = auth.uid() and blocked_id = p_other)
       or (blocker_id = p_other and blocked_id = auth.uid())
  )
$$;

-- 같은 챌린지·그룹에 속해 있거나 내가 운영하는 챌린지의 참여자일 때만 닉네임을 볼 수 있다.
create function private.shares_community(p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
      select 1
      from public.challenge_members mine
      join public.challenge_members theirs on theirs.challenge_id = mine.challenge_id
      where mine.user_id = auth.uid() and theirs.user_id = p_other
    )
    or exists (
      select 1
      from public.group_members mine
      join public.group_members theirs on theirs.group_id = mine.group_id
      where mine.user_id = auth.uid() and theirs.user_id = p_other
    )
    or exists (
      select 1
      from public.challenge_members m
      join public.challenges c on c.id = m.challenge_id
      where (m.user_id = p_other and c.created_by = auth.uid())
         or (m.user_id = auth.uid() and c.created_by = p_other)
    )
$$;

-- 연령 제한·그룹 제한·종료 여부를 한 곳에서 판정한다.
create function private.can_join_challenge(p_challenge_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.challenges c
    join public.profiles p on p.id = auth.uid()
    left join public.groups g on g.id = c.group_id
    where c.id = p_challenge_id
      and p.status <> 'suspended'
      and c.end_date >= private.kst_today()
      and (c.visibility = 'public' or private.is_group_member(c.group_id))
      and (
        c.target_age = 'all'
        or (c.target_age = 'teen_only' and p.age_group in ('teen', 'child_u14'))
        or (c.target_age = 'adult_only' and p.age_group = 'adult')
        -- 연령 제한 예외는 해당 그룹 운영자(교사)뿐이다.
        or g.owner_id = p.id
      )
  )
$$;

create function private.reading_log_author(p_log_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select user_id from public.reading_logs where id = p_log_id
$$;

-- ---------------------------------------------------------------------------
-- 금칙어 검사
-- ---------------------------------------------------------------------------
create function private.contains_banned_word(p_text text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.banned_words b
    where strpos(private.normalize_text(p_text), b.normalized) > 0
  )
$$;

-- 서버 액션이 저장 전에 친절한 오류 메시지를 보여줄 수 있도록 공개 RPC로도 제공한다.
-- 최종 판정은 아래 트리거가 한다.
create function public.check_banned_words(p_text text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.contains_banned_word(p_text)
$$;

-- ---------------------------------------------------------------------------
-- 진행률·스트릭 (대시보드와 배지 지급에서 공통 사용)
-- ---------------------------------------------------------------------------
create function private.challenge_progress(p_challenge_id uuid, p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case c.goal_type
      when 'books' then (
        select count(distinct rl.book_id) from public.reading_logs rl
        where rl.challenge_id = c.id and rl.user_id = p_user_id
          and rl.is_finished and rl.review_status <> 'hidden'
      )
      when 'pages' then (
        select coalesce(sum(rl.pages_read), 0) from public.reading_logs rl
        where rl.challenge_id = c.id and rl.user_id = p_user_id and rl.review_status <> 'hidden'
      )
      when 'days' then (
        select count(distinct rl.log_date) from public.reading_logs rl
        where rl.challenge_id = c.id and rl.user_id = p_user_id and rl.review_status <> 'hidden'
      )
    end::integer
  from public.challenges c
  where c.id = p_challenge_id
$$;

-- p_date로 끝나는 연속 인증 일수(챌린지 구분 없이 하루 한 번이라도 인증한 날 기준)
create function private.streak_ending_on(p_user_id uuid, p_date date)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  with days as (
    select distinct log_date from public.reading_logs
    where user_id = p_user_id and log_date <= p_date
  ),
  grouped as (
    select log_date, log_date - (row_number() over (order by log_date))::integer as grp
    from days
  )
  select count(*)::integer from grouped
  where grp = (select grp from grouped where log_date = p_date)
$$;

-- ---------------------------------------------------------------------------
-- 가입: auth.users → profiles / profile_private
-- user_metadata는 JWT와 세션 쿠키에 그대로 실리므로, 출생연도·보호자 이메일은
-- BEFORE 트리거에서 읽은 뒤 메타데이터에서 지워 버린다. 값은 트랜잭션 로컬 설정으로 넘긴다.
-- ---------------------------------------------------------------------------
create function private.handle_auth_user_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_nickname text := btrim(v_meta ->> 'nickname');
  v_birth_year integer;
  v_guardian text := nullif(lower(btrim(v_meta ->> 'guardian_email')), '');
  v_age public.age_group;
  v_this_year integer := extract(year from private.kst_today())::integer;
  v_key text;
begin
  if v_nickname is null or v_nickname = '' then
    raise exception 'nickname_required' using errcode = '22023';
  end if;
  if private.contains_banned_word(v_nickname) then
    raise exception 'nickname_banned_word' using errcode = '22023';
  end if;

  begin
    v_birth_year := (v_meta ->> 'birth_year')::integer;
  exception when others then
    raise exception 'birth_year_invalid' using errcode = '22023';
  end;
  if v_birth_year is null or v_birth_year < v_this_year - 100 or v_birth_year > v_this_year - 7 then
    raise exception 'birth_year_invalid' using errcode = '22023';
  end if;

  v_age := private.compute_age_group(v_birth_year, private.kst_today());
  if v_age = 'child_u14' then
    if v_guardian is null or v_guardian !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      raise exception 'guardian_email_required' using errcode = '22023';
    end if;
    if v_guardian = lower(new.email) then
      raise exception 'guardian_email_must_differ' using errcode = '22023';
    end if;
  else
    v_guardian := null;
  end if;

  -- 여러 행을 한 번에 넣어도 섞이지 않도록 사용자 id를 키에 포함한다.
  v_key := 'app.signup_' || replace(new.id::text, '-', '_');
  perform set_config(v_key || '_nickname', v_nickname, true);
  perform set_config(v_key || '_birth_year', v_birth_year::text, true);
  perform set_config(v_key || '_guardian_email', coalesce(v_guardian, ''), true);

  new.raw_user_meta_data := v_meta - 'birth_year' - 'guardian_email';
  return new;
end;
$$;

create function private.handle_auth_user_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text := 'app.signup_' || replace(new.id::text, '-', '_');
  v_birth_year integer := current_setting(v_key || '_birth_year')::integer;
  v_guardian text := nullif(current_setting(v_key || '_guardian_email'), '');
  v_age public.age_group := private.compute_age_group(v_birth_year, private.kst_today());
begin
  insert into public.profiles (id, nickname, age_group, status)
  values (
    new.id,
    current_setting(v_key || '_nickname'),
    v_age,
    case when v_age = 'child_u14' then 'pending_guardian' else 'active' end::public.account_status
  );
  insert into public.profile_private (id, birth_year, guardian_email)
  values (new.id, v_birth_year, v_guardian);
  return new;
end;
$$;

create trigger on_auth_user_before_insert
  before insert on auth.users
  for each row execute function private.handle_auth_user_before_insert();

create trigger on_auth_user_after_insert
  after insert on auth.users
  for each row execute function private.handle_auth_user_after_insert();

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create function private.profiles_before_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.nickname is distinct from old.nickname and private.contains_banned_word(new.nickname) then
    raise exception 'nickname_banned_word' using errcode = '22023';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_before_update
  before update on public.profiles
  for each row execute function private.profiles_before_update();

-- 출생연도 기준 연령 그룹은 해가 바뀌면 달라진다. 매년 1월 1일(KST)에 다시 계산한다.
-- 만 14세가 되면 보호자 동의 요건이 사라지므로 pending_guardian도 풀어 준다.
create function private.refresh_age_groups()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  with recalculated as (
    select pp.id, private.compute_age_group(pp.birth_year, private.kst_today()) as new_group
    from public.profile_private pp
  )
  update public.profiles p
  set age_group = r.new_group,
      status = case
        when p.status = 'pending_guardian' and r.new_group <> 'child_u14' then 'active'
        else p.status
      end::public.account_status
  from recalculated r
  where r.id = p.id and p.age_group is distinct from r.new_group;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- groups: 초대 코드 생성, 운영자 자동 가입
-- ---------------------------------------------------------------------------
create function private.generate_invite_code()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
begin
  loop
    select string_agg(substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::integer, 1), '')
      into v_code
    from generate_series(1, 6);
    exit when not exists (select 1 from public.groups where invite_code = v_code);
  end loop;
  return v_code;
end;
$$;

create function private.groups_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.invite_code := private.generate_invite_code();
  if auth.uid() is not null then
    new.owner_id := auth.uid();
  end if;
  return new;
end;
$$;

create function private.groups_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.group_members (group_id, user_id) values (new.id, new.owner_id)
  on conflict do nothing;
  return new;
end;
$$;

create trigger groups_before_insert
  before insert on public.groups
  for each row execute function private.groups_before_insert();

create trigger groups_after_insert
  after insert on public.groups
  for each row execute function private.groups_after_insert();

-- 그룹 운영자는 그룹을 떠날 수 없다(그룹을 지워야 한다).
create function private.group_members_before_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.groups where id = old.group_id and owner_id = old.user_id) then
    raise exception 'group_owner_cannot_leave' using errcode = '42501';
  end if;
  return old;
end;
$$;

create trigger group_members_before_delete
  before delete on public.group_members
  for each row
  when (pg_trigger_depth() = 0)
  execute function private.group_members_before_delete();

-- ---------------------------------------------------------------------------
-- challenges / challenge_members
-- ---------------------------------------------------------------------------
create function private.challenges_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null then
      new.created_by := auth.uid();
    end if;
    new.member_count := 0;
  end if;
  if (tg_op = 'INSERT' or new.title is distinct from old.title or new.description is distinct from old.description)
     and (private.contains_banned_word(new.title) or private.contains_banned_word(new.description)) then
    raise exception 'banned_word' using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger challenges_before_write
  before insert or update on public.challenges
  for each row execute function private.challenges_before_write();

create function private.challenge_members_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.challenges set member_count = member_count + 1 where id = new.challenge_id;
    return new;
  else
    update public.challenges set member_count = greatest(member_count - 1, 0) where id = old.challenge_id;
    return old;
  end if;
end;
$$;

create trigger challenge_members_count
  after insert or delete on public.challenge_members
  for each row execute function private.challenge_members_count();

-- ---------------------------------------------------------------------------
-- reading_logs
-- ---------------------------------------------------------------------------
create function private.reading_logs_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_challenge public.challenges%rowtype;
begin
  -- 날짜 판정은 언제나 서버 시각(KST)으로 한다.
  new.log_date := private.kst_today();
  new.created_at := now();
  new.is_hidden := false;
  new.review_status := 'none';

  select * into v_challenge from public.challenges where id = new.challenge_id;
  if new.log_date < v_challenge.start_date or new.log_date > v_challenge.end_date then
    raise exception 'challenge_not_in_progress' using errcode = '22023';
  end if;

  if split_part(new.image_path, '/', 1) <> new.user_id::text then
    raise exception 'image_path_not_owned' using errcode = '42501';
  end if;

  -- 같은 날 여러 챌린지에 같은 사진으로 인증하는 것은 허용하고,
  -- 다른 날 찍은 사진을 다시 쓰는 것만 막는다.
  if exists (
    select 1 from public.reading_logs
    where user_id = new.user_id and image_hash = new.image_hash and log_date <> new.log_date
  ) then
    raise exception 'duplicate_image' using errcode = '23505';
  end if;

  if new.page_from is not null then
    new.pages_read := new.page_to - new.page_from + 1;
  end if;

  if private.contains_banned_word(new.comment) then
    raise exception 'banned_word' using errcode = '22023';
  end if;

  return new;
end;
$$;

create trigger reading_logs_before_insert
  before insert on public.reading_logs
  for each row execute function private.reading_logs_before_insert();

-- 배지는 이 트리거에서만 지급한다(user_badges에는 클라이언트 쓰기 권한이 없다).
create function private.reading_logs_award_badges()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_streak integer;
  v_goal integer;
begin
  insert into public.user_badges (user_id, badge_code) values (new.user_id, 'first_log')
  on conflict do nothing;

  v_streak := private.streak_ending_on(new.user_id, new.log_date);
  if v_streak >= 7 then
    insert into public.user_badges (user_id, badge_code) values (new.user_id, 'streak_7')
    on conflict do nothing;
  end if;
  if v_streak >= 30 then
    insert into public.user_badges (user_id, badge_code) values (new.user_id, 'streak_30')
    on conflict do nothing;
  end if;

  if new.is_finished then
    insert into public.user_badges (user_id, badge_code) values (new.user_id, 'first_finish')
    on conflict do nothing;
  end if;

  select goal_value into v_goal from public.challenges where id = new.challenge_id;
  if private.challenge_progress(new.challenge_id, new.user_id) >= v_goal then
    insert into public.user_badges (user_id, badge_code, challenge_id)
    values (new.user_id, 'challenge_complete', new.challenge_id)
    on conflict do nothing;
  end if;

  return new;
end;
$$;

create trigger reading_logs_award_badges
  after insert on public.reading_logs
  for each row execute function private.reading_logs_award_badges();

-- ---------------------------------------------------------------------------
-- comments / books
-- ---------------------------------------------------------------------------
create function private.comments_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.body := btrim(new.body);
  new.created_at := now();
  new.is_hidden := false;
  new.review_status := 'none';
  if private.contains_banned_word(new.body) then
    raise exception 'banned_word' using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger comments_before_insert
  before insert on public.comments
  for each row execute function private.comments_before_insert();

create function private.books_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  if new.source = 'manual' and private.contains_banned_word(new.title) then
    raise exception 'banned_word' using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger books_before_insert
  before insert on public.books
  for each row execute function private.books_before_insert();

-- ---------------------------------------------------------------------------
-- reports: 검토 대기 신고가 3건 이상이면 자동 숨김
-- ---------------------------------------------------------------------------
create function private.reports_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.reading_log_id is not null then
    if (select count(*) from public.reports
        where reading_log_id = new.reading_log_id and status = 'pending') >= 3 then
      update public.reading_logs
      set is_hidden = true, review_status = 'pending_review'
      where id = new.reading_log_id and not is_hidden;
    end if;
  else
    if (select count(*) from public.reports
        where comment_id = new.comment_id and status = 'pending') >= 3 then
      update public.comments
      set is_hidden = true, review_status = 'pending_review'
      where id = new.comment_id and not is_hidden;
    end if;
  end if;
  return new;
end;
$$;

create trigger reports_after_insert
  after insert on public.reports
  for each row execute function private.reports_after_insert();

-- ---------------------------------------------------------------------------
-- 공개 RPC
-- ---------------------------------------------------------------------------

-- 초대 코드로 그룹 가입. 가입 전에는 그룹을 조회할 수 없으므로 security definer로 처리한다.
create function public.join_group_by_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if private.current_status() = 'suspended' then
    raise exception 'account_suspended' using errcode = '42501';
  end if;

  select id into v_group_id from public.groups where invite_code = upper(btrim(p_code));
  if v_group_id is null then
    raise exception 'invalid_invite_code' using errcode = 'P0002';
  end if;

  insert into public.group_members (group_id, user_id) values (v_group_id, auth.uid())
  on conflict do nothing;
  return v_group_id;
end;
$$;

create function public.regenerate_invite_code(p_group_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  if not private.is_group_owner(p_group_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  v_code := private.generate_invite_code();
  update public.groups set invite_code = v_code where id = p_group_id;
  return v_code;
end;
$$;

-- 대시보드용: 내 챌린지 진행률 (본인 것만)
create function public.my_challenge_progress(p_challenge_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select private.challenge_progress(p_challenge_id, auth.uid())
$$;

create function public.my_current_streak()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  -- 오늘 아직 인증하지 않았으면 어제까지의 스트릭을 유지해서 보여준다.
  select greatest(
    private.streak_ending_on(auth.uid(), private.kst_today()),
    private.streak_ending_on(auth.uid(), private.kst_today() - 1)
  )
$$;

create function public.kst_today()
returns date
language sql
stable
set search_path = ''
as $$
  select private.kst_today()
$$;

-- 관리자: 신고된 게시물·댓글 처리
create function public.admin_review_content(
  p_reading_log_id uuid,
  p_comment_id uuid,
  p_decision text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if num_nonnulls(p_reading_log_id, p_comment_id) <> 1 or p_decision not in ('keep_hidden', 'restore') then
    raise exception 'invalid_arguments' using errcode = '22023';
  end if;

  if p_reading_log_id is not null then
    update public.reading_logs
    set is_hidden = (p_decision = 'keep_hidden'),
        review_status = case when p_decision = 'keep_hidden' then 'hidden' else 'restored' end::public.review_status
    where id = p_reading_log_id;
    update public.reports
    set status = 'resolved', resolved_by = auth.uid(), resolved_at = now()
    where reading_log_id = p_reading_log_id and status = 'pending';
  else
    update public.comments
    set is_hidden = (p_decision = 'keep_hidden'),
        review_status = case when p_decision = 'keep_hidden' then 'hidden' else 'restored' end::public.review_status
    where id = p_comment_id;
    update public.reports
    set status = 'resolved', resolved_by = auth.uid(), resolved_at = now()
    where comment_id = p_comment_id and status = 'pending';
  end if;
end;
$$;

-- 관리자: 이용 정지/해제
-- 정지를 풀 때 보호자 동의가 없는 만 14세 미만이면 active가 아니라 pending_guardian으로 되돌린다.
create function public.admin_set_suspension(p_user_id uuid, p_suspend boolean)
returns public.account_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status public.account_status;
begin
  if not private.is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'cannot_suspend_self' using errcode = '22023';
  end if;

  if p_suspend then
    v_status := 'suspended';
  else
    select case
        when p.age_group = 'child_u14' and pp.guardian_consented_at is null then 'pending_guardian'
        else 'active'
      end::public.account_status
      into v_status
    from public.profiles p
    join public.profile_private pp on pp.id = p.id
    where p.id = p_user_id;
  end if;

  update public.profiles set status = v_status where id = p_user_id;
  return v_status;
end;
$$;

-- 보호자 동의 확정. 서버(service_role)만 호출한다. 원문 토큰을 받아 해시로 비교한다.
create function public.confirm_guardian_consent(p_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_consent public.guardian_consents%rowtype;
begin
  select * into v_consent
  from public.guardian_consents
  where token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
  for update;

  if v_consent.id is null or v_consent.expires_at < now() then
    raise exception 'consent_token_invalid' using errcode = '22023';
  end if;
  if v_consent.consented_at is not null then
    return v_consent.user_id;
  end if;

  update public.guardian_consents set consented_at = now() where id = v_consent.id;
  update public.profile_private set guardian_consented_at = now() where id = v_consent.user_id;
  update public.profiles set status = 'active'
  where id = v_consent.user_id and status = 'pending_guardian';
  return v_consent.user_id;
end;
$$;
