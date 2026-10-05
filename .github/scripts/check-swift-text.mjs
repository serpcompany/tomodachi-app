// Fails when a Swift string literal contains Japanese (kana, kanji, full-width forms). Tomo's words belong in
// the target pack (Resources/languages/<id>.json) and interface text in ui.<id>.json, so switching the language
// pair switches every word (docs/languages.md). A literal that isn't shown text (a debug label, a "？" being
// matched) can stay: end its line with `// text-ok: <why>`.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

process.chdir(fileURLToPath(new URL("../../", import.meta.url)));

const JAPANESE = /[぀-ヿ㐀-鿿＀-￯]/;
const LITERAL = /"(?:[^"\\]|\\.)*"/g;
const files = execFileSync("git", ["ls-files", "--", "*.swift"], { encoding: "utf8" })
  .split("\n")
  .filter(Boolean);

const failures = [];
for (const path of files) {
  readFileSync(path, "utf8")
    .split("\n")
    .forEach((line, index) => {
      if (line.includes("// text-ok:")) return;
      const code = line.replace(/\/\/.*$/, "");
      for (const literal of code.match(LITERAL) ?? []) {
        if (JAPANESE.test(literal)) failures.push(`${path}:${index + 1}: ${literal}`);
      }
    });
}

if (failures.length > 0) {
  failures.forEach((failure) => console.error(failure));
  console.error(
    "\nJapanese text in Swift. Put Tomo's words in the target pack (Resources/languages/<id>.json) and interface" +
      "\ntext in ui.<id>.json. If the literal isn't shown text, end the line with `// text-ok: <why>`.",
  );
  process.exit(1);
}
console.log(`${files.length} Swift files, no language-specific text in string literals.`);
