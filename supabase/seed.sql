-- 로컬 개발용 시드. 운영 DB에는 적용하지 않는다.
-- 금칙어 예시(실제 목록은 관리자 페이지에서 관리)
insert into public.banned_words (word) values
  ('바보'),
  ('멍청이')
on conflict do nothing;
