import "server-only";
import { z } from "zod";

// 서버 전용 비밀 값. "server-only" 덕분에 클라이언트 컴포넌트에서 import하면 빌드가 실패한다.
// 값이 없어도 빌드는 되도록, 실제로 쓰는 순간에 검사한다.
const serverSchema = z.object({
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1),
  KAKAO_REST_API_KEY: z.string().min(1).optional(),
});

export function getServerEnv() {
  const parsed = serverSchema.safeParse({
    SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
    KAKAO_REST_API_KEY: process.env.KAKAO_REST_API_KEY,
  });
  if (!parsed.success) {
    const names = [...new Set(parsed.error.issues.map((issue) => issue.path.join(".")))].join(", ");
    throw new Error(`서버 환경 변수가 없거나 형식이 잘못되었습니다: ${names}. .env.example 참고.`);
  }
  return parsed.data;
}
