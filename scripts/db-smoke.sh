#!/usr/bin/env bash
# Docker 없이 마이그레이션을 검증한다: 임시 Postgres 클러스터 → Supabase 스텁 → 마이그레이션 → 스모크 테스트
# 사용법: npm run db:smoke   (PostgreSQL 15+ 서버 바이너리가 필요)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PG_BIN="${PG_BIN:-$(dirname "$(command -v pg_ctl 2>/dev/null || ls -d /usr/lib/postgresql/*/bin/pg_ctl | tail -1)")}"
PORT="${PG_SMOKE_PORT:-54329}"
WORK="$(mktemp -d)"
RUN_AS=()
if [ "$(id -u)" = "0" ]; then
  # initdb는 root로 실행할 수 없다.
  chown postgres "$WORK"
  RUN_AS=(runuser -u postgres --)
fi

cleanup() {
  "${RUN_AS[@]}" "$PG_BIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

"${RUN_AS[@]}" "$PG_BIN/initdb" -D "$WORK/data" -U postgres -A trust --locale=C.UTF-8 >/dev/null
"${RUN_AS[@]}" "$PG_BIN/pg_ctl" -D "$WORK/data" -o "-p $PORT -k $WORK -c listen_addresses=''" -l "$WORK/log" -w start >/dev/null

PSQL=(psql -X -q -v ON_ERROR_STOP=1 -h "$WORK" -p "$PORT" -U postgres -d postgres)
"${PSQL[@]}" -f "$ROOT/supabase/tests/stub/supabase_stub.sql"
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "apply $(basename "$f")"
  out="$("${PSQL[@]}" -f "$f" 2>&1)" || { echo "$out"; exit 1; }
  echo "$out" | grep -v "pg_cron is not available" || true
done
"${PSQL[@]}" -f "$ROOT/supabase/tests/stub/smoke.sql"
