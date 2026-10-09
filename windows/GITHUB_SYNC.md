# MyGitea2 GitHub sync — first controlled test

This module lives under `windows/` and does not change upstream Gitea source, Gitea's configuration, or the original `E:\MyGitea` installation.

## Buttons

- **Keys:** Saves a GitHub personal access token and a MyGitea2 API token under `%LOCALAPPDATA%\MyGitea2\keys.dpapi.json`, encrypted by Windows DPAPI for the current Windows user. Neither token is committed to GitHub.
- **Sync GitHub:** Read-only preview of repos owned by the authenticated GitHub user; compares repository names against repos belonging to the authenticated MyGitea2 user. This does not import on preview.
- **Import only selected repository:** Explicitly submits one migration using Gitea's native `POST /api/v1/repos/migrate` API; never a bulk import.
- **Auto Refresh:** Client-side tab reload every minute while enabled and tab visible; avoid editing forms while enabled.
- **Stop Gitea:** Stops only MyGitea2's executable.

## Before first test

Create a GitHub token with read access to repositories (including private repos if desired). Create a MyGitea2 access token in user Settings > Applications with appropriate repository write and user read permissions. Enter these **only in the local Keys form**, never in chat, source code, or Gitea `app.ini`.

After pulling changes, parse-check both `windows/MyGitea-Control.ps1` and `windows/MyGitea-Sync.ps1`, then restart the launcher and reload the Chrome extension in the dedicated MyGitea2 profile.

## Acceptance gates

1. **PASS (user-confirmed 2026-10-09):** Keys form reported saved successfully after opening MyGitea2's dedicated Chrome profile. Actual decryption and API permissions are not yet independently tested. Never print tokens in logs or commit them to source control.
2. Preview shows correct GitHub username and MyGitea2 username, repo counts, and skips current names.
3. Import one harmless, small test repo explicitly.
4. Verify repository contents and migration status in the MyGitea2 UI.
5. Only after these pass, plan optional bulk import / startup sync.

## Current limitations

- No bulk import or startup sync yet.
- Looks at repositories owned by the authenticated GitHub user (not organization-owned repos).
- Name collision means skip; it does not refresh existing repository contents.
- Windows UI Keys-save flow: **user-reported PASS** on 2026-10-09. Sync preview, API token validation, and repository import remain **NOT TESTED**.

## Windows checkpoint: Keys save PASS — 2026-10-09

**Observed:** The toolbar initially displayed `Save failed: No response from launcher` and the encrypted file was absent. After opening the dedicated MyGitea2 Chrome profile using the command below and continuing from that profile, the user reported **Keys saved**. This confirms the UI save milestone from the user's report; the precise underlying cause of the earlier no-response message has not been proven.

To open the **correct MyGitea2 Chrome profile** (not regular Chrome), run in PowerShell:

