# Publishing MFO to CurseForge

Publishing is manual. Pushing or merging to main does not upload to CurseForge.
The publisher uses the existing ZIP from a successful push build for the exact
main commit selected when the workflow is started. It never packages development.

## One-time configuration

In this repository's Settings > Secrets and variables > Actions:

- Add a **secret** named `CF_API_TOKEN`, using an upload token generated at
  https://authors.curseforge.com/#/settings/api-tokens . Do not put it in chat or source.
- Add a **variable** named `CF_PROJECT_ID`, containing the numeric MFO CurseForge project ID.
- The preview authenticates with the saved token and automatically resolves the
  exact tested Forever game version from the TOC using CurseForge's version API.
  No game-version variable is required. Unknown or ambiguous versions fail closed;
  retail/Classic substitutions are refused. `CF_GAME_VERSION_IDS` is optional and,
  if set, must match the automatically resolved version.

Official upload API: https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-upload-api

## Release procedure

1. Test the addon and approve merging development into main.
2. Wait for **Validate and package addon** on that exact main commit to pass.
3. Open Actions > **Publish MFO to CurseForge** > Run workflow; select **main**.
4. Enter the exact TOC version, release notes and release channel.
5. Leave **dry_run** checked for the first preview. Inspect the project ID,
   game-version IDs, package version, SHA256 and notes.
6. When publishing is requested, run again with the same inputs and dry_run unchecked.
7. Check the returned CurseForge file ID and the file's review/publication status.

If an upload times out, check CurseForge before retrying to avoid duplicate files.
Concurrency prevents simultaneous uploads, but deliberately rerunning a completed
release can still create a duplicate. A successful API upload is not a guarantee
that CurseForge has finished processing or approved the file.

## Publishing from chat

After the user says **publish MFO to CurseForge**, the assistant:

1. Reads the current main SHA and TOC version, checks that its push build passed,
   and checks recent release requests and uploads to avoid repeating a release.
2. Compares addon changes since the previous published version and writes
   player-facing release notes. Exclude CI-only changes and unmerged development work.
3. Opens an issue titled exactly `[CurseForge] MFO release request`, with the JSON
   body below. The GitHub connector can create it without workflow-dispatch access.
4. Checks **Process MFO CurseForge request** and its publish job until completion;
   reports the CurseForge file ID, or the actual failure. API acceptance still needs
   CurseForge processing/approval. Never retry a timed-out upload without checking CurseForge.

The assistant may submit `preview` for setup tests. Only submit `publish` when the
user explicitly requests publishing. This setup change itself does not publish.

```json
{
  "main_sha": "EXACT_40_CHARACTER_MAIN_SHA",
  "changelog": "Player-facing release notes, with newlines encoded as JSON.",
  "release_type": "release",
  "mode": "preview"
}
```

Only newly opened requests by the repository owner, with the owner as triggering
actor, are accepted. Other issues are ignored. The main SHA must match the run;
the addon version is read directly from that commit's TOC. Existing ZIP, successful
main build, game-version and token checks still apply. Notes are parsed as data,
never inserted into shell code. The issue is a persistent release request record.
Issue edits/reopens do not trigger uploads, and reruns are refused. To retry, first
check CurseForge, then open a fresh request. Deliberately creating a second request
for an already-published version can still duplicate an upload; check history first.

The existing manual **Run workflow** form remains available as a fallback.

GitHub references:
- https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#issues
- https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows

