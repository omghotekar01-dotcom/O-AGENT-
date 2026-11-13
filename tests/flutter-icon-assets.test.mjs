import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const pubspec = readFileSync(new URL("../apps/flutter/pubspec.yaml", import.meta.url), "utf8");

test("Flutter explicitly bundles the CupertinoIcons font used by iOS-style UI", () => {
  assert.match(pubspec, /^  cupertino_icons: \^1\.0\.8\s*$/m,
    "Without the package dependency the mobile UI renders missing-glyph boxes");
  assert.match(pubspec, /^  uses-material-design: true\s*$/m);
});