```powershell
Start-Process "chrome.exe" -ArgumentList @(
    "--user-data-dir=`"$env:LOCALAPPDATA\MyGitea2\ChromeProfile`"",
    "--new-window",
    "chrome://extensions"
)
```

In that window, check **MyGitea2 Local Controls** is enabled; to inspect errors click its **service worker** link and select Console. Chrome extensions installed in a different profile are not necessarily present in MyGitea2. Reload the extension there after a Git pull, and refresh the MyGitea2 dashboard.

**Never paste or commit GitHub/Gitea API keys.** DPAPI-backed store is local to the Windows user at `%LOCALAPPDATA%\MyGitea2\keys.dpapi.json`.

**Next safe test:** Click **Sync GitHub** once and inspect **preview only**; verify the GitHub account name and repo counts. Do not press **Import only selected repository** until preview passes. Original `E:\MyGitea` remains protected.

## Preview list regression — 2026-10-09

- **Observed FAIL:** GitHub token and MyGitea2 token both authorized; Sync GitHub preview displayed **1 repository** while the single dropdown option contained many comma-separated `Sadusor/...` names. No import was performed.
- **Root cause identified in code:** Windows PowerShell API response arrays could be wrapped as one nested array; the preview treated that array as one repository object and interpolated all `full_name` fields together.
- **Fix:** `windows/MyGitea-Sync.ps1` expands nested arrays for GitHub and Gitea listings, validates each `owner/repo` item, and refuses an invalid preview before any import.
- **Status:** Committed; **NOT YET TESTED on Windows**. Next test: stop the MyGitea2 *launcher* safely, pull changes, parse-check scripts, restart launcher, use Sync GitHub for **preview only**. Expected: multiple distinct dropdown options and sensible repository count. Do not click Import until verified.

## Bulk import UI update — 2026-10-09

- Preview list and token authentication were user-reported working.
- Added **Import ALL missing repositories** to the Chrome toolbar. The user must confirm before any import.
- Imports are submitted **sequentially** (one API migration request per missing repository). The UI shows per-repository accepted/failed results and provides **Cancel remaining imports**; cancellation takes effect after the current request.
- Existing destination repository names are excluded by the preview and rechecked via `Import-SyncOne`. This is **migration**, not background mirror sync of already imported repositories.
- Auto Refresh is switched **OFF** during bulk execution to avoid reloading mid-operation. Keep the Chrome app and launcher open until it finishes; closing/reloading can interrupt the sequence.
- **Important:** A successful API response means the migration request was accepted, not that all contents were verified. Check repositories in MyGitea2 after completion.
- **Status:** Committed to GitHub; bulk import remains **UNTESTED on the user's PC**. Validate with a single small repository first, then proceed with bulk import after explicit user approval.

## Physical test — 2026-10-09

**PASS (user-confirmed):** One GitHub repository was imported successfully into the fresh MyGitea2 Gitea instance (port 3001) using saved local DPAPI credentials and the single-repository migration workflow. The repository name was not reported, so none is asserted here. This is the first end-to-end single-import proof. No bulk import success has yet been verified.

**Next gate:** Refresh Sync GitHub preview; check that the successfully imported repository is counted as skipped and that the missing count decreased by one. Keep Auto Refresh off; only then begin a confirmed bulk import of remaining missing repositories. Treat API acceptance separately from actual verified completion.

## Bulk-import checkpoint and launcher convenience — 2026-10-09

- **User-verified:** 111 GitHub repositories discovered; 107 shown as imported/skipped in Gitea. Remaining 4 repos: `Sadusor/bifrost`, `Sadusor/cua`, `Sadusor/deepseek-harness`, `Sadusor/n8n`.
- **FAIL:** Retrying those four through Gitea's migration API produced HTTP 500 for all four. Do not auto-retry blindly; inspect local Gitea logs for root causes and distinguish migration errors from Git transfer errors. All 107 present repos should remain untouched.
- **Convenience scripts added at repository root:** `START MyGitea2.bat`, `STOP MyGitea2.bat`; both use `windows/MyGitea-Hidden.vbs` to launch PowerShell hidden. Original `windows/START MyGitea.bat` and `windows/STOP MyGitea.bat` remain available for console diagnostics.
- Root START detects an existing MyGitea2 launcher and declines to start another copy. Root STOP stops the MyGitea2 server and its matching PowerShell control-listener launcher; it does not target the old `E:\MyGitea` installation.
- **Status:** Root BAT/VBS convenience launchers committed, **not yet physically tested**. Verify syntax, hidden operation and START/STOP after preserving runtime status. Never stop the application during imports.

## Hidden STOP GUI regression — 2026-10-09

- **User test:** root START BAT opens MyGitea2 successfully, but root STOP BAT leaves the Chrome app GUI visible. STOP GUI = **FAIL**; START = **PASS**.
- **Fix committed:** `windows/MyGitea-Control.ps1` now posts a graceful `WM_CLOSE` to visible Chrome windows belonging to processes launched with the dedicated `%LOCALAPPDATA%\MyGitea2\ChromeProfile` profile, including their child processes. It then stops only MyGitea2's `gitea.exe` and the matching local controller. It does **not** target the user's normal Chrome profile or `E:\MyGitea`.
- **Not yet physically verified:** Pull update, syntax-check, then STOP and START. Verify the MyGitea2 app window closes while ordinary Chrome windows stay open. If it fails, collect the observed behavior before modifying further.
- The four migration failures (`bifrost`, `cua`, `deepseek-harness`, `n8n`) are **deferred by user request**. Do not retry or change migrations in this STOP/START task.

## Hidden launcher test verified — 2026-10-09

**PASS (user-confirmed):** Root hidden START opens the MyGitea2 app; root STOP closes the Chrome GUI; subsequent read-only Win32_Process enumeration for `powershell.exe` processes with command line containing `E:\MyGitea2\windows\MyGitea-Control.ps1` returned **no matching processes**. This proves no matching MyGitea2 PowerShell launcher remained after STOP. Original Gitea unchanged. Pending: read-only integrity audit for 107 migrated repositories; the four deferred imports remain untouched.

## Read-only Git code-integrity audit — 2026-10-09

**Implementation:** `windows/MyGitea-IntegrityAudit.ps1` compares all GitHub repositories owned by the authenticated user against MyGitea2 repositories for the authenticated Gitea user. It checks **every enumerated branch and tag's 40-character commit object hash**, including GitHub-only and Gitea-only refs. It does **not** clone, push, migrate, update or delete repositories. It writes only local CSV/JSON reports to `%LOCALAPPDATA%\MyGitea2\Audit`.

Run in PowerShell **while MyGitea2 is running**:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "E:\MyGitea2\windows\MyGitea-IntegrityAudit.ps1"
```

