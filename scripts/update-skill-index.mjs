#!/usr/bin/env node
// Update skills/index.json's entry for `process.env.SKILL` to match the
// current state of skills/<skill>/. Reads description from SKILL.md
// frontmatter (single-line scalar required) and recomputes files[] from
// disk listing.
//
// Called by .github/workflows/sync.yml after rsync drops new upstream
// content into skills/<skill>/. Run manually with `SKILL=<name> node
// scripts/update-skill-index.mjs`.

import { readFileSync, writeFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const skill = process.env.SKILL;
if (!skill) {
    throw new Error("SKILL env var is required");
}

const skillDir = join("skills", skill);
const indexPath = join("skills", "index.json");

// 1. Read SKILL.md frontmatter and recover the upstream description.
const md = readFileSync(join(skillDir, "SKILL.md"), "utf8");
const fm = md.match(/^---\r?\n([\s\S]*?)\r?\n---/);
if (!fm) {
    throw new Error(`SKILL.md for ${skill} has no YAML frontmatter`);
}
const fmLines = fm[1].split(/\r?\n/);
const descIdx = fmLines.findIndex((l) => l.startsWith("description:"));
if (descIdx === -1) {
    throw new Error(`SKILL.md for ${skill} has no description field`);
}

// Reject YAML folded (>) or block (|) scalars explicitly. The single-line
// description format is the contract; multi-line variants silently
// truncate the description in older parsers.
const descLine = fmLines[descIdx];
let description = descLine.replace(/^description:\s*/, "").trim();
if (description === ">" || description === "|" || description === ">-" || description === "|-") {
    throw new Error(
        `SKILL.md for ${skill} uses YAML folded/block scalar for description; only single-line strings are supported`,
    );
}

// Accumulate continuation lines (any line indented more than the description: line).
for (let i = descIdx + 1; i < fmLines.length; i++) {
    const next = fmLines[i];
    if (/^\w[\w-]*:/.test(next)) break;
    if (next.trim() === "") continue;
    if (!next.startsWith(" ") && !next.startsWith("\t")) {
        throw new Error(`SKILL.md for ${skill} description has malformed continuation line: ${next}`);
    }
    description += " " + next.trim();
}
if (
    (description.startsWith("\"") && description.endsWith("\"")) ||
    (description.startsWith("'") && description.endsWith("'"))
) {
    description = description.slice(1, -1);
}

// 2. Recompute files[] from disk: SKILL.md first, then references/*.md alphabetically.
const files = ["SKILL.md"];
const refsDir = join(skillDir, "references");
try {
    if (statSync(refsDir).isDirectory()) {
        const refs = readdirSync(refsDir)
            .filter((f) => f.endsWith(".md"))
            .sort();
        for (const f of refs) {
            files.push(`references/${f}`);
        }
    }
} catch (e) {
    if (e.code !== "ENOENT") {
        throw e;
    }
}

// 3. Patch the matching entry in skills/index.json (or append if missing).
const index = JSON.parse(readFileSync(indexPath, "utf8"));
const entry = index.skills.find((s) => s.name === skill);
if (entry) {
    entry.description = description;
    entry.files = files;
} else {
    index.skills.push({ name: skill, description, files });
}
writeFileSync(indexPath, JSON.stringify(index, null, 4) + "\n");
console.log(`updated skills/index.json: ${skill} (${files.length} files)`);
