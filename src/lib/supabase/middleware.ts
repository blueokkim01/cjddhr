import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { getSupabaseEnv, isSupabaseConfigured } from "@/lib/env";
import type { Database } from "@/types/database";

// proxy.ts에서 호출한다. 만료된 액세스 토큰을 갱신해 쿠키에 다시 쓰고,
// 확인된 사용자 id를 돌려준다(경로 보호는 2단계에서 이 값을 사용).
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  // Supabase를 아직 연결하지 않았으면 로그인 자체가 불가능하므로 갱신할 세션도 없다.
  if (!isSupabaseConfigured) {
    return { response, userId: null };
  }
  const env = getSupabaseEnv();

  const supabase = createServerClient<Database>(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet, headers) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options),
          );
          Object.entries(headers).forEach(([key, value]) => response.headers.set(key, value));
        },
      },
    },
  );

  // getSession()은 쿠키 값을 검증 없이 믿으므로 쓰지 않는다. getClaims()는 JWT 서명을 검증한다.
  const { data } = await supabase.auth.getClaims();
  const userId = data?.claims.sub ?? null;

  return { response, userId };
}
