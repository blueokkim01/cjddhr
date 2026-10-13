import { z } from "zod";

// 브라우저 번들에 들어가도 되는 값만 둔다. process.env.NEXT_PUBLIC_* 는 빌드 시 문자열로 치환되므로
// 동적 접근(process.env[key]) 없이 하나씩 적어야 한다.

const siteUrl = z.url().safeParse(process.env.NEXT_PUBLIC_SITE_URL);
// Netlify는 배포 주소를 URL 변수로 넣어 준다. 따로 설정하지 않아도 메타데이터 주소가 맞게 나온다.
const netlifyUrl = z.url().safeParse(process.env.URL);

export const SITE_URL = siteUrl.success
  ? siteUrl.data
  : netlifyUrl.success
    ? netlifyUrl.data
    : "http://localhost:3000";

const supabaseSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.url(),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1),
});

const supabaseEnv = supabaseSchema.safeParse({
  NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
});

// Supabase 값이 없어도 공개 페이지는 빌드·배포되도록, 검사는 Supabase를 실제로 쓰는 순간에 한다.
export const isSupabaseConfigured = supabaseEnv.success;

export function getSupabaseEnv() {
  if (!supabaseEnv.success) {
    const names = [...new Set(supabaseEnv.error.issues.map((issue) => issue.path.join(".")))].join(", ");
    throw new Error(
      `환경 변수가 없거나 형식이 잘못되었습니다: ${names}. ` +
        ".env.local 또는 배포 플랫폼(Netlify/Vercel)의 환경 변수 설정을 확인하세요. 목록은 .env.example 참고.",
    );
  }
  return supabaseEnv.data;
}
