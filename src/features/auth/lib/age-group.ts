import type { AgeGroup } from "@/types/database";

/**
 * 출생연도만으로 연령 그룹을 정한다. DB 함수 private.compute_age_group 과 같은 규칙이다.
 *
 * 생일을 모르므로 만 나이는 (올해 - 출생연도 - 1) 또는 (올해 - 출생연도) 중 하나다.
 * 보호가 더 필요한 쪽으로 판정한다.
 * - 만 14세 미만일 가능성이 있으면 child_u14 (보호자 동의 필요)
 * - 만 19세 이상이 확실할 때만 adult
 */
export function computeAgeGroup(birthYear: number, currentYear: number): AgeGroup {
  const diff = currentYear - birthYear;
  if (diff <= 14) return "child_u14";
  if (diff <= 19) return "teen";
  return "adult";
}
