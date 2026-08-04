---
name: flutter-review
description: "Reviews Flutter code built on the FlutterSDK stack (magic framework + Wind UI) with a subagent as an independent second pair of eyes, then fixes what it finds. Resolves scope from the active work (uncommitted changes, else the branch diff), spawns fluttersdk:flutter-reviewer or fluttersdk:flutter-reviewer-deep, verifies every returned finding against the code before showing it, and applies approved fixes with a re-review. Checks magic compliance (bootstrap, IoC, controller/view/state, models, HTTP, validation, auth, routing), Wind UI compliance (dark pairing, states over interpolation, layout contracts, dead tokens, widget choice), correctness, OOP, style, and reuse. TRIGGER when: the user asks to review, audit, or get a second opinion on Flutter code; before shipping a feature in an app that depends on magic or fluttersdk_wind; after a refactor; when a change crosses controller, view, model, or route layers. DO NOT TRIGGER when: the project has no magic or fluttersdk_wind dependency, or the user wants the code written rather than reviewed."
when_to_use: "Any review, audit, or second-opinion request on Dart code in an app using magic or Wind: in-flight uncommitted work, a finished branch before a PR, a specific feature or path the user names, or a follow-up pass after fixes. Also when the user asks whether their controller, view, model, HTTP, validation, or auth code follows the framework properly."
argument-hint: "[paths|uncommitted|branch|feature name] [--deep] [--no-fix]"
---

# Flutter review

A review is worth running when a second reader would catch what the author cannot. That is the whole design here: the reading happens in a subagent with its own context, which never saw the conversation that produced the code, so it cannot inherit the author's assumptions about what the code does.

You orchestrate. You resolve what to review, spawn the reviewer, check its work, and carry the fixes. You do not do the reviewing yourself: reviewing your own recent edits in the same context is the failure this skill exists to avoid.

## 1. Resolve the scope

Take the first branch that applies:

1. **Arguments name paths or globs** (`lib/features/monitor/**`, two file paths, a feature name that maps to a directory): that is the scope.
2. **`git status --porcelain` shows uncommitted changes**: those files are the scope. This is the common case, and it is what "review my work" means while the work is in progress.
3. **The branch is ahead of its upstream or the default branch**: `git diff --name-only $(git merge-base HEAD @{u} 2>/dev/null || git merge-base HEAD main)...HEAD` is the scope.
4. **Nothing resolves**: ask what to review. Do not review the whole `lib/` tree on a guess; on a real app that produces a long report nobody reads.

Filter the resolved list to Dart sources. Drop generated files (`*.g.dart`, `*.freezed.dart`, `_previews.g.dart`), and say how many you dropped.

Confirm the project is on this stack before spawning anything: `pubspec.yaml` names `magic` or `fluttersdk_wind`. If it names neither, say so and stop; the rulebooks this review applies would be inventing rules for a project that never adopted them.

**Success criterion**: a concrete list of Dart files, shown to the user with its origin ("12 uncommitted files", "8 files ahead of `main`").

## 2. Pick the reviewer

| Reviewer | When |
|:--|:--|
| `fluttersdk:flutter-reviewer` | The default. A fix, a screen, a handful of files inside one layer. |
| `fluttersdk:flutter-reviewer-deep` | The change crosses layers (controller plus view plus model, or route plus middleware plus authorization), introduces a pattern the app will copy, or is a whole new feature or module. Also when a standard review came back clean and the user still thinks something is off. |

`--deep` forces the deep reviewer. Roughly: more than about 12 files, or files spanning three or more of controller / view / model / http / routes, is deep territory. Say which you picked and why, in one line.

**Success criterion**: the reviewer is chosen for a reason you stated, not by default.

## 3. Spawn it

One call, with the whole contract in the prompt: the resolved file list as absolute paths, the scope origin, the user's focus if they gave one, and the base ref when the scope came from a branch diff.

