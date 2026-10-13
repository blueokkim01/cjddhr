import { SITE_DESCRIPTION, SITE_NAME } from "@/lib/metadata";

// 3단계에서 랜딩 페이지(공개 챌린지 미리보기, 가입 유도)로 교체한다.
export default function LandingPage() {
  return (
    <main id="main" className="mx-auto flex w-full max-w-2xl flex-1 flex-col justify-center gap-4 p-6">
      <h1 className="text-3xl font-bold tracking-tight">{SITE_NAME}</h1>
      <p className="text-lg text-muted-foreground">{SITE_DESCRIPTION}</p>
    </main>
  );
}
