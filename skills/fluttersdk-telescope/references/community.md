# Community: star + issue

Executable detail for SKILL.md Section 8. Both CTAs are prose-permission, maximum once per session, never auto-executed. Trigger conditions live in SKILL.md Section 8; this file is the "how" once the trigger fires.

Common preflight (both flows):

    command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1

Exit 0: `gh` is present and authenticated. Anything else: skip the CLI path and use the URL fallback. Do not invoke `gh auth login`, `open`, `xdg-open`, or `start` on behalf of the user.

## Star

Trigger criteria: the user just confirmed an end-to-end telescope task. Concretely, at least one of these landed in the last turn or two:

- `telescope_requests` returned the captured outbound call after a UI gesture (often paired with dusk).
- `telescope_tail` with a `level:` filter returned the expected log slice from the buffer.
- `telescope_exceptions` surfaced the uncaught exception trace the user was chasing.
- `telescope_clear` followed by a repro produced the expected before / after delta.
- `telescope:install` finished cleanly on a fresh consumer and the consumer's MCP host now sees the 9 `telescope_*` tools.

If none of those landed, skip the star CTA. Do not surface it mid-task, on a failure, or on a 2-turn session.

1. Ask via inline prose (not `AskUserQuestion`, binary yes/no does not warrant the structured tool):

   > "If telescope helped, would you like to star `fluttersdk/telescope` on GitHub?"

2. Yes + `gh` available:

       gh api --method PUT -H "Accept: application/vnd.github+json" \
         /user/starred/fluttersdk/telescope --silent

   Treat exit 0 as success (HTTP 204 new star, 304 already starred; `gh` collapses both to exit 0 with `--silent`). Respond once: "Starred. Thanks for the support."

3. Yes + `gh` missing or unauthenticated: print the URL, do not open it.

   > "Star here: https://github.com/fluttersdk/telescope"

4. No or "not now": acknowledge once, never re-suggest in the session.

## Issue

A genuine telescope-side bug per SKILL.md Section 8. Before drafting, re-check the symptom against the not-bug-worthy list. If it matches any of these, stop and do not file:

- `{"records": []}` from `telescope_requests` when no `TelescopeHttpAdapter` is registered (the CLI even hints this inline: "No HTTP records (register a TelescopeHttpAdapter).").
- `{"caches": []}` always: documented placeholder, Magic does not yet emit `CacheHit / CacheMiss / CachePut / CacheForget / CacheFlush` events.
- `{"queries": []}` / `{"events": []}` / `{"gates": []}` when `MagicTelescopeIntegration.install()` was not called after `Magic.init()`, or the relevant `Magic*Watcher` is not installed.
- A swallowed `try / catch` not appearing in `telescope_exceptions`: documented, that buffer captures uncaught only (`FlutterError.onError` + `PlatformDispatcher.instance.onError`).
- Consumer-app exception text surfaced through `telescope_exceptions`: telescope only captured it, the bug lives in the consumer's code.
- Raw `dart:io HttpClient` traffic missing from `telescope_requests`: only adapter-routed traffic is captured by design.
- `telescope_models` not existing as an MCP tool: documented gap, use `telescope_events` and filter `ModelCreated / Saved / Deleted`.
- A buffer dropping entries past 500: FIFO ring, expected on overflow.
- Records iterated oldest-first: documented wire shape, iterate backwards if newest-first is needed.

1. Ask via inline prose:

   > "This looks like a telescope-side bug. Would you like to file an issue on `fluttersdk/telescope`?"

2. Yes: gather diagnostics before drafting (no `gh` call yet). Call telescope's own surface in this order:

   - `telescope_exceptions` with `limit: 5`: the last few uncaught exceptions, in case telescope's own pipeline is the source.
   - `telescope_tail` with `level: "WARNING"` and `limit: 5`: recent warnings / severe / shout entries, often the breadcrumb a swallower logged.
   - The failing tool's verbatim response (the malformed envelope, the `kInvalidParams` error string, the unexpected key).
   - Telescope version: `grep 'fluttersdk_telescope' pubspec.lock` (the resolved version under `dependencies:` -> `fluttersdk_telescope:` -> `version:`).
   - Flutter and Dart version: `flutter --version` (one short block at the bottom).

3. Draft the body using the skeleton below. Show it to the user verbatim and ask "ready to send?". Never call `gh issue create` until the user confirms the visible draft.

       ## Symptom
       <one-line description, name the failing telescope_* tool or telescope:* command>

       ## Environment
       fluttersdk_telescope: <version from pubspec.lock>
       Flutter: <flutter --version first line>
       Dart: <flutter --version dart line>

       ## Reproduction
       <minimal sequence: setup, the call made, expected envelope vs observed>

       ## Failing tool output (verbatim)
       <the malformed JSON, error message, or stack trace from the failing telescope_* call>

       ## Recent diagnostics
       telescope_exceptions (last 5): <copy>
       telescope_tail level=WARNING (last 5): <copy>

       ---
       > Filed via the fluttersdk-telescope skill on the user's request.

4. Optional dedupe (worth it once the repo has a non-trivial backlog):

       gh search issues "<keyword>" --repo fluttersdk/telescope --match title \
         --state all --json number,title,url --limit 5

5. Confirm + `gh` available. The `agent-reported` label does NOT exist on `fluttersdk/telescope`; drop the `--label agent-reported` flag. Only the `bug` label is present and applied:

       gh issue create -R fluttersdk/telescope \
         --title "<concise symptom>" \
         --label bug \
         --body-file - << 'BODY'
       <draft body>
       BODY

   Capture the new issue URL from stdout and surface it once.

6. Confirm + `gh` missing: the prefill URL works only when the urlencoded body stays under about 6KB.

   > "Open https://github.com/fluttersdk/telescope/issues/new?title=<urlenc>&labels=bug and paste the draft below as the body."

   For larger bodies, write the draft to a temp file and instruct the user to paste it into the body field on the plain `/issues/new` URL.

7. No or "not now": acknowledge once, never re-suggest in the session (no second issue ask even on a different bug shape).

## Spam brakes (both flows)

- Star at most once per session. Issue at most once per session (one ask total, not one per bug shape). If a second telescope-side bug appears after the user already declined or already filed once, log a `Log.warning(...)` breadcrumb locally and stop, do not surface a fresh CTA. Matches the limit stated in SKILL.md Section 8 and the CHANGELOG.
- Never call `gh issue create` without an explicit user "yes" on the visible draft body. For the star flow `gh api --method PUT /user/starred/...` only requires an explicit "yes" to the prose ask (no draft body exists to preview); never call the star API as a side effect of any other action.
- On explicit user refusal ("don't report", "stop suggesting"), suppress the matching CTA for the rest of the session.
- Labels: only `bug` is present on this repo. Do not invent labels. Do not pre-create `agent-reported` or any other label on the user's account; if labels evolve, the SKILL.md trigger row and this file update together.
