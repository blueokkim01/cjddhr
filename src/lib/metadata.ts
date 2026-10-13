import type { Metadata } from "next";

export const SITE_NAME = "함께읽기 챌린지";
export const SITE_DESCRIPTION =
  "친구, 학급, 독서 모임과 함께 매일 읽고 인증하는 독서 챌린지. 사진 한 장과 한 줄 감상으로 독서 습관을 만들어요.";

// 미성년자 게시물·프로필이 나올 수 있는 화면은 검색엔진에 노출하지 않는다.
export const NO_INDEX: Metadata["robots"] = {
  index: false,
  follow: false,
  nocache: true,
  googleBot: { index: false, follow: false, noimageindex: true },
};
