"""Upload gateway for the mobile app.

Runs on a public server behind nginx. Phones talk only to this gateway: they
sign in, upload recordings in chunks, read results and register for push.
Sign-in, processing and reads belong to a pluggable processing provider
(providers/). The provider reports each finished recording with finish_upload(),
and the gateway then sends the push notification. The gateway keeps no
passwords of the processing service.

Environment:
  GATEWAY_HOME         data directory (database, uploads, private key files)
  GATEWAY_PROVIDER     processing provider, default aham_voice (see providers/)
  GATEWAY_MAX_MB       per-upload limit, default 2048
  GATEWAY_KEEP_DAYS    days to keep audio after the Mac has imported it; 0 (default) keeps
                       everything and turns the sweeper off
  APNS_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC   push; all four or none
"""
from __future__ import annotations

import collections
import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import threading
import time
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException, Request

from . import apns
from .providers import load_provider

HOME = Path(os.environ.get('GATEWAY_HOME', Path.home() / '.cache' / 'voice-mobile-gateway'))
CHUNK_MAX = 8 * 1024 * 1024
TOKEN_DAYS = 90
KINDS = {'note', 'call', 'import'}
SUFFIXES = {'.ogg', '.opus', '.m4a', '.aac', '.wav', '.mp3'}
ID_PATTERN = re.compile(r'[A-Za-z0-9_-]{1,64}')
SHA_PATTERN = re.compile(r'[0-9a-f]{64}')


def max_bytes():
    return int(os.environ.get('GATEWAY_MAX_MB', '2048')) * 1024 * 1024


def keep_seconds():
    return int(os.environ.get('GATEWAY_KEEP_DAYS', '0')) * 86400


def uploads_dir():
    path = HOME / 'uploads'
    path.mkdir(parents=True, exist_ok=True)
    return path


def bridge_key():
    path = HOME / 'private' / 'bridge-key'
    if not path.exists():
        raise HTTPException(503, '网关密钥未配置')
    return path.read_bytes()


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


@contextmanager
def db():
    HOME.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(HOME / 'gateway.sqlite3', timeout=30, isolation_level=None)
    conn.row_factory = sqlite3.Row
    conn.execute('pragma journal_mode=wal')
    try:
        yield conn
    finally:
        conn.close()


def ensure_schema():
    with db() as c:
        c.executescript("""
        create table if not exists tokens(
          hash text primary key, user_id text not null, user_name text not null,
          device_name text not null, created real not null, expires real not null,
          revoked integer not null default 0);
        create table if not exists uploads(
          id text primary key, user_id text not null, device_sn text not null,
          file_name text not null, size integer not null, sha256 text not null,
          kind text not null, title text not null, recorded_at_ms integer,
          duration_sec real, received integer not null default 0,
          status text not null, recording_id text, result text,
          created real not null, updated real not null,
          unique(user_id, sha256, size));
        create table if not exists devices(
          apns_token text primary key, user_id text not null,
          environment text not null, updated real not null);
        create table if not exists notifications(
          id text primary key, upload_id text not null, apns_token text not null,
          status text not null, detail text, created real not null);
        """)


def sign(secret, method, path, stamp, body=b''):
    message = f'{method.upper()}\n{path}\n{stamp}\n'.encode() + body
    return hmac.new(secret, message, hashlib.sha256).hexdigest()


class Limiter:
    def __init__(self, count, window):
        self.count, self.window, self.hits = count, window, collections.defaultdict(list)
        self.lock = threading.Lock()

    def check(self, key):
        with self.lock:
            now = time.time()
            hits = [t for t in self.hits[key] if now - t < self.window]
            if len(hits) >= self.count:
                raise HTTPException(429, '尝试次数过多，请稍后再试')
            hits.append(now)
            self.hits[key] = hits


login_limit = Limiter(10, 300)
app = FastAPI(title='Voice mobile gateway', docs_url=None, redoc_url=None, openapi_url=None)


_provider = None


def provider():
    global _provider
    if _provider is None:
        _provider = load_provider(os.environ.get('GATEWAY_PROVIDER', 'aham_voice'))
    return _provider


