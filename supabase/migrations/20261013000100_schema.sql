-- 독서 챌린지 MVP: 타입과 테이블
-- 권한은 20261013000300_rls.sql 에서 부여한다. 이 파일만 적용하면 anon/authenticated는 아무것도 할 수 없다.

create schema if not exists private;

-- ---------------------------------------------------------------------------
-- Enum
-- ---------------------------------------------------------------------------
create type public.age_group as enum ('child_u14', 'teen', 'adult');
create type public.user_role as enum ('user', 'admin');
create type public.account_status as enum ('pending_guardian', 'active', 'suspended');
create type public.goal_type as enum ('books', 'pages', 'days');
create type public.challenge_visibility as enum ('public', 'group_only');
create type public.target_age as enum ('all', 'teen_only', 'adult_only');
-- none: 정상 / pending_review: 신고 누적으로 자동 숨김, 관리자 검토 대기
-- hidden: 관리자가 숨김 유지 / restored: 관리자가 복구
create type public.review_status as enum ('none', 'pending_review', 'hidden', 'restored');
create type public.report_reason as enum (
  'spam', 'abuse', 'sexual', 'personal_info', 'self_harm', 'inappropriate', 'other'
);
create type public.report_status as enum ('pending', 'resolved');
create type public.reaction_kind as enum ('clap', 'fire', 'books', 'muscle', 'heart');

-- ---------------------------------------------------------------------------
-- 프로필
-- 다른 사용자에게 보일 수 있는 정보(profiles)와 본인만 보는 정보(profile_private)를 분리한다.
-- RLS는 행 단위라서, 한 테이블에 두면 출생연도·보호자 이메일까지 같이 노출된다.
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  nickname text not null
    check (nickname ~ '^[가-힣a-zA-Z0-9_]{2,20}$'),
  age_group public.age_group not null,
  role public.user_role not null default 'user',
  status public.account_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index profiles_nickname_lower_key on public.profiles (lower(nickname));

create table public.profile_private (
  id uuid primary key references public.profiles (id) on delete cascade,
  birth_year smallint not null check (birth_year between 1900 and 2100),
  guardian_email text check (guardian_email is null or guardian_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  guardian_consented_at timestamptz,
  created_at timestamptz not null default now()
);

-- 보호자 동의 토큰. 원문 토큰은 메일에만 담고 DB에는 SHA-256 해시만 둔다.
-- 정책을 두지 않으므로 service_role(서버 코드)만 접근한다.
create table public.guardian_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  guardian_email text not null,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null,
  consented_at timestamptz,
  created_at timestamptz not null default now()
);
create index guardian_consents_user_idx on public.guardian_consents (user_id);

-- ---------------------------------------------------------------------------
-- 그룹 (학급·북클럽)
-- ---------------------------------------------------------------------------
create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 40),
  description text not null default '' check (char_length(description) <= 300),
  owner_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  -- 0/O, 1/I/L 처럼 헷갈리는 문자는 제외한다. 학생이 칠판을 보고 옮겨 적기 때문.
  invite_code text not null unique check (invite_code ~ '^[A-HJ-KM-NP-Z2-9]{6}$'),
  created_at timestamptz not null default now()
);
create index groups_owner_idx on public.groups (owner_id);

create table public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index group_members_user_idx on public.group_members (user_id);

-- ---------------------------------------------------------------------------
-- 챌린지
-- ---------------------------------------------------------------------------
create table public.challenges (
  id uuid primary key default gen_random_uuid(),
  group_id uuid references public.groups (id) on delete cascade,
  title text not null check (char_length(title) between 2 and 60),
  description text not null default '' check (char_length(description) <= 2000),
  start_date date not null,
  end_date date not null,
  goal_type public.goal_type not null,
  goal_value integer not null check (goal_value between 1 and 100000),
  visibility public.challenge_visibility not null default 'public',
  target_age public.target_age not null default 'all',
  -- 비로그인 방문자는 challenge_members를 읽을 수 없으므로 참여자 수를 비정규화해 둔다.
  member_count integer not null default 0 check (member_count >= 0),
  created_by uuid default auth.uid() references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint challenges_period_check check (end_date >= start_date and end_date - start_date <= 366),
  constraint challenges_group_only_needs_group check (visibility = 'public' or group_id is not null)
);
create index challenges_visibility_dates_idx on public.challenges (visibility, start_date, end_date);
create index challenges_group_idx on public.challenges (group_id);

