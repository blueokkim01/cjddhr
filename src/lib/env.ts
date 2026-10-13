import { z } from "zod";

// 브라우저 번들에 들어가도 되는 값만 둔다. process.env.NEXT_PUBLIC_* 는 빌드 시 문자열로 치환되므로
// 동적 접근(process.env[key]) 없이 하나씩 적어야 한다.
const publicSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.url(),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1),
  NEXT_PUBLIC_SITE_URL: z.url().default("http://localhost:3000"),
});

const parsed = publicSchema.safeParse({
  NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  NEXT_PUBLIC_SITE_URL: process.env.NEXT_PUBLIC_SITE_URL,
});

if (!parsed.success) {
  // 배포 로그에서 원인을 바로 알 수 있도록 빠진 변수 이름을 그대로 보여준다.
  const names = [...new Set(parsed.error.issues.map((issue) => issue.path.join(".")))].join(", ");
  throw new Error(
    `환경 변수가 없거나 형식이 잘못되었습니다: ${names}. ` +
      ".env.local 또는 배포 플랫폼(Netlify/Vercel)의 환경 변수 설정을 확인하세요. 목록은 .env.example 참고.",
  );
}

export const publicEnv = parsed.data;
