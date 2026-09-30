---
name: ya-recorder-development
description: Assess and advance the 丫丫录音 Flutter MVP using its product, architecture, and progress documents. Use when asked to assess implementation status, deliver the next scoped feature, verify it, update progress, and commit the work.
metadata:
  short-description: Advance and verify 丫丫录音 MVP work
---

# 丫丫录音开发

Use this skill for work in the 丫丫录音 repository. Treat the product documents and the checked-out code as complementary evidence: documents define intended scope and acceptance criteria; code and validation show the implemented state.

## Assess the project first

1. Inspect `git status --short` before editing. Preserve unrelated dirty changes and do not stage them.
2. Read these documents before selecting or reporting a work item:
   - `docs/product/feature-list.md`
   - `docs/product/user-flows.md`
   - `docs/product/ui-interaction-design.md`
   - `docs/architecture/recording-lifecycle.md`
   - `docs/development-progress.md`
3. Inspect the relevant implementation and tests. Reconcile differences explicitly: implementation alone is not proof that an item meets its acceptance criteria.

Use an item explicitly selected by the user when one is given. Otherwise select the next dependency-ready MVP item from the recommended order in `docs/development-progress.md` that still requires implementation work. Skip items whose implementation is complete and whose only remaining condition is Android device verification; do not use such items as the turn's work item solely to repeat automated checks or report the absent device. Keep a turn focused on one cohesive item; do not expand into adjacent features merely because they share code.

## Implement and verify

- Follow the existing separation between Flutter UI/business code, platform integration, and local storage. Preserve the recording lifecycle's save and failure guarantees.
- Add or update automated tests for new decision logic and user-visible behavior where practical.
- Run `flutter analyze` and `flutter test` after implementation. Build an Android debug APK when Android/plugin changes make that a useful compilation check. Use a connected Android device for criteria that require real recording, permission, playback, or interruption behavior.
- Do not report a device-only criterion as verified without device evidence. Keep its status as `进行中` and record the remaining verification in the progress document.
- Fix failures caused by the change before handoff. If an external limitation prevents a check, report the limitation and keep the status accurate.

## Synchronize progress

Update `docs/development-progress.md` in the same change whenever the item is started, its implementation state changes, or validation adds material evidence.

- Set `已完成` only when its stated acceptance criteria and required automated or device validation are satisfied.
- Update the item's note with concrete evidence and remaining risks.
- Keep the last-updated date, overview counts, and current-stage summary consistent with the item rows.
- Do not change `docs/product/feature-list.md` unless the MVP scope itself changes.

## Commit the completed work

After verification and documentation updates:

1. Review the scoped diff and run `git diff --check`.
2. Stage only files changed for this work item, including its progress-document update. Leave unrelated user changes unstaged.
3. Create one concise conventional commit, for example `feat(playback): add seek controls`.
4. Report the commit hash, validation results, documentation status, and any verification still pending.

Do not commit if the user asks only for assessment or documentation updates, or if there is no scoped change to commit.