create table public.challenge_members (
  challenge_id uuid not null references public.challenges (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (challenge_id, user_id)
);
create index challenge_members_user_idx on public.challenge_members (user_id);

-- ---------------------------------------------------------------------------
-- 도서
-- ---------------------------------------------------------------------------
create table public.books (
  id uuid primary key default gen_random_uuid(),
  isbn text unique check (isbn ~ '^([0-9]{13}|[0-9]{9}[0-9X])$'),
  title text not null check (char_length(title) between 1 and 200),
  author text not null default '' check (char_length(author) <= 200),
  publisher text not null default '' check (char_length(publisher) <= 100),
  thumbnail_url text check (thumbnail_url is null or thumbnail_url ~ '^https://'),
  source text not null default 'manual' check (source in ('kakao', 'manual')),
  created_by uuid default auth.uid() references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 독서 인증
-- ---------------------------------------------------------------------------
create table public.reading_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  challenge_id uuid not null references public.challenges (id) on delete cascade,
  book_id uuid not null references public.books (id) on delete restrict,
  -- 클라이언트가 보낸 값은 트리거가 덮어쓴다(Asia/Seoul 기준 오늘).
  log_date date not null,
  page_from integer,
  page_to integer,
  pages_read integer not null check (pages_read between 0 and 5000),
  minutes integer check (minutes is null or minutes between 1 and 1440),
  comment text not null default '' check (char_length(comment) <= 200),
  is_finished boolean not null default false,
  image_path text not null unique,
  image_hash text not null check (image_hash ~ '^[0-9a-f]{64}$'),
  is_hidden boolean not null default false,
  review_status public.review_status not null default 'none',
  created_at timestamptz not null default now(),
  constraint reading_logs_one_per_day unique (user_id, challenge_id, log_date),
  constraint reading_logs_page_range_pair check ((page_from is null) = (page_to is null)),
  constraint reading_logs_page_range_valid check (
    page_from is null or (page_from >= 1 and page_to >= page_from and page_to <= 100000)
  )
);
create index reading_logs_challenge_feed_idx on public.reading_logs (challenge_id, created_at desc);
create index reading_logs_user_date_idx on public.reading_logs (user_id, log_date);
create index reading_logs_user_hash_idx on public.reading_logs (user_id, image_hash);
create index reading_logs_pending_review_idx on public.reading_logs (review_status)
  where review_status = 'pending_review';

-- ---------------------------------------------------------------------------
-- 응원·댓글
-- ---------------------------------------------------------------------------
create table public.reactions (
  reading_log_id uuid not null references public.reading_logs (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  kind public.reaction_kind not null,
  created_at timestamptz not null default now(),
  primary key (reading_log_id, user_id, kind)
);
create index reactions_user_idx on public.reactions (user_id);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  reading_log_id uuid not null references public.reading_logs (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 300),
  is_hidden boolean not null default false,
  review_status public.review_status not null default 'none',
  created_at timestamptz not null default now()
);
create index comments_log_idx on public.comments (reading_log_id, created_at);
create index comments_user_idx on public.comments (user_id);
create index comments_pending_review_idx on public.comments (review_status)
  where review_status = 'pending_review';

-- ---------------------------------------------------------------------------
-- 신고·차단
-- ---------------------------------------------------------------------------
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  reading_log_id uuid references public.reading_logs (id) on delete cascade,
  comment_id uuid references public.comments (id) on delete cascade,
  reason public.report_reason not null,
  detail text not null default '' check (char_length(detail) <= 300),
  status public.report_status not null default 'pending',
  resolved_by uuid references public.profiles (id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  constraint reports_single_target check (num_nonnulls(reading_log_id, comment_id) = 1)
);
-- 한 사람이 같은 대상을 여러 번 신고해서 자동 숨김 기준(3건)을 혼자 채우지 못하게 한다.
create unique index reports_unique_log on public.reports (reporter_id, reading_log_id)
  where reading_log_id is not null;
create unique index reports_unique_comment on public.reports (reporter_id, comment_id)
  where comment_id is not null;
create index reports_pending_idx on public.reports (status, created_at) where status = 'pending';

create table public.blocks (
  blocker_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_not_self check (blocker_id <> blocked_id)
);
create index blocks_blocked_idx on public.blocks (blocked_id);

-- ---------------------------------------------------------------------------
-- 배지
-- ---------------------------------------------------------------------------
create table public.badges (
  code text primary key,
  name text not null,
  description text not null,
  sort_order smallint not null default 0
);

create table public.user_badges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  badge_code text not null references public.badges (code) on delete cascade,
  -- 챌린지 완주 배지만 챌린지별로 여러 개 받을 수 있다.
  challenge_id uuid references public.challenges (id) on delete cascade,
  awarded_at timestamptz not null default now()
);
create unique index user_badges_unique on public.user_badges (user_id, badge_code, challenge_id) nulls not distinct;

insert into public.badges (code, name, description, sort_order) values
  ('first_log', '첫 인증', '처음으로 독서 인증을 남겼어요.', 1),
  ('streak_7', '7일 연속', '7일 연속으로 독서 인증을 했어요.', 2),
  ('streak_30', '30일 연속', '30일 연속으로 독서 인증을 했어요.', 3),
  ('first_finish', '첫 완독', '처음으로 책 한 권을 끝까지 읽었어요.', 4),
  ('challenge_complete', '챌린지 완주', '챌린지 목표를 달성했어요.', 5);

-- ---------------------------------------------------------------------------
-- 금칙어
-- ---------------------------------------------------------------------------
-- 띄어쓰기·특수문자를 끼워 넣는 우회("바 보", "바.보")를 막기 위해 정규화한 형태로 비교한다.
create function private.normalize_text(p_text text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select regexp_replace(lower(coalesce(p_text, '')), '[^가-힣ㄱ-ㅎㅏ-ㅣa-z0-9]', '', 'g')
$$;

create table public.banned_words (
  id bigint generated always as identity primary key,
  word text not null check (char_length(btrim(word)) between 1 and 50),
  normalized text generated always as (private.normalize_text(word)) stored,
  created_by uuid default auth.uid() references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint banned_words_normalized_not_empty check (normalized <> '')
);
create unique index banned_words_normalized_key on public.banned_words (normalized);
