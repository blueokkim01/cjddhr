import type { Metadata } from "next";
import { NO_INDEX } from "@/lib/metadata";

export const metadata: Metadata = { robots: NO_INDEX };

export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return children;
}
