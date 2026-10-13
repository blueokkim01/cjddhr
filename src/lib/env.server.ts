import "server-only";
import { z } from "zod";

// 서버 전용 비밀 값. "server-only" 덕분에 클라이언트 컴포넌트에서 import하면 빌드가 실패한다.
const serverSchema = z.object({
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1),
  KAKAO_REST_API_KEY: z.string().min(1).optional(),
});

export const serverEnv = serverSchema.parse({
  SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
  KAKAO_REST_API_KEY: process.env.KAKAO_REST_API_KEY,
});
