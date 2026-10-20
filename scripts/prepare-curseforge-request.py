"""Validate an owner-authored release request; never execute issue content."""
import json
import os
from pathlib import Path
import re
import uuid

TITLE = '[CurseForge] MFO release request'


def prepare(event, sha, actor, attempt, toc):
    owner = event['repository']['owner']['login']
    issue = event['issue']
    if (event.get('action') != 'opened' or issue.get('title') != TITLE
            or issue.get('user', {}).get('login') != owner or actor != owner
            or 'pull_request' in issue):
        raise ValueError('Only new release requests opened by the repository owner are accepted')
    if str(attempt) != '1':
        raise ValueError('Do not rerun release requests; check CurseForge before creating another')
    request = json.loads(issue.get('body') or '')
    if not isinstance(request, dict) or set(request) != {'main_sha', 'changelog', 'release_type', 'mode'}:
        raise ValueError('Expected main_sha, changelog, release_type and mode')
    if not re.fullmatch(r'[0-9a-f]{40}', str(request['main_sha'])) or request['main_sha'] != sha:
        raise ValueError('Release request does not match the main commit that triggered this run')
    if request['mode'] not in ('preview', 'publish'):
        raise ValueError('Mode must explicitly be preview or publish')
    if request['release_type'] not in ('release', 'beta', 'alpha'):
        raise ValueError('Invalid release channel')
    notes = request['changelog']
    if not isinstance(notes, str) or not notes.strip() or len(notes) > 20000 or '\x00' in notes:
        raise ValueError('Release notes must contain 1-20000 characters and no NUL')
    versions = re.findall(r'^## Version:\s*(\S+)\s*$', toc, re.M)
    if len(versions) != 1 or not re.fullmatch(r'\d+\.\d+\.\d+', versions[0]):
        raise ValueError('Expected one valid addon version in the main TOC')
    return dict(version=versions[0], changelog=notes.strip(),
                release_type=request['release_type'],
                dry_run='true' if request['mode'] == 'preview' else 'false')


def main():
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    toc = Path('MerchantsFavourOptimiser/MerchantsFavourOptimiser.toc').read_text()
    values = prepare(event, os.environ['GITHUB_SHA'], os.environ['GITHUB_ACTOR'],
                     os.environ['GITHUB_RUN_ATTEMPT'], toc)
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        for key, value in values.items():
            delimiter = uuid.uuid4().hex
            while delimiter in value.splitlines():
                delimiter = uuid.uuid4().hex
            output.write(f'{key}<<{delimiter}\n{value}\n{delimiter}\n')
    print(f"Validated MFO {values['version']}; preview={values['dry_run']}")


if __name__ == '__main__':
    main()
