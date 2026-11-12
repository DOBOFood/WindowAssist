// Checks that every translation file has exactly the same keys as English.
// Usage: node tools/check_i18n.js
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const webDir = path.join(__dirname, "..", "web", "js");
const sandbox = { window: {} };
vm.createContext(sandbox);

const load = (file) => {
  vm.runInContext(fs.readFileSync(path.join(webDir, file), "utf8"), sandbox, { filename: file });
};

load("i18n.js");
load("languages.js");

const files = fs.readdirSync(webDir).filter((file) => /^i18n\..+\.js$/.test(file));
files.forEach(load);

const dictionaries = sandbox.window.I18N || {};
const languages = sandbox.window.LANGUAGES || [];
const baseKeys = Object.keys(dictionaries.en || {});
let failed = false;

if (!baseKeys.length) {
  console.error("FAIL: English dictionary is empty");
  process.exit(1);
}

for (const language of languages) {
  if (!dictionaries[language.code]) {
    console.error(`FAIL: language "${language.code}" is listed but has no dictionary`);
    failed = true;
  }
}

for (const [code, dictionary] of Object.entries(dictionaries)) {
  const missing = baseKeys.filter((key) => !(key in dictionary));
  const extra = Object.keys(dictionary).filter((key) => !(key in dictionaries.en));
  if (missing.length || extra.length) {
    failed = true;
    console.error(`FAIL [${code}] missing: ${missing.join(", ") || "-"}; extra: ${extra.join(", ") || "-"}`);
  }
}

if (failed) {
  process.exit(1);
}

console.log(
  `OK: ${Object.keys(dictionaries).length} languages, ${baseKeys.length} keys each (${Object.keys(dictionaries).join(", ")})`
);
