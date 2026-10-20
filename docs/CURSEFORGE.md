# Publishing MFO to CurseForge

Publishing is manual. Pushing or merging to main does not upload to CurseForge.
The publisher uses the existing ZIP from a successful push build for the exact
main commit selected when the workflow is started. It never packages development.

## One-time configuration

In this repository's Settings > Secrets and variables > Actions:

- Add a **secret** named `CF_API_TOKEN`, using an upload token generated at
  https://authors.curseforge.com/#/settings/api-tokens . Do not put it in chat or source.
- Add a **variable** named `CF_PROJECT_ID`, containing the numeric MFO CurseForge project ID.
- Add a **variable** named `CF_GAME_VERSION_IDS`, containing the numeric CurseForge
  game-version ID(s) for the tested WoW Forever client, comma-separated without spaces.
  These are CurseForge IDs, not the TOC interface number `16001`. Retrieve them with
  the authenticated GET `https://wow.curseforge.com/api/game/versions` and verify the
  version and game-version type. Never substitute retail or Classic IDs.

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
