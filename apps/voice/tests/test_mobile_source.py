import json
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

_root = tempfile.TemporaryDirectory()
os.environ['RECORDING_AI_HOME'] = _root.name
from backend.app import main as m, mobile_source as mobile, voice_integration as v, voice_worker as worker
from fastapi.testclient import TestClient

KEY = b'g' * 32


class MobileSourceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        m.BASE = Path(self.tmp.name); m.APP_DATA = m.BASE / 'app-data'; m.APP_DATA.mkdir()
        m.DB_PATH = m.APP_DATA / 'test.sqlite'; m.RECORDINGS = m.APP_DATA / 'recordings'; m.RECORDINGS.mkdir()
        m.ensure_schema(); v.ensure_schema()
        (m.BASE / 'private').mkdir()
        (m.BASE / 'private/mobile-gateway.json').write_text(json.dumps({'gateway_url': 'https://gateway.example.com/voice/mobile'}))
        (m.BASE / 'private/mobile-gateway-key').write_bytes(KEY)
        with m.db() as c:
            for uid in ('alice', 'bob'):
                c.execute("insert into users(id,username,name,email,dept,role,last_active_at,must_change_password,password_hash) values(?,?,?,?,?,'member',?,0,?)",
                          (uid, uid, uid, uid + '@example.com', 'Test', m.now(), m.hash_password('secret-pw')))
        self.item = {'id': 'u1', 'user_id': 'alice', 'file_name': 'call20251203-123344.ogg', 'size': 5,
                     'sha256': '', 'kind': 'call', 'title': '', 'recorded_at_ms': 1764736424000}

    def tearDown(self):
        self.tmp.cleanup()

    def signed_post(self, client, payload, key=KEY, stamp=None):
        body = json.dumps(payload).encode(); stamp = stamp or str(time.time())
        sig = mobile.sign(key, 'POST', '/api/internal/mobile', stamp, body)
        return client.post('/api/internal/mobile', content=body, headers={'X-Voice-Time': stamp, 'X-Voice-Signature': sig})

    def test_login_and_reads_require_signature(self):
        client = TestClient(m.app)
        ok = self.signed_post(client, {'action': 'login', 'username': 'alice', 'password': 'secret-pw'})
        self.assertEqual(ok.status_code, 200)
        self.assertEqual(ok.json()['id'], 'alice')
        self.assertEqual(self.signed_post(client, {'action': 'login', 'username': 'alice', 'password': 'wrong'}).status_code, 401)
        self.assertEqual(self.signed_post(client, {'action': 'login', 'username': 'alice', 'password': 'secret-pw'}, key=b'x' * 32).status_code, 401)
        self.assertEqual(self.signed_post(client, {'action': 'recordings', 'user_id': 'alice'}, stamp='1').status_code, 401)
        self.assertEqual(self.signed_post(client, {'action': 'recordings', 'user_id': 'alice', 'arguments': {}}).json()['items'], [])
        self.assertEqual(self.signed_post(client, {'action': 'update_hotwords', 'user_id': 'alice'}).status_code, 400)

    def test_failed_logins_lock_account(self):
        client = TestClient(m.app)
        for _ in range(5):
            self.signed_post(client, {'action': 'login', 'username': 'bob', 'password': 'wrong'})
        self.assertEqual(self.signed_post(client, {'action': 'login', 'username': 'bob', 'password': 'secret-pw'}).status_code, 423)

    def test_pipeline_imports_reports_once(self):
        audio = b'audio'
        def fake_gateway(method, path, body=None, timeout=60, stream_to=None):
            if path.endswith('/ready'): return {'items': [self.item]}
            if path.endswith('/file'): Path(stream_to).write_bytes(audio); return None
            if path == '/internal/v1/uploads/u1': return {'file_name': self.item['file_name'], 'size': len(audio), 'sha256': v.sha256(stream_path())}
            return {'ok': True}
        def stream_path():
            p = m.BASE / 'probe'; p.write_bytes(audio); return p
        with patch.object(mobile, 'gateway', side_effect=fake_gateway) as gw:
            self.assertEqual(mobile.scan()['added'], 1)
            self.assertEqual(mobile.scan()['added'], 0)
            job = worker.claim()
            with patch.object(m, 'probe_duration', return_value=60), patch.object(m, 'transcribe_recording'), \
                 patch.object(m, 'summarize_recording'), patch.object(v, 'apply_title'), patch.object(v, 'dws') as dws:
                v.run_job(job)
                dws.assert_not_called()
            reports = [c for c in gw.call_args_list if c.args[1].endswith('/result')]
        self.assertEqual(len(reports), 1)
        with m.db() as c:
            rec = dict(c.execute('select * from recordings').fetchone())
            self.assertEqual((rec['owner_id'], rec['tag']), ('alice', '录音卡通话'))
            self.assertEqual(c.execute("select status from voice_jobs").fetchone()[0], 'done')

    def test_failed_report_retries_from_report_stage(self):
        audio = b'audio'
        digest = None
        def fake_gateway(method, path, body=None, timeout=60, stream_to=None):
            if path.endswith('/file'): Path(stream_to).write_bytes(audio); return None
            if path == '/internal/v1/uploads/u1': return {'file_name': 'a.ogg', 'size': len(audio), 'sha256': digest}
            if path.endswith('/result'): raise RuntimeError('上传网关返回 502')
            return {'ok': True}
        p = m.BASE / 'probe'; p.write_bytes(audio); digest = v.sha256(p)
        mobile.add_source(self.item)
        job = worker.claim()
        with patch.object(mobile, 'gateway', side_effect=fake_gateway), patch.object(m, 'probe_duration', return_value=60), \
             patch.object(m, 'transcribe_recording'), patch.object(m, 'summarize_recording'), patch.object(v, 'apply_title'):
            with self.assertRaises(RuntimeError):
                v.run_job(job)
        with m.db() as c:
            self.assertEqual(c.execute('select stage from voice_jobs').fetchone()[0], 'report')

    def test_unknown_owner_rejected(self):
        with self.assertRaises(ValueError):
            mobile.add_source({**self.item, 'user_id': 'nobody'})
        with self.assertRaises(ValueError):
            mobile.add_source({**self.item, 'id': '../x'})

    def test_disabled_without_config(self):
        (m.BASE / 'private/mobile-gateway.json').unlink()
        self.assertFalse(mobile.enabled())


if __name__ == '__main__':
    unittest.main()
