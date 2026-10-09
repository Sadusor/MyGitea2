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

1. Keys save successfully and tokens never appear in logs or source control.
2. Preview shows correct GitHub username and MyGitea2 username, repo counts, and skips current names.
3. Import one harmless, small test repo explicitly.
4. Verify repository contents and migration status in the MyGitea2 UI.
5. Only after these pass, plan optional bulk import / startup sync.

## Current limitations

- No bulk import or startup sync yet.
- Looks at repositories owned by the authenticated GitHub user (not organization-owned repos).
- Name collision means skip; it does not refresh existing repository contents.
- Not yet tested on the user's Windows environment.
