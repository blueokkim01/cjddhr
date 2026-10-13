# 함께읽기 챌린지 (MVP)

청소년과 성인이 함께 쓰는 독서 챌린지 웹사이트. Next.js 16 (App Router) + Supabase.

> 진행 상황: **1단계 완료** (프로젝트 초기화, 폴더 구조, DB 마이그레이션·RLS·트리거·Storage 정책).
> 환경 변수, 로컬 실행, Vercel 배포 안내는 7단계에서 정리한다.

## 빠른 시작

```bash
npm install
cp .env.example .env.local      # 값 채우기
npm run db:start                # Docker 필요: 로컬 Supabase 실행 + 마이그레이션 적용
npm run dev
```

## 스크립트

| 명령 | 설명 |
| --- | --- |
| `npm run dev` / `build` | 개발 서버 / 프로덕션 빌드 |
| `npm run typecheck` / `lint` | 타입 검사 / ESLint |
| `npm test` | Vitest 단위 테스트 |
| `npm run test:e2e` | Playwright E2E (모바일·데스크톱) |
| `npm run db:reset` | 로컬 Supabase DB를 마이그레이션 + `seed.sql`로 재생성 |
| `npm run db:smoke` | Docker 없이 임시 Postgres에 마이그레이션을 적용하고 RLS 스모크 테스트 실행 |

## 폴더 구조

```
app/
  (public)/     랜딩, 공개 챌린지
  (auth)/       로그인, 가입, 보호자 동의 (noindex)
  (main)/       로그인 후 화면 (noindex)
  admin/        관리자 (noindex)
proxy.ts        Next.js 16의 미들웨어(구 middleware.ts). 세션 갱신·경로 보호
src/
  features/<기능>/{components,actions,queries,schemas}
  lib/supabase/ server.ts, client.ts, middleware.ts, admin.ts(service role, 서버 전용)
  lib/env.ts, env.server.ts   zod로 검증한 환경 변수
  types/database.ts           DB 타입 (마이그레이션과 짝)
supabase/
  migrations/   스키마 → 함수·트리거 → RLS → Storage → 스케줄
  tests/stub/   Docker 없는 검증용 Supabase 스텁과 스모크 테스트
```
