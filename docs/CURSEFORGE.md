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

An assistant with GitHub workflow-dispatch access can run this when asked.
Otherwise use the same manual Run workflow control. The GitHub connector currently
available in this chat can edit workflows and inspect runs, but exposes no workflow
dispatch operation; publishing from chat may require an additional supported access path.