@app.on_event('startup')
def startup():
    ensure_schema()
    provider().install(app)
    threading.Thread(target=sweeper, daemon=True, name='gateway-sweeper').start()


def sweeper():
    while True:
        try:
            purge()
        except Exception:
            pass
        time.sleep(3600)


def purge():
    """Delete audio the Mac has imported, after the keep period, and stale partial uploads."""
    if keep_seconds() <= 0:
        return
    cutoff = time.time() - keep_seconds()
    with db() as c:
        rows = c.execute("select id from uploads where (status in ('claimed','done') and updated<?) or (status='receiving' and updated<?)",
                         (cutoff, time.time() - 30 * 86400)).fetchall()
        for row in rows:
            for name in (row['id'], row['id'] + '.part'):
                (uploads_dir() / name).unlink(missing_ok=True)
            c.execute("update uploads set status=case when status='receiving' then 'expired' else status end, updated=? where id=?",
                      (time.time(), row['id']))


# ---------------------------------------------------------------- phone side

def phone(authorization: str | None = Header(default=None)):
    token = (authorization or '').removeprefix('Bearer').strip()
    if not token:
        raise HTTPException(401, '请先登录')
    with db() as c:
        row = c.execute('select * from tokens where hash=?', (digest(token),)).fetchone()
    if not row or row['revoked'] or row['expires'] < time.time():
        raise HTTPException(401, '登录已过期，请重新登录')
    return {'id': row['user_id'], 'name': row['user_name'], 'token_hash': row['hash']}


@app.get('/healthz')
def health():
    return {'ok': True, 'service': 'voice-mobile-gateway'}


@app.post('/v1/login')
def login(payload: dict, request: Request):
    login_limit.check(request.headers.get('x-real-ip') or (request.client.host if request.client else '-'))
    username = str(payload.get('username') or '').strip()
    password = payload.get('password') or ''
    device = str(payload.get('device_name') or 'iPhone').strip()[:80] or 'iPhone'
    if not username or not isinstance(password, str) or not password:
        raise HTTPException(400, '请输入账号和密码')
    user = provider().login(username, password)
    token = secrets.token_urlsafe(40)
    expires = time.time() + TOKEN_DAYS * 86400
    with db() as c:
        c.execute('insert into tokens(hash,user_id,user_name,device_name,created,expires) values(?,?,?,?,?,?)',
                  (digest(token), user['id'], user['name'], device, time.time(), expires))
    return {'token': token, 'expires_at': datetime.fromtimestamp(expires, timezone.utc).isoformat(timespec='seconds'),
            'user': {'id': user['id'], 'name': user['name'], 'must_change_password': user.get('must_change_password', False)}}


@app.post('/v1/logout')
def logout(user=Depends(phone)):
    with db() as c:
        c.execute('update tokens set revoked=1 where hash=?', (user['token_hash'],))
    return {'ok': True}


@app.get('/v1/me')
def me(user=Depends(phone)):
    return {'id': user['id'], 'name': user['name']}


@app.post('/v1/devices')
def register_device(payload: dict, user=Depends(phone)):
    token = str(payload.get('apns_token') or '')
    environment = payload.get('environment', 'production')
    if not re.fullmatch(r'[0-9a-f]{64,200}', token) or environment not in ('sandbox', 'production'):
        raise HTTPException(400, '推送令牌无效')
    with db() as c:
        c.execute('insert into devices values(?,?,?,?) on conflict(apns_token) do update set user_id=excluded.user_id,environment=excluded.environment,updated=excluded.updated',
                  (token, user['id'], environment, time.time()))
    return {'ok': True, 'push_enabled': apns.configured()}


def public_upload(row):
    return {'id': row['id'], 'file_name': row['file_name'], 'size': row['size'], 'received': row['received'],
            'status': row['status'], 'kind': row['kind'], 'title': row['title'], 'recording_id': row['recording_id'],
            'result': json.loads(row['result']) if row['result'] else None}


