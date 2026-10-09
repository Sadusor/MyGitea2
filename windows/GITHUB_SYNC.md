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
