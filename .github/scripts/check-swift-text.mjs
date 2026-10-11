// Fails when a Swift string literal contains Japanese (kana, kanji, full-width forms). Tomo's words belong in
// the target pack (Resources/languages/<id>.json) and interface text in ui.<id>.json, so switching the language
// pair switches every word (docs/languages.md). A literal that isn't shown text (a debug label, a "？" being
// matched) can stay: end its line with `// text-ok: <why>`.
//
// Also fails when Swift writes a time of day (a `timeStyle`, `.hour()`, `style: .time`, `time: .shortened`, an
// `.hourAndMinute` picker or a format with hours in it) with no `tomoClockLocale` within a few lines: every time a
// learner sees is in the learner's language on the device's own 12- or 24-hour clock (#197). One that isn't a
// learner's time (a debug log, a drawing of the system's own clock) can stay: end its line with `// clock-ok: <why>`.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

process.chdir(fileURLToPath(new URL("../../", import.meta.url)));

const JAPANESE = /[぀-ヿ㐀-鿿＀-￯]/;
const LITERAL = /"(?:[^"\\]|\\.)*"/g;
const TIME_OF_DAY =
  /\btimeStyle\b|\.hour\(|style:\s*\.time\b|time:\s*\.(?:shortened|standard|complete)\b|\.hourAndMinute\b|(?:dateFormat\s*=|FromTemplate\()\s*"[^"]*[HhjkK]/;
const CLOCK_NEAR = 12; // lines either side: a formatter's locale, or a view's .environment(\.locale, …)
const files = execFileSync("git", ["ls-files", "--", "*.swift"], { encoding: "utf8" })
  .split("\n")
  .filter(Boolean);

const failures = [];
const clockFailures = [];
for (const path of files) {
  const lines = readFileSync(path, "utf8").split("\n");
  lines.forEach((line, index) => {
    const code = line.replace(/\/\/.*$/, "");
    if (!line.includes("// text-ok:")) {
      for (const literal of code.match(LITERAL) ?? []) {
        if (JAPANESE.test(literal)) failures.push(`${path}:${index + 1}: ${literal}`);
      }
    }
    if (TIME_OF_DAY.test(code) && !line.includes("// clock-ok:")) {
      const near = lines.slice(Math.max(0, index - CLOCK_NEAR), index + CLOCK_NEAR + 1);
      if (!near.some((l) => l.replace(/\/\/.*$/, "").includes("tomoClockLocale("))) {
        clockFailures.push(`${path}:${index + 1}: ${line.trim()}`);
      }
    }
  });
}

if (failures.length > 0) {
  failures.forEach((failure) => console.error(failure));
  console.error(
    "\nJapanese text in Swift. Put Tomo's words in the target pack (Resources/languages/<id>.json) and interface" +
      "\ntext in ui.<id>.json. If the literal isn't shown text, end the line with `// text-ok: <why>`.",
  );
}
if (clockFailures.length > 0) {
  clockFailures.forEach((failure) => console.error(failure));
  console.error(
    "\nA time of day written without tomoClockLocale (TomoGame.swift): use tomoTime, or give the formatter or the" +
      "\nview tomoClockLocale(<learner id>). If it isn't a time a learner sees, end the line with `// clock-ok: <why>`.",
  );
}
if (failures.length > 0 || clockFailures.length > 0) process.exit(1);
console.log(
  `${files.length} Swift files, no language-specific text in string literals, every time of day on tomoClockLocale.`,
);