@app.post('/v1/uploads')
def create_upload(payload: dict, user=Depends(phone)):
    """Start an upload, or return the existing one for the same audio (same SHA-256 and size)."""
    try:
        size = int(payload['size'])
        sha = str(payload['sha256']).lower()
        file_name = Path(str(payload['file_name'])).name[:120]
    except (KeyError, TypeError, ValueError):
        raise HTTPException(400, '缺少文件名、大小或校验值')
    device_sn = str(payload.get('device_sn') or 'phone')[:64]
    kind = payload.get('kind', 'note')
    title = str(payload.get('title') or '').strip()[:150]
    recorded = payload.get('recorded_at_ms')
    duration = payload.get('duration_sec')
    if not SHA_PATTERN.fullmatch(sha) or not 0 < size <= max_bytes():
        raise HTTPException(400, '文件大小或校验值无效')
    if Path(file_name).suffix.lower() not in SUFFIXES:
        raise HTTPException(400, '只支持 ogg、opus、m4a、aac、wav、mp3 文件')
    if kind not in KINDS:
        raise HTTPException(400, '录音类型无效')
    if recorded is not None and (type(recorded) is not int or recorded <= 0):
        raise HTTPException(400, '录音时间无效')
    if duration is not None and (not isinstance(duration, (int, float)) or duration < 0):
        raise HTTPException(400, '录音时长无效')
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        row = c.execute('select * from uploads where user_id=? and sha256=? and size=?', (user['id'], sha, size)).fetchone()
        if row and row['status'] != 'expired':
            c.execute('COMMIT')
            return public_upload(row)
        if row:
            c.execute('delete from uploads where id=?', (row['id'],))
        uid = uuid.uuid4().hex
        c.execute('insert into uploads(id,user_id,device_sn,file_name,size,sha256,kind,title,recorded_at_ms,duration_sec,status,created,updated) values(?,?,?,?,?,?,?,?,?,?,?,?,?)',
                  (uid, user['id'], device_sn, file_name, size, sha, kind, title, recorded, duration, 'receiving', time.time(), time.time()))
        row = c.execute('select * from uploads where id=?', (uid,)).fetchone()
        c.execute('COMMIT')
    return public_upload(row)


def own_upload(c, upload_id, user):
    if not ID_PATTERN.fullmatch(upload_id):
        raise HTTPException(404, '上传不存在')
    row = c.execute('select * from uploads where id=? and user_id=?', (upload_id, user['id'])).fetchone()
    if not row:
        raise HTTPException(404, '上传不存在')
    return row


@app.put('/v1/uploads/{upload_id}/chunk')
async def put_chunk(upload_id: str, offset: int, request: Request, user=Depends(phone)):
    """Append one chunk at `offset`. A repeated chunk is accepted without writing twice."""
    body = await request.body()
    if not body or len(body) > CHUNK_MAX:
        raise HTTPException(413, '分片大小应为 1 字节到 8 MB')
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        row = own_upload(c, upload_id, user)
        if row['status'] != 'receiving':
            c.execute('COMMIT')
            return public_upload(row)
        received = row['received']
        if offset + len(body) <= received:
            c.execute('COMMIT')
            return public_upload(row)
        if offset != received:
            c.execute('COMMIT')
            raise HTTPException(409, f'应从 {received} 字节继续')
        if received + len(body) > row['size']:
            c.execute('COMMIT')
            raise HTTPException(400, '超出声明的文件大小')
        part = uploads_dir() / (upload_id + '.part')
        with part.open('ab') as out:
            out.truncate(received)
            out.write(body)
        c.execute('update uploads set received=?,updated=? where id=?', (received + len(body), time.time(), upload_id))
        row = c.execute('select * from uploads where id=?', (upload_id,)).fetchone()
        c.execute('COMMIT')
    return public_upload(row)


