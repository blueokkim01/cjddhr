import type { MetadataRoute } from "next";
import { SITE_URL } from "@/lib/env";

// 공개 영역만 색인을 허용한다. 각 페이지의 noindex 메타 태그와 함께 이중으로 막는다.
export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: ["/", "/challenges"],
      disallow: ["/dashboard", "/admin", "/groups", "/login", "/signup", "/challenges/*/feed", "/challenges/*/verify", "/api/"],
    },
    sitemap: `${SITE_URL}/sitemap.xml`,
  };
}
