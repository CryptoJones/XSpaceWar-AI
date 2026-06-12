# Steam delivery (SteamPipe)

Automated build delivery to Steam, reusing the exact per-tag artifacts CI
already publishes (`xspacewar-ai-{windows,linux,macos}*.zip`). One depot per
platform.

> **Status: scaffolded but inert.** Blocked on a Steamworks partner account +
> the $100 app credit (issue #2). Everything here is committed and ready; the
> `steam-deploy` workflow is **skipped on every release until you arm it**.

## Files

| File | Purpose |
| --- | --- |
| `app_build.vdf` | SteamPipe app build script — one depot per platform. |
| `depot_windows.vdf` / `depot_linux.vdf` / `depot_macos.vdf` | Per-depot file mappings. |
| `../.github/workflows/steam-deploy.yml` | Gated CI job: on a published release, fetch the artifacts and `steamcmd +run_app_build`. |

The `.vdf` files are **templates** — `__PLACEHOLDERS__` are substituted from
repo secrets/vars at deploy time, so no real App/depot IDs live in git.

## Arming it (once the Steamworks app exists)

1. **Create the app** in Steamworks and note its **AppID** and the three
   **depot IDs** (one each for Windows / Linux / macOS).

2. **Generate the cached login** (so CI never hits a 2FA prompt). On a trusted
   machine with `steamcmd`, log in once as the build account:
   ```bash
   steamcmd +login <build_account> +quit      # answer the Steam Guard code once
   base64 -w0 ~/Steam/config/config.vdf        # copy this into the secret below
   ```
   Use a dedicated builder account with **Generate Steam Guard via app**, added
   to the app's build permissions — not your personal account.

3. **Set repo secrets** (Settings → Secrets and variables → Actions → Secrets):
   - `STEAM_APPID`
   - `STEAM_DEPOT_WINDOWS`, `STEAM_DEPOT_LINUX`, `STEAM_DEPOT_MACOS`
   - `STEAM_USERNAME` (the builder account)
   - `STEAM_CONFIG_VDF` (the base64 string from step 2)

4. **Set repo variables** (same screen → Variables):
   - `STEAM_DEPLOY` = `true`  ← this is the master switch that arms the job
   - `STEAM_BETA_BRANCH` = `beta` (optional; the branch a release auto-sets
     live on — leave unset to upload only and promote manually in Steamworks)

5. **Tag a release** (`git tag vX.Y.Z && git push --tags`). `ci.yml` builds and
   publishes the GitHub release; `steam-deploy.yml` then fires on
   `release: published`, uploads the depots, and (if `STEAM_BETA_BRANCH` is set)
   sets that branch live. Re-deploy an existing tag any time via the workflow's
   **Run workflow** button (`workflow_dispatch`).

## Branches

- **default** — the public branch; promote a build to it from the Steamworks
  build page after the testers sign off (keep `setlive` empty for default so a
  push never goes live to everyone automatically).
- **beta** — for the play testers; `STEAM_BETA_BRANCH=beta` auto-sets each
  release live here. Share the beta access code with testers.

## Manual push (no CI)

Fill the placeholders in a copy of the `.vdf` files (or export the same env
vars the workflow uses and `sed` them) and run:
```bash
steamcmd +login <build_account> +run_app_build "$(pwd)/app_build.vdf" +quit
```

## Not in scope here

GodotSteam `PlatformServices` (achievements / lobbies / Rich Presence) is a
separate, later effort — LAN/relay multiplayer is platform-agnostic and needs
none of it to ship. VAC opt-in is tracked with the rest of issue #4.