@app.post('/v1/uploads/{upload_id}/complete')
def complete(upload_id: str, user=Depends(phone)):
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        row = own_upload(c, upload_id, user)
        if row['status'] != 'receiving':
            c.execute('COMMIT')
            return public_upload(row)
        part = uploads_dir() / (upload_id + '.part')
        if row['received'] != row['size'] or not part.exists() or part.stat().st_size != row['size']:
            c.execute('COMMIT')
            raise HTTPException(409, f"文件未传完：已收到 {row['received']} / {row['size']} 字节")
        with part.open('rb') as f:
            actual = hashlib.file_digest(f, 'sha256').hexdigest()
        if actual != row['sha256']:
            part.unlink(missing_ok=True)
            c.execute("update uploads set received=0,updated=? where id=?", (time.time(), upload_id))
            c.execute('COMMIT')
            raise HTTPException(422, '文件校验不一致，请重新上传')
        os.replace(part, uploads_dir() / upload_id)
        c.execute("update uploads set status='ready',updated=? where id=?", (time.time(), upload_id))
        row = c.execute('select * from uploads where id=?', (upload_id,)).fetchone()
        c.execute('COMMIT')
    provider().upload_ready(dict(row))
    return public_upload(row)


@app.get('/v1/uploads')
def list_uploads(limit: int = 50, user=Depends(phone)):
    with db() as c:
        rows = c.execute('select * from uploads where user_id=? order by created desc limit ?', (user['id'], max(1, min(limit, 200)))).fetchall()
    return {'items': [public_upload(r) for r in rows]}


@app.get('/v1/uploads/{upload_id}')
def get_upload(upload_id: str, user=Depends(phone)):
    with db() as c:
        return public_upload(own_upload(c, upload_id, user))


@app.get('/v1/recordings')
def recordings(limit: int = 20, offset: int = 0, since: str = '', user=Depends(phone)):
    args = {'limit': limit, 'offset': offset}
    if since:
        args['since'] = since
    return provider().recordings(user, args)


@app.get('/v1/recordings/{recording_id}/{part}')
def recording_part(recording_id: str, part: str, limit: int = 100, offset: int = 0, user=Depends(phone)):
    if part not in ('summary', 'transcript', 'detail'):
        raise HTTPException(404, '不支持的内容')
    return provider().recording_part(user, recording_id, part, {'limit': limit, 'offset': offset})


# ---------------------------------------------------------------- results

def finish_upload(upload_id, payload):
    """Record the provider's result; notify the owner's phones the first time only."""
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        row = c.execute('select * from uploads where id=?', (upload_id,)).fetchone()
        if not row:
            c.execute('COMMIT')
            raise HTTPException(404, '上传不存在')
        first = row['status'] != 'done'
        c.execute("update uploads set status='done',recording_id=?,result=?,updated=? where id=?",
                  (payload['recording_id'], json.dumps(payload, ensure_ascii=False), time.time(), upload_id))
        devices = c.execute('select * from devices where user_id=?', (row['user_id'],)).fetchall() if first else []
        c.execute('COMMIT')
    sent = [notify(upload_id, d, payload) for d in devices]
    return {'ok': True, 'notified': sum(1 for s in sent if s == 'sent')}


def mark_claimed(upload_id):
    with db() as c:
        c.execute("update uploads set status='claimed',updated=? where id=? and status='ready'", (time.time(), upload_id))


def ready_uploads(limit=50):
    with db() as c:
        return [dict(r) for r in c.execute("select * from uploads where status='ready' order by created limit ?", (limit,))]


def upload_row(upload_id):
    if not ID_PATTERN.fullmatch(upload_id):
        raise HTTPException(404, '上传不存在')
    with db() as c:
        row = c.execute('select * from uploads where id=?', (upload_id,)).fetchone()
    if not row:
        raise HTTPException(404, '上传不存在')
    return dict(row)


def upload_path(upload_id):
    return uploads_dir() / upload_id


def notify(upload_id, device, payload):
    title = payload.get('title') or '录音'
    ready = payload.get('summary_status') == 'done'
    message = {'aps': {'alert': {'title': '纪要已生成' if ready else '录音已处理', 'body': title}, 'sound': 'default'},
               'recording_id': payload['recording_id']}
    try:
        status = apns.send(device['apns_token'], message, device['environment'])
        detail = None
    except Exception as exc:
        status, detail = 'failed', str(exc)[:300]
    with db() as c:
        c.execute('insert into notifications values(?,?,?,?,?,?)',
                  (uuid.uuid4().hex, upload_id, device['apns_token'], status, detail, time.time()))
    return status
