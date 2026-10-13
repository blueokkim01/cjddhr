-- 매년 1월 1일 00:05 KST(= 12월 31일 15:05 UTC)에 연령 그룹을 다시 계산한다.
-- pg_cron을 쓸 수 없는 환경(일부 로컬 테스트 DB)에서는 건너뛰고 경고만 남긴다.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('refresh-age-groups', '5 15 31 12 *', 'select private.refresh_age_groups()');
  else
    raise warning 'pg_cron is not available: schedule private.refresh_age_groups() manually';
  end if;
end $$;
