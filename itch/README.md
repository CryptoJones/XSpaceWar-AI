# itch.io delivery (butler)

Automated build delivery to itch.io via [butler], reusing the exact per-tag
artifacts CI already publishes (`xspacewar-ai-{windows,linux,macos}*.zip`). One
itch channel per platform: `windows`, `linux`, `osx`.

> **Status: scaffolded but inert.** The `itch-deploy` workflow is **skipped on
> every release until you arm it** with the repo variable below. Nothing here
> stores credentials — the API key lives in a repo secret.

## Files

| File | Purpose |
| --- | --- |
| `../.github/workflows/itch-deploy.yml` | Gated CI job: on a published release, fetch the artifacts and `butler push` each platform channel. |

butler is installed straight from itch.io's official `broth` channel at deploy
time — no third-party action, no checked-in binary.

## Arming it

1. **Create the game page** at `itch.io/dashboard` (the target slug must match
   `<user>/<game>` — default `cryptojones/xspacewar-ai`).

2. **Generate an API key** at <https://itch.io/user/settings/api-keys>. Use a
   wpkey (a generic key works); it never needs your password in CI.

3. **Set the repo secret** (Settings → Secrets and variables → Actions → Secrets):
   - `BUTLER_API_KEY` — the key from step 2

4. **Set repo variables** (same screen → Variables):
   - `ITCH_DEPLOY` = `true`  ← the master switch that arms the job
   - `ITCH_TARGET` = `cryptojones/xspacewar-ai` (optional; only needed if the
     slug differs from the default — e.g. on a fork)

5. **Tag a release** (`git tag vX.Y.Z && git push --tags`). `ci.yml` builds and
   publishes the GitHub release; `itch-deploy.yml` then fires on
   `release: published`, downloads the three zips, and pushes each to its
   channel with the tag as the itch userversion (the leading `v` is stripped).
   Re-deploy an existing tag any time via the workflow's **Run workflow** button
   (`workflow_dispatch`).

## Channels

itch infers the OS from the channel name keyword, so `windows`, `linux`, and
`osx` each land on the right platform and the itch app offers the correct
download / launches the build. Pushing the **unzipped** build directory (not the
zip) lets butler patch incrementally and lets the app run the executable.

## Manual push (no CI)

With butler installed and `BUTLER_API_KEY` exported, from a folder holding the
three unzipped builds:
```bash
butler push windows cryptojones/xspacewar-ai:windows --userversion 3.1.41
butler push linux   cryptojones/xspacewar-ai:linux   --userversion 3.1.41
butler push macos   cryptojones/xspacewar-ai:osx     --userversion 3.1.41
```

[butler]: https://itch.io/docs/butler/
