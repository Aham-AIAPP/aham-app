"""手机上传录音的失败回报、重试和无有效语音（2026-11-25）。"""
import asyncio
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

_root = tempfile.TemporaryDirectory()
os.environ['RECORDING_AI_HOME'] = _root.name
from backend.app import main as m, mobile_source as mobile, voice_integration as v, voice_worker as worker

KEY = b'g' * 32


class MobileFailureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        m.BASE = Path(self.tmp.name); m.APP_DATA = m.BASE / 'app-data'; m.APP_DATA.mkdir()
        m.DB_PATH = m.APP_DATA / 'test.sqlite'; m.RECORDINGS = m.APP_DATA / 'recordings'; m.RECORDINGS.mkdir()
        m.ensure_schema(); v.ensure_schema()
        (m.BASE / 'private').mkdir()
        (m.BASE / 'private/mobile-gateway.json').write_text(json.dumps({'gateway_url': 'https://gateway.example.com/voice/mobile'}))
        (m.BASE / 'private/mobile-gateway-key').write_bytes(KEY)
        with m.db() as c:
            c.execute("insert into users(id,username,name,email,dept,role,last_active_at,must_change_password,password_hash) values(?,?,?,?,?,'member',?,0,?)",
                      ('alice', 'alice', 'alice', 'alice@example.com', 'Test', m.now(), m.hash_password('secret-pw')))
        self.item = {'id': 'u1', 'user_id': 'alice', 'file_name': 'note20251203-123344.ogg', 'size': 5,
                     'sha256': '', 'kind': 'note', 'title': '现场录音 12月3日 12:33', 'recorded_at_ms': 1764736424000}

    def tearDown(self):
        self.tmp.cleanup()

    def test_final_failure_is_reported_to_gateway(self):
        mobile.add_source(self.item)
        job = worker.claim()
        v.update_job(job['id'], attempt=3)
        job = dict(job, attempt=3)
        with patch.object(mobile, 'gateway', return_value={'ok': True}) as gw:
            worker.fail(job, RuntimeError('ASR 出错'))
        calls = [c for c in gw.call_args_list if c.args[1] == '/internal/v1/uploads/u1/result']
        self.assertEqual(len(calls), 1)
        body = calls[0].args[2]
        self.assertEqual(body['status'], 'failed')
        self.assertIn('ASR 出错', body['error'])

    def test_retry_with_attempts_left_is_not_reported(self):
        mobile.add_source(self.item)
        job = worker.claim()
        with patch.object(mobile, 'gateway', return_value={'ok': True}) as gw:
            worker.fail(job, RuntimeError('暂时失败'))
        self.assertFalse([c for c in gw.call_args_list if c.args[1].endswith('/result')])

    def test_rescan_after_phone_retry_requeues_failed_job(self):
        mobile.add_source(self.item)
        with m.db() as c:
            c.execute("update voice_jobs set status='failed',attempt=4,error='x'")
        _, new = mobile.add_source(self.item)
        self.assertFalse(new)
        with m.db() as c:
            self.assertEqual(tuple(c.execute('select status,attempt from voice_jobs').fetchone()), ('queued', 0))
            self.assertEqual(c.execute('select count(*) from voice_jobs').fetchone()[0], 1)

    def test_no_speech_finishes_with_notice(self):
        path = m.RECORDINGS / 'r1.ogg'; path.write_bytes(b'OggS')
        with m.db() as c:
            c.execute('''insert into recordings(id,title,filename,file_path,meeting_type,tag,owner_id,duration,duration_label,asr_status,summary_status,created_at,updated_at)
                         values('r1','t','r1.ogg',?,'内部会议','录音卡','alice',2,'00:02','queued','pending',?,?)''', (str(path), m.now(), m.now()))
        user = v.owner('alice')
        model = MagicMock(); model.generate.return_value = [{'text': '', 'sentence_info': []}]
        with patch.object(m, 'get_asr_model', return_value=model):
            out = m.transcribe_recording('r1', user)
        self.assertTrue(out.get('no_speech'))
        with patch.object(m, 'call_deepseek_summary') as llm:
            asyncio.run(m.summarize_recording('r1', user))
            llm.assert_not_called()
        with m.db() as c:
            rec = dict(c.execute("select asr_status,summary_status from recordings where id='r1'").fetchone())
            content = c.execute("select content from summaries where recording_id='r1' and is_current=1").fetchone()[0]
        self.assertEqual((rec['asr_status'], rec['summary_status']), ('done', 'done'))
        self.assertIn('无有效语音', content)


if __name__ == '__main__':
    unittest.main()
