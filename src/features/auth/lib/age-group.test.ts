import { describe, expect, it } from "vitest";
import { computeAgeGroup } from "./age-group";

describe("computeAgeGroup", () => {
  it.each([
    [2014, "child_u14"],
    // 2012년생은 2026년에 만 13세 또는 14세 → 보수적으로 child_u14
    [2012, "child_u14"],
    [2011, "teen"],
    [2007, "teen"],
    // 2006년생은 만 19세 또는 20세 → 성인 확정
    [2006, "adult"],
    [1980, "adult"],
  ] as const)("%i년생은 2026년에 %s", (birthYear, expected) => {
    expect(computeAgeGroup(birthYear, 2026)).toBe(expected);
  });
});