Give it everything it needs and nothing about your opinion of the code. A prompt that says "I think the controller is fine but check the view" gets a reviewer that agrees with you, which is worth nothing.

Do not review in parallel with the subagent. Wait for it.

**Success criterion**: the reviewer returns a report with a verdict, or reports `NONE`.

## 4. Verify before you believe it

The report is a claim, not a finding. It came from a model that read files in isolation and is as fluent when it is wrong as when it is right. Before anything reaches the user:

- **Open each cited `file:line`.** The line says what the finding says it says, or the finding is dropped.
- **Re-check the rule.** A finding that cites a Core Law, a token, or a facade method is only as good as that citation: confirm the rule exists in the skill it names. Wind tokens change between releases and a plausible-sounding token name is the easiest thing for a reviewer to invent.
- **Test the failure scenario.** Trace it in the code. If the scenario cannot happen, the finding is wrong even when the rule is real.
- **Watch for the disproof the reviewer missed**: the `dark:` peer on the next line, the guard three lines up, the validator that already ran, the theme override that makes the token resolve.

Drop what fails. Say how many you dropped and why, in one line: a review that silently passes through 9 findings when 3 were wrong teaches the user to distrust all 9.

**Success criterion**: every finding you present has been checked against the code by you, not only by the subagent.

## 5. Report

If the `ReportFindings` tool is available, report through it: one entry per verified finding, most severe first, each with the file, the one-sentence summary, the concrete failure scenario, and a category slug (`magic-compliance`, `wind-compliance`, `correctness`, `oop`, `style`, `reuse`). Do not also print the same findings as prose.

Otherwise print them grouped by stage, in the shape the reviewer used.

Either way, state the verdict and the two counts that matter: findings presented, findings dropped in verification.

When the verified set is empty, say so plainly and stop. A clean review is a result.

## 6. Fix

Skip this step entirely when `--no-fix` is passed, or when the user asked for a review rather than a fix.

Otherwise, for each finding in severity order:

1. **Show the fix before making it.** The current lines, the replacement, and one sentence on why it is the fix the rule asks for.
2. **Ask once, for the batch.** Group the mechanical fixes (a missing `dark:` peer, a `response.body` to `response.data`) into one approval. Ask separately for anything that changes behavior, moves a call between lifecycle methods, or touches more than a few lines.
3. **Apply only inside the reviewed scope.** A fix that requires touching a file outside it is a finding to report, not a change to make quietly.
4. **Never fix by weakening the check.** Do not silence the analyzer, delete the assertion, or loosen the type. If the honest fix is bigger than the review, say so and leave it.

After applying: run what the project runs (`dart analyze` on the touched files, `dart format --set-exit-if-changed`, and the test suite if the change touched logic), then re-spawn the same reviewer on the same scope for one confirmation pass.

Stop after two fix rounds. A third round means the findings are arguing with each other or the design is wrong, and that is a conversation with the user, not another pass.

**Success criterion**: the analyzer is clean on the touched files, the confirmation review returns no new CRITICAL finding, and the user saw every change before it was made.

## Rules that hold throughout

- **The reviewer is read-only.** It reports; you fix. Never ask the subagent to edit, and never present its report as finished work.
- **Rulebooks over memory.** Every framework claim traces to the `magic-framework` or `wind-ui` skill, or to `${CLAUDE_PLUGIN_ROOT}/references/dart-style-core.md`. If you cannot find the rule, the finding does not ship.
- **Scope discipline.** Pre-existing issues outside the change are not this review's business unless the change made them reachable.
- **No padding.** Neither you nor the reviewer invents a finding to justify the run.

## When you need details

- The stages, the severity and confidence rule, the not-a-finding list, and the report shape: `${CLAUDE_PLUGIN_ROOT}/references/flutter-review-core.md`.
- The style rules applied when no personal style skill is loaded: `${CLAUDE_PLUGIN_ROOT}/references/dart-style-core.md`.
- The framework rules themselves: the `magic-framework` and `wind-ui` skills, which the reviewer loads at startup.
