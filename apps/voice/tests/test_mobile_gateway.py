import hashlib
import json
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from mobile_gateway import app as gw
from mobile_gateway.providers import aham_voice

KEY = b'k' * 32


def signed(method, path, body=b''):
    stamp = str(time.time())
    return {'X-Voice-Time': stamp, 'X-Voice-Signature': gw.sign(KEY, method, path, stamp, body)}


class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        gw.HOME = Path(self.tmp.name)
        (gw.HOME / 'private').mkdir(parents=True)
        (gw.HOME / 'private' / 'bridge-key').write_bytes(KEY)
        gw._provider = None
        self.client = TestClient(gw.app)
        self.client.__enter__()
        gw.login_limit.hits.clear()
        with patch.object(aham_voice, 'backend', return_value={'id': 'alice', 'name': 'Alice'}) as call:
            r = self.client.post('/v1/login', json={'username': 'alice', 'password': 'pw'})
            call.assert_called_once_with('login', {'username': 'alice', 'password': 'pw'})
        self.assertEqual(r.status_code, 200)
        self.auth = {'Authorization': 'Bearer ' + r.json()['token']}
        self.audio = b'OggS' + bytes(range(256)) * 40
        self.meta = {'file_name': 'note20251203-123344.ogg', 'size': len(self.audio),
                     'sha256': hashlib.sha256(self.audio).hexdigest(), 'kind': 'note',
                     'device_sn': 'SN1', 'recorded_at_ms': 1764736424000}

    def tearDown(self):
        self.client.__exit__(None, None, None)
        self.tmp.cleanup()

    def upload(self, chunk=4000):
        up = self.client.post('/v1/uploads', json=self.meta, headers=self.auth).json()
        for offset in range(0, len(self.audio), chunk):
            r = self.client.put(f"/v1/uploads/{up['id']}/chunk?offset={offset}", content=self.audio[offset:offset + chunk], headers=self.auth)
            self.assertEqual(r.status_code, 200, r.text)
        return self.client.post(f"/v1/uploads/{up['id']}/complete", headers=self.auth).json()

    def test_requires_login(self):
        self.assertEqual(self.client.get('/v1/uploads').status_code, 401)
        self.assertEqual(self.client.get('/v1/uploads', headers={'Authorization': 'Bearer nope'}).status_code, 401)

    def test_resume_and_idempotent_upload(self):
        up = self.client.post('/v1/uploads', json=self.meta, headers=self.auth).json()
        self.client.put(f"/v1/uploads/{up['id']}/chunk?offset=0", content=self.audio[:3000], headers=self.auth)
        again = self.client.post('/v1/uploads', json=self.meta, headers=self.auth).json()
        self.assertEqual((again['id'], again['received']), (up['id'], 3000))
        gap = self.client.put(f"/v1/uploads/{up['id']}/chunk?offset=5000", content=b'x', headers=self.auth)
        self.assertEqual(gap.status_code, 409)
        repeat = self.client.put(f"/v1/uploads/{up['id']}/chunk?offset=0", content=self.audio[:3000], headers=self.auth)
        self.assertEqual(repeat.json()['received'], 3000)
        early = self.client.post(f"/v1/uploads/{up['id']}/complete", headers=self.auth)
        self.assertEqual(early.status_code, 409)
        self.client.put(f"/v1/uploads/{up['id']}/chunk?offset=3000", content=self.audio[3000:], headers=self.auth)
        done = self.client.post(f"/v1/uploads/{up['id']}/complete", headers=self.auth).json()
        self.assertEqual(done['status'], 'ready')
        self.assertEqual((gw.HOME / 'uploads' / up['id']).read_bytes(), self.audio)

    def test_checksum_mismatch_restarts_upload(self):
        self.meta['sha256'] = '0' * 64
        up = self.client.post('/v1/uploads', json=self.meta, headers=self.auth).json()
        self.client.put(f"/v1/uploads/{up['id']}/chunk?offset=0", content=self.audio, headers=self.auth)
        r = self.client.post(f"/v1/uploads/{up['id']}/complete", headers=self.auth)
        self.assertEqual(r.status_code, 422)
        self.assertEqual(self.client.get(f"/v1/uploads/{up['id']}", headers=self.auth).json()['received'], 0)

    def test_rejects_bad_metadata(self):
        for change in ({'file_name': 'x.exe'}, {'size': 0}, {'sha256': 'abc'}, {'kind': 'other'}):
            r = self.client.post('/v1/uploads', json={**self.meta, **change}, headers=self.auth)
            self.assertEqual(r.status_code, 400, change)

    def test_other_users_cannot_see_upload(self):
        up = self.upload()
        with patch.object(aham_voice, 'backend', return_value={'id': 'bob', 'name': 'Bob'}):
            token = self.client.post('/v1/login', json={'username': 'bob', 'password': 'pw'}).json()['token']
        r = self.client.get(f"/v1/uploads/{up['id']}", headers={'Authorization': 'Bearer ' + token})
        self.assertEqual(r.status_code, 404)

    def test_worker_pull_and_single_notification(self):
        up = self.upload()
        self.client.post('/v1/devices', json={'apns_token': 'ab' * 32, 'environment': 'sandbox'}, headers=self.auth)
        path = '/internal/v1/uploads/ready'
        self.assertEqual(self.client.get(path).status_code, 401)
        items = self.client.get(path, headers=signed('GET', path)).json()['items']
        self.assertEqual([i['id'] for i in items], [up['id']])
        file_path = f"/internal/v1/uploads/{up['id']}/file"
        self.assertEqual(self.client.get(file_path, headers=signed('GET', file_path)).content, self.audio)
        claim = f"/internal/v1/uploads/{up['id']}/claimed"
        self.client.post(claim, headers=signed('POST', claim))
        self.assertEqual(self.client.get(path, headers=signed('GET', path)).json()['items'], [])
        result = f"/internal/v1/uploads/{up['id']}/result"
        body = json.dumps({'recording_id': 'r1', 'title': '会议', 'summary_status': 'done'}).encode()
        with patch.object(gw.apns, 'send', return_value='sent') as push:
            first = self.client.post(result, content=body, headers={**signed('POST', result, body), 'Content-Type': 'application/json'})
            second = self.client.post(result, content=body, headers={**signed('POST', result, body), 'Content-Type': 'application/json'})
        self.assertEqual((first.json()['notified'], second.json()['notified']), (1, 0))
        self.assertEqual(push.call_args[0][1]['aps']['alert']['title'], '纪要已生成')
        mine = self.client.get(f"/v1/uploads/{up['id']}", headers=self.auth).json()
        self.assertEqual((mine['status'], mine['recording_id']), ('done', 'r1'))

    def test_signature_bound_to_path(self):
        good = signed('GET', '/internal/v1/uploads/ready')
        self.assertEqual(self.client.get('/internal/v1/uploads/x/file', headers=good).status_code, 401)

    def test_push_skipped_without_apns_settings(self):
        self.assertEqual(gw.apns.send('ab' * 32, {}), 'skipped')

    def test_reads_go_through_provider(self):
        with patch.object(aham_voice, 'backend', return_value={'items': []}) as call:
            self.client.get('/v1/recordings/r1/summary', headers=self.auth)
        call.assert_called_once_with('summary', {'user_id': 'alice', 'arguments': {'recording_id': 'r1', 'limit': 100, 'offset': 0}})
        self.assertEqual(self.client.get('/v1/recordings/r1/audio', headers=self.auth).status_code, 404)


if __name__ == '__main__':
    unittest.main()
