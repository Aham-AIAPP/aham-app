"""Recordings uploaded from the mobile app through the upload gateway.

The gateway runs on a public server and keeps uploaded audio until this Mac has
imported it. The worker pulls finished uploads, runs the normal pipeline, and
reports the result back so the gateway can notify the phone. Every request in
both directions is signed with the shared key in private/mobile-gateway-key.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import time
import uuid
from pathlib import Path

from fastapi import HTTPException, Request

PROFILE = 'mobile'
KINDS = {'note': '录音卡', 'call': '录音卡通话', 'import': '手机导入'}


def core():
    from . import main
    return main


def vi():
    from . import voice_integration
    return voice_integration


def config():
    path = core().BASE / 'private' / 'mobile-gateway.json'
    return json.loads(path.read_text()) if path.exists() else {}


def key():
    path = core().BASE / 'private' / 'mobile-gateway-key'
    return path.read_bytes() if path.exists() else None


def enabled():
    return bool(config().get('gateway_url')) and key() is not None


def sign(secret, method, path, stamp, body=b''):
    message = f'{method.upper()}\n{path}\n{stamp}\n'.encode() + body
    return hmac.new(secret, message, hashlib.sha256).hexdigest()


def gateway(method, path, body=None, timeout=60, stream_to=None):
    import httpx
    secret = key()
    if secret is None:
        raise RuntimeError('未配置上传网关密钥')
    data = b'' if body is None else json.dumps(body, ensure_ascii=False).encode()
    stamp = str(time.time())
    headers = {'X-Voice-Time': stamp, 'X-Voice-Signature': sign(secret, method, path, stamp, data)}
    if body is not None:
        headers['Content-Type'] = 'application/json'
    url = config()['gateway_url'].rstrip('/') + path
    with httpx.Client(timeout=timeout, trust_env=False) as client:
        if stream_to is not None:
            with client.stream(method, url, content=data, headers=headers) as r:
                if r.status_code != 200:
                    raise RuntimeError(f'上传网关返回 {r.status_code}')
                with open(stream_to, 'wb') as out:
                    for chunk in r.iter_bytes(1024 * 1024):
                        out.write(chunk)
            return None
        r = client.request(method, url, content=data, headers=headers)
    if r.status_code != 200:
        raise RuntimeError(f'上传网关返回 {r.status_code}：' + vi().sanitize_error(r.text[:300]))
    return r.json()


def add_source(item):
    """Register one finished upload. Idempotent on the gateway upload ID."""
    upload_id, user_id = item.get('id'), item.get('user_id')
    if not isinstance(upload_id, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', upload_id):
        raise ValueError('上传 ID 无效')
    vi().owner(user_id)
    kind = item.get('kind') if item.get('kind') in KINDS else 'note'
    title = str(item.get('title') or '').strip()[:150] or Path(str(item.get('file_name') or '录音')).stem[:150]
    with core().db() as c:
        c.execute('BEGIN IMMEDIATE')
        row = c.execute('select id from recording_sources where profile=? and source_uuid=?', (PROFILE, upload_id)).fetchone()
        if row:
            return row[0], False
        sid, jid, ts = str(uuid.uuid4()), str(uuid.uuid4()), vi().timestamp()
        c.execute('insert into recording_sources(id,profile,source_uuid,owner_id,source_title,source_start,source_url,created_at,updated_at) values(?,?,?,?,?,?,?,?,?)',
                  (sid, PROFILE, upload_id, user_id, title, item.get('recorded_at_ms'), 'mobile://' + kind, ts, ts))
        c.execute('insert into voice_jobs(id,owner_id,source_id,stage,created_at,updated_at) values(?,?,?,?,?,?)',
                  (jid, user_id, sid, 'download', ts, ts))
        return sid, True


def scan():
    data = gateway('GET', '/internal/v1/uploads/ready')
    added = 0
    for item in data.get('items', []):
        try:
            _, new = add_source(item)
        except ValueError as exc:
            vi().set_state('mobile_last_error', {'at': vi().timestamp(), 'upload_id': item.get('id'), 'error': vi().sanitize_error(exc)})
            continue
        added += int(new)
        gateway('POST', f"/internal/v1/uploads/{item['id']}/claimed", {})
    receipt = {'at': vi().timestamp(), 'seen': len(data.get('items', [])), 'added': added}
    vi().set_state('mobile_last_scan', receipt)
    return receipt


def kind_of(source):
    value = (source.get('source_url') or '').removeprefix('mobile://')
    return value if value in KINDS else 'note'


def download(source):
    m = core()
    folder = m.BASE / 'incoming' / source['id']
    folder.mkdir(parents=True, exist_ok=True)
    meta = gateway('GET', f"/internal/v1/uploads/{source['source_uuid']}")
    name = re.sub(r'[^A-Za-z0-9._-]', '_', meta.get('file_name') or 'recording')[-80:]
    suffix = Path(name).suffix.lower()
    if suffix not in ('.ogg', '.opus', '.m4a', '.aac', '.wav', '.mp3'):
        name += '.ogg'
    path = folder / name
    if not path.exists():
        tmp = path.with_name(path.name + '.part')
        gateway('GET', f"/internal/v1/uploads/{source['source_uuid']}/file", stream_to=tmp, timeout=1200)
        os.replace(tmp, path)
    digest = vi().sha256(path)
    if path.stat().st_size != meta.get('size') or digest != meta.get('sha256'):
        path.unlink(missing_ok=True)
        raise RuntimeError('网关文件校验不一致，下次重新下载')
    if m.probe_duration(path) <= 0:
        raise RuntimeError('音频无法解析')
    vi().source_update(source['id'], audio_path=str(path), audio_sha256=digest)


def report(source, user):
    m = core()
    with m.db() as c:
        rec = m.can_access_recording(c, source['recording_id'], user)
    gateway('POST', f"/internal/v1/uploads/{source['source_uuid']}/result",
            {'recording_id': rec['id'], 'title': rec['title'], 'asr_status': rec['asr_status'],
             'summary_status': rec['summary_status']})


async def verify(req: Request):
    """Check a gateway request signed with the shared key; return the JSON body."""
    body = await req.body()
    if len(body) > 32000:
        raise HTTPException(413, '请求过大')
    secret = key()
    if secret is None:
        raise HTTPException(503, '上传网关尚未配置')
    stamp = req.headers.get('x-voice-time', '')
    sig = req.headers.get('x-voice-signature', '')
    try:
        fresh = abs(time.time() - float(stamp)) < 30
    except ValueError:
        fresh = False
    expected = sign(secret, req.method, req.url.path, stamp, body)
    if not fresh or not hmac.compare_digest(expected, sig):
        raise HTTPException(401, '无效服务认证')
    try:
        return json.loads(body or b'{}')
    except ValueError:
        raise HTTPException(400, '请求格式无效')


def handle(payload):
    """Actions the gateway may run on behalf of a signed-in phone."""
    m, v = core(), vi()
    action = payload.get('action')
    if action == 'login':
        username = str(payload.get('username') or '').strip()
        password = payload.get('password') or ''
        if not username or not password or len(username) > 200 or len(password) > 1000:
            raise HTTPException(400, '请输入账号和密码')
        with m.db() as c:
            user = m.authenticate_user(c, username, password)
            if user.get('role') == 'admin':
                raise HTTPException(403, '管理员账号不能使用手机端')
            c.execute('update users set failed_login_count=0,locked_until=null,last_login_at=?,last_active_at=?,updated_at=? where id=?',
                      (m.now(), m.now(), m.now(), user['id']))
            m.audit(c, m.normalize_user(user), 'auth', '手机端登录。')
        user = m.normalize_user(user)
        return {'id': user['id'], 'name': user['name'], 'role': user['role'],
                'must_change_password': bool(user.get('must_change_password'))}
    try:
        user = v.owner(payload.get('user_id'))
    except ValueError:
        raise HTTPException(403, '用户无效或停用')
    if action in ('recordings', 'summary', 'transcript', 'detail'):
        return v.read_action(action, payload.get('arguments') or {}, user)
    raise HTTPException(400, '不支持的操作')
