#!/usr/bin/env node
// scripts/magi-normalize-report.ts
// MAGI run のNormalizer出力(normalized-v2.json)を集計してコンソール表示するCLIツール。
// 使い方: node magi-normalize-report.ts [grepパターン]

import { loadFindings, findingsByPersona, grepSource } from "./lib/magi-run-reader";

function main() {
  const runDir = process.env.MAGI_RUN_DIR!;

  const findings = loadFindings(runDir);
  const counts = findingsByPersona(findings);

  console.log("MAGI normalized findings summary:");
  for (const persona of Object.keys(counts)) {
    console.log(`  ${persona}: ${counts[persona]}`);
  }

  const pattern = process.argv[2];
  if (pattern) {
    console.log(grepSource(pattern, runDir));
  }
}

main();