Optional first small test:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "E:\MyGitea2\windows\MyGitea-IntegrityAudit.ps1" -MaxRepositories 1
```

**Result meanings:**
- `MATCH`: both locations expose the same enumerated branch names, tag names and commit hashes. This validates Git ref parity, not all Gitea metadata, LFS files or issues.
- `DIFFERENT`: a branch/tag is missing on one side or a hash differs; source GitHub may have changed after migration.
- `MISSING`: repository not in current MyGitea2 account.
- `ERROR`: authentication/API/format error for that repository, not proof of missing code.

Expected starting situation before running (not a predicted result): the user previously observed **107/111 repositories present**, four deferred API migration failures (`bifrost`, `cua`, `deepseek-harness`, `n8n`). No claim of 107 hash matches is made until a report is generated. The integrity script has been committed and reviewed for consistency, but **has not yet passed a physical PowerShell run**.

**Safety:** Never paste GitHub/Gitea tokens in chat; the script reads the existing DPAPI keys locally. Reports include repository names and hashes, not tokens. Do not delete the original `E:\MyGitea` installation based on a single branch comparison.

## Read-only audit smoke test — 2026-10-09

**User-confirmed PASS (physical Windows PowerShell run):** `MyGitea-IntegrityAudit.ps1 -MaxRepositories 1` checked `Sadusor/agency-agents`: **MATCH 1, DIFFERENT 0, MISSING 0, ERROR 0**. Reports generated at `%LOCALAPPDATA%\MyGitea2\Audit\integrity-20261009-184944.csv` and corresponding `.json`. The first-run audit therefore exercises authentication and report generation on Windows, but the **full 111-repository audit is still pending**. No repositories modified.

## Full read-only integrity audit — 2026-10-09

**User-confirmed physical run** of `windows/MyGitea-IntegrityAudit.ps1`, 111 GitHub repos examined. Report: `%LOCALAPPDATA%\MyGitea2\Audit\integrity-20261009-185129.csv` and corresponding JSON.

| Result | Count | Names |
| --- | ---: | --- |
| MATCH | **98** | See report for full list |
| DIFFERENT | **2** | `Sadusor/cua`, `Sadusor/MyGitea2` |
| MISSING | **3** | `Sadusor/bifrost`, `Sadusor/deepseek-harness`, `Sadusor/n8n` |
| ERROR | **8** | `Sadusor/AiHub`, `Sadusor/assistant`, `Sadusor/Forgetrader`, `Sadusor/KiraPhoneBench`, `Sadusor/ORION-AI-BRIDGE`, `Sadusor/RememberAi`, `Sadusor/w`, `Sadusor/website` |

**Interpretation:** 98 repos have matching exposed Git branch/tag refs and commit IDs. `cua` is **present**, contrary to the earlier four-missing assumption, but Git ref parity differs. `MyGitea2` may differ because the source continues to receive code changes; investigate exact ref mismatches before concluding. Eight ERRORs require inspection of the `Details` field; they do not establish corruption or missing code. No destructive action or new import authorized. User has deferred missing imports. Preserve `E:\MyGitea` original.

**Next safe read-only step:** show CSV rows with status other than MATCH, including `Details`. Diagnose error categories first; keep secrets out of output.

## Integrity audit: empty API entries correction — 2026-10-09

The full physical run returned **98 MATCH, 2 DIFFERENT, 3 MISSING, 8 ERROR**. User inspected errors: `Unrecognized branch or tag API entry.` for at least `Forgetrader`, `KiraPhoneBench`, `ORION-AI-BRIDGE`, `RememberAi`, `w`, `website` (same status for `AiHub` and `assistant`).

**Code correction:** The read-only audit now ignores null placeholders returned when PowerShell enumerates empty branch/tag arrays, while rejecting other malformed records with source information. Repositories with **zero branch/tag refs on both sides** are classified as `EMPTY`, **not `MATCH`**, because zero refs is not meaningful proof of Git code parity. Report summary includes `Empty`. This change is committed but **awaits rerun**; previous counts remain the only physically observed totals. `MyGitea2` differed on `main` because its GitHub commit hash had advanced relative to the imported Gitea branch (`44a992af…` versus `095468eb…` at observation time). At least one other difference is `branch:docs/custom-ipsw exists only in MyGitea2`; preserve until diagnosed. Do not auto-sync Git refs or touch original Gitea.

## Integrity audit: literal `null` branch response — 2026-10-09

**Confirmed user diagnostic:** On `Sadusor/AiHub`, authenticated MyGitea2 `GET /api/v1/repos/{owner}/AiHub/branches?limit=50&page=1` returned a **System.String** whose content is `null`. Previous audit treated that string as a malformed branch object and reported ERROR. Commit `98814dc` updates `Read-AuditPage` to treat **only the exact trimmed literal `null`** as an empty branch/tag response; any other unexpected string remains an ERROR. Repositories with zero refs on both sides are still classified `EMPTY`, not `MATCH`. **Physical full audit rerun pending.** This correction only changes read-only audit parsing; no repo migration, Gitea settings, or original instance changed.

## Empty project clarification — 2026-10-09

The user confirmed the eight previously errored repositories were intentionally created as empty project placeholders (folders/projects only; no code committed): `AiHub`, `assistant`, `Forgetrader`, `KiraPhoneBench`, `ORION-AI-BRIDGE`, `RememberAi`, `w`, and `website`. Treat `EMPTY` as an intentional, valid inventory state, **not as Git code verified or missing/corrupt**, provided the audit's output indeed labels those eight `EMPTY`. No dummy commits or migrations. The last explicitly pasted full-audit totals were earlier than the user's successful EMPTY rerun; do not record new numerical totals as physically verified until the user supplies them. Remaining `DIFFERENT` entries (cua and this actively-developed MyGitea2) and 3 MISSING remain deferred/read-only only.

## FROZEN BASELINE — owner decision, 2026-10-09

**Status: FROZEN. No further edits to MyGitea2 application, launcher, import/sync, audit scripts, configuration, database, stored Git repositories or LFS without new explicit owner approval.** This entry documents the freeze, not a request to update the local installation.

Physical tests confirmed:
- Separate Gitea at `http://127.0.0.1:3001`; original `E:\MyGitea` on port 3000 remains protected.
- Root hidden START/STOP BATs work; STOP closes the dedicated Chrome app and leaves no matching hidden PowerShell controller.
- Git remote `gitea` connects to `http://127.0.0.1:3001/MyGitea/MyGitea2.git`; existing GitHub `origin` retained.
- Read-only Git connectivity succeeds; `git push gitea HEAD:refs/heads/local-push-test-20261009` succeeded; its remote commit hash matched local HEAD.
- Personal `MYGITEA2_GIT_MANUAL.md` pushed to Gitea branch `docs-my-gitea-manual`; owner confirmed it displays correctly.
- Full audit initially 98 matching Git-ref sets, two DIFFERENT (`cua`, `MyGitea2`), three MISSING (`bifrost`, `deepseek-harness`, `n8n`), eight ERROR subsequently diagnosed as intentionally empty project placeholders; after parser correction the user reports EMPTY statuses, but has not pasted the final full totals. Do not fabricate a subsequent exact count.
- Approximate on-disk size: `E:\MyGitea2` 8.06 GiB, consisting primarily of `mygitea2-data\repositories` 7.201 GiB and `mygitea2-data\lfs` 0.705 GiB, SQLite DB ~3.6 MiB. No cleanup authorized.

**Preservation rules:** No migration retries, deletions, Git ref force-pushes, branch merges, changing primary remotes, performance cleanup, or modifications of `E:\MyGitea` as part of this freeze. The three missing repos and any unmatched refs remain known exceptions, not acceptance to discard old data. A separate, verified off-device backup of MyGitea2 remains recommended but **not yet proven**. The local Gitea server is accessible to local PC Git/Hands workflows, but direct autonomous ORION Hands integration is **not yet tested**.

This freeze note is recorded in GitHub documentation only; local files and local Gitea are left untouched.
