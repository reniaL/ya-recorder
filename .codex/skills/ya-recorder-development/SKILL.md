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
2. Read documents according to the task's scope. When selecting the next work item, assessing overall MVP status, or changing product scope, read all of these documents. For an explicitly selected local fix, read `docs/development-progress.md` and the relevant requirements and architecture sections; reuse documents already read in this session if they have not changed. For a documentation or skill-only edit, read only the material needed for that edit:
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
- Do not report a device-only criterion as verified without device evidence. Keep its status as `进行中` and record the remaining verification in the progress document.
- Fix failures caused by the change before handoff. If an external limitation prevents a check, report the limitation and keep the status accurate.

### Choose validation by impact

Before running checks, select the smallest sufficient validation set from the affected behavior, dependencies, and acceptance criteria. Judge risk by impact, not by the number of changed lines. Honor an explicit user request for full regression, a build, or a device check.

| Change | Default validation | Android debug APK |
| --- | --- | --- |
| Documentation, skill instructions, or comments only | Review content, links, and `git diff --check`; validate skill structure when editing a skill. Skip Flutter analysis and tests. | Skip. |
| Local UI text, colors, spacing, or layout | `flutter analyze` and relevant widget tests, including applicable layout/accessibility criteria. | Usually skip. |
| Business logic confined to one module | `flutter analyze` and tests for the module and directly affected callers. | Usually skip. |
| Shared interfaces, cross-module behavior, database migrations, recording save or recovery guarantees | Full `flutter analyze` and `flutter test`, including regression coverage for the affected guarantees. | Build when platform integration is affected. |
| Android native code, plugins, dependencies, Manifest, Gradle, JNI, or CMake | Relevant native checks and affected tests; use full Flutter analysis and tests when application dependencies or cross-layer behavior are affected. | Build the affected application or prototype. |

- Run targeted tests by file or directory, for example `flutter test test/playback/`. Include tests for directly affected callers and UI; a directory boundary alone does not establish sufficient coverage. Inspect the existing tests before selecting them.
- If only `android/mp3-prototype` changes and no production application or shared code is affected, run the prototype's relevant native tests and build checks. Skip the production Flutter suite and APK build. Select encoding, ABI, alignment, and long-recording checks according to what changed and the prototype's acceptance criteria.
- Expand to full analysis and tests when the impact cannot be bounded or targeted checks expose cross-module problems. Add a build if compilation or platform integration is in question. Fix change-related failures before handoff.
- Use targeted checks during implementation. Run required full regression once the final code is ready. Reuse passing results from this session only when the checked code, dependencies, configuration, and relevant environment remain unchanged; a later documentation-only update does not require rerunning code checks. After further code edits, rerun affected checks and any full regression required by the final change.
- Preserve Flutter and Gradle incremental caches. Do not routinely run `flutter clean`, delete build caches, or reinstall dependencies; do so only to resolve evidence of stale artifacts or a specific build/dependency problem.
- Use a connected Android device for criteria requiring real recording, permission, playback, interruption, or performance behavior. Smaller automated check sets do not waive device acceptance criteria.
- Report the checks actually run, their results, and why other checks were skipped. Distinguish targeted test success from full regression and build success from device verification.

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
