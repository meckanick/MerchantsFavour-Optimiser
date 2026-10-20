import copy
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('request', Path(__file__).parents[1] / 'scripts/prepare-curseforge-request.py')
request = importlib.util.module_from_spec(spec)
spec.loader.exec_module(request)


class ReleaseRequestTests(unittest.TestCase):
    def setUp(self):
        self.sha = 'a' * 40
        self.payload = dict(main_sha=self.sha, changelog='Fix scan times\n\nImprove scrolling.',
                            release_type='release', mode='preview')
        self.event = dict(action='opened', repository=dict(owner=dict(login='meckanick')),
                          issue=dict(title=request.TITLE, user=dict(login='meckanick'),
                                     body=json.dumps(self.payload)))

    def run_request(self, **kwargs):
        self.event['issue']['body'] = json.dumps(self.payload)
        args = dict(event=self.event, sha=self.sha, actor='meckanick', attempt='1',
                    toc='## Interface: 16001\n## Version: 0.1.71\n')
        args.update(kwargs)
        return request.prepare(**args)

    def test_preview_reads_main_version_and_preserves_multiline_notes(self):
        result = self.run_request()
        self.assertEqual(result['version'], '0.1.71')
        self.assertEqual(result['changelog'], self.payload['changelog'])
        self.assertEqual(result['dry_run'], 'true')

    def test_publish_requires_explicit_mode(self):
        self.payload['mode'] = 'publish'
        self.assertEqual(self.run_request()['dry_run'], 'false')
        for bad in [True, False, '', 'false', 'Publish', None]:
            with self.subTest(mode=bad), self.assertRaises(ValueError):
                self.payload['mode'] = bad
                self.run_request()

    def test_wrong_author_actor_title_action_and_pr_are_rejected(self):
        for path, value in [('author', 'other'), ('actor', 'other'), ('title', 'Other'),
                            ('action', 'edited'), ('pr', {})]:
            original = copy.deepcopy(self.event)
            args = {}
            if path == 'author': self.event['issue']['user']['login'] = value
            if path == 'actor': args['actor'] = value
            if path == 'title': self.event['issue']['title'] = value
            if path == 'action': self.event['action'] = value
            if path == 'pr': self.event['issue']['pull_request'] = value
            with self.subTest(path=path), self.assertRaises(ValueError): self.run_request(**args)
            self.event = original

    def test_stale_commit_and_rerun_are_rejected(self):
        with self.assertRaises(ValueError): self.run_request(sha='b' * 40)
        with self.assertRaises(ValueError): self.run_request(attempt='2')

    def test_schema_channel_notes_and_toc_are_checked(self):
        for key, value in [('release_type', 'stable'), ('changelog', ''), ('changelog', 3),
                           ('changelog', 'a' * 20001), ('changelog', 'abc\x00'), ('extra', True)]:
            original = self.payload.copy()
            self.payload[key] = value
            with self.subTest(key=key, value=str(value)[:20]), self.assertRaises(ValueError):
                self.run_request()
            self.payload = original
        for toc in ['', '## Version: 1.0\n', '## Version: 0.1.71\n## Version: 0.1.72\n']:
            with self.subTest(toc=toc), self.assertRaises(ValueError): self.run_request(toc=toc)


if __name__ == '__main__':
    unittest.main()
