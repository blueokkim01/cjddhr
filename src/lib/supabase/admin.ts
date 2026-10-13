import "server-only";
import { createClient } from "@supabase/supabase-js";
import { getSupabaseEnv } from "@/lib/env";
import { getServerEnv } from "@/lib/env.server";
import type { Database } from "@/types/database";

// RLS를 우회한다. 보호자 동의 처리처럼 사용자 세션이 없는 서버 작업에만 쓰고,
// 호출하는 쪽에서 권한을 먼저 확인해야 한다.
export function createAdminClient() {
  const env = getSupabaseEnv();
  return createClient<Database>(
    env.NEXT_PUBLIC_SUPABASE_URL,
    getServerEnv().SUPABASE_SERVICE_ROLE_KEY,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}
