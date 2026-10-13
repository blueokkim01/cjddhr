import type { Metadata } from "next";
import { NO_INDEX } from "@/lib/metadata";

// 로그인 후 화면에는 미성년자 게시물이 나올 수 있으므로 전체를 noindex로 둔다.
export const metadata: Metadata = { robots: NO_INDEX };

export default function MainLayout({ children }: { children: React.ReactNode }) {
  return children;
}
