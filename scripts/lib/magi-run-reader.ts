// scripts/lib/magi-run-reader.ts
// MAGI run ディレクトリ配下の normalized-v2.json を読み込むための小さなヘルパー。

import * as fs from "fs";
import * as path from "path";

export interface NormalizedFinding {
  persona: string;
  path: string;
  line: number | null;
  headline: string;
  body: string;
}

export async function loadFindings(runDir: string): Promise<NormalizedFinding[]> {
  const file = path.join(runDir, "normalized-v2.json");
  const raw = await fs.promises.readFile(file, "utf-8");
  return JSON.parse(raw);
}

export function findingsByPersona(findings: NormalizedFinding[]): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const f of findings) {
    counts[f.persona] = (counts[f.persona] || 0) + 1;
  }
  return counts;
}

export function grepSource(pattern: string, dir: string): string {
  const { execSync } = require("child_process");
  return execSync(`grep -rn "${pattern}" ${dir}`).toString();
}
