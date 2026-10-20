"""Upload the existing validated MFO ZIP; never rebuild or retry a POST."""
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.request
import uuid
import zipfile


def prepare():
    version = os.environ['RELEASE_VERSION'].strip()
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Version must use MAJOR.MINOR.PATCH')
    channel = os.environ['RELEASE_TYPE']
    if channel not in ('release', 'beta', 'alpha'):
        raise ValueError('Invalid release channel')
    notes = os.environ['RELEASE_CHANGELOG'].strip()
    if not notes:
        raise ValueError('Release notes are required')
    archives = list(Path('publish-package').glob('*.zip'))
    if len(archives) != 1:
        raise ValueError('Expected exactly one validated addon ZIP')
    archive = archives[0]
    if archive.name != f'MerchantsFavourOptimiser_v{version}_Forever.zip':
        raise ValueError('Requested version does not match the validated ZIP filename')
    with zipfile.ZipFile(archive) as zf:
        if zf.testzip():
            raise ValueError('ZIP integrity check failed')
        names = zf.namelist()
        if len(names) != len(set(names)) or any(
            not n.startswith('MerchantsFavourOptimiser/') or '..' in Path(n).parts
            for n in names
        ):
            raise ValueError('Invalid ZIP layout')
        toc_name = 'MerchantsFavourOptimiser/MerchantsFavourOptimiser.toc'
        toc = zf.read(toc_name).decode('utf-8')
        if re.findall(r'^## Version:\s*(\S+)\s*$', toc, re.M) != [version]:
            raise ValueError('Requested version does not match ZIP manifest')
        if zf.read(toc_name) != Path(toc_name).read_bytes():
            raise ValueError('ZIP manifest differs from this main commit')
    project = os.environ.get('CF_PROJECT_ID', '').strip()
    ids = os.environ.get('CF_GAME_VERSION_IDS', '').strip()
    if not re.fullmatch(r'[1-9]\d*', project):
        raise ValueError('Set repository variable CF_PROJECT_ID to the MFO project ID')
    if ids and not re.fullmatch(r'[1-9]\d*(,[1-9]\d*)*', ids):
        raise ValueError('CF_GAME_VERSION_IDS must contain comma-separated numeric IDs')
    metadata = dict(displayName=f'MFO {version} - WoW Forever',
                    gameVersions=[int(i) for i in ids.split(',')] if ids else [],
                    releaseType=channel, changelog=notes, changelogType='markdown')
    return archive, project, metadata


def main():
    archive, project, metadata = prepare()
    token = os.environ.get('CF_API_TOKEN', '')
    if not token:
        raise ValueError('Set GitHub Actions secret CF_API_TOKEN')
    # Authenticate even in preview mode; resolve the exact Forever version only.
    request = urllib.request.Request(
        'https://wow.curseforge.com/api/game/versions',
        headers={'X-Api-Token': token})
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None
    opener = urllib.request.build_opener(NoRedirect)
    try:
        with opener.open(request, timeout=30) as response:
            versions = json.load(response)
    except urllib.error.URLError as error:
        raise SystemExit(f'Game-version lookup failed ({getattr(error, "code", "network")}). Check CF_API_TOKEN.') from None
    toc = Path('MerchantsFavourOptimiser/MerchantsFavourOptimiser.toc').read_text()
    interface = re.findall(r'^## Interface:\s*(\d+)\s*$', toc, re.M)
    if len(interface) != 1:
        raise ValueError('Expected one tested Forever interface version')
    interface = int(interface[0])
    game_version = f'{interface // 10000}.{interface // 100 % 100}.{interface % 100}'
    if not 16000 <= interface < 17000:
        raise ValueError('Publisher is restricted to WoW Forever')
    matching = [v['id'] for v in versions
                if v.get('name') == game_version
                and v.get('gameVersionTypeID') == 88568]
    if len(matching) != 1:
        raise ValueError(f'No unique CurseForge Forever match for {game_version}; refusing fallback')
    if metadata['gameVersions'] and metadata['gameVersions'] != matching:
        raise ValueError('Configured game-version IDs do not match the tested Forever client')
    metadata['gameVersions'] = matching
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    summary = (f'Package: {archive.name}\nProject: {project}\nSHA256: {digest}\n'
               f'Metadata:\n{json.dumps(metadata, indent=2)}\n')
    print(summary)
    if os.environ.get('DRY_RUN', 'true') != 'false':
        print('Dry run complete. Nothing uploaded.')
        return
    token = os.environ.get('CF_API_TOKEN', '')
    if not token:
        raise ValueError('Set GitHub Actions secret CF_API_TOKEN')
    boundary = uuid.uuid4().hex
    body = (
        f'--{boundary}\r\nContent-Disposition: form-data; name="metadata"\r\n\r\n'
        f'{json.dumps(metadata)}\r\n--{boundary}\r\n'
        f'Content-Disposition: form-data; name="file"; filename="{archive.name}"\r\n'
        'Content-Type: application/zip\r\n\r\n'
    ).encode() + archive.read_bytes() + f'\r\n--{boundary}--\r\n'.encode()
    request = urllib.request.Request(
        f'https://wow.curseforge.com/api/projects/{project}/upload-file',
        data=body, headers={'X-Api-Token': token,
                           'Content-Type': f'multipart/form-data; boundary={boundary}'})
    # Refuse redirects so authentication cannot be forwarded to another host.
    try:
        with opener.open(request, timeout=120) as response:
            result = json.load(response)
    except (urllib.error.URLError, TimeoutError) as error:
        code = getattr(error, 'code', 'network/timeout')
        raise SystemExit(f'Upload failed ({code}). Check CurseForge before retrying; the upload may have arrived.') from None
    file_id = result.get('id')
    if not isinstance(file_id, int) or file_id <= 0:
        raise SystemExit('No valid file ID returned. Check CurseForge before retrying.')
    print(f'CurseForge accepted upload. File ID: {file_id}. Publication/review status must be checked on CurseForge.')
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as output:
            output.write(f'Uploaded **{archive.name}** to project **{project}**. File ID: **{file_id}**.\n\nSHA256: `{digest}`\n')


if __name__ == '__main__':
    main()
