"""Aham Voice as the processing provider.

Aham Voice runs on a Mac behind a reverse tunnel. Sign-in and reads go to its
backend through the tunnel (VOICE_BACKEND_URL); audio goes the other way: the
Voice worker pulls ready uploads from the /internal routes below and reports the
result. Both directions are signed with the key in GATEWAY_HOME/private/bridge-key.
"""
from __future__ import annotations

import hmac
import json
import os
import time

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse

from . import Provider


def gw():
    from .. import app
    return app


def backend(action, payload):
    base = os.environ.get('VOICE_BACKEND_URL', '').rstrip('/')
    if not base:
        raise HTTPException(503, '未配置录音服务地址')
    path = '/api/internal/mobile'
    body = json.dumps({'action': action, **payload}, ensure_ascii=False).encode()
    stamp = str(time.time())
    headers = {'Content-Type': 'application/json', 'X-Voice-Time': stamp,
               'X-Voice-Signature': gw().sign(gw().bridge_key(), 'POST', path, stamp, body)}
    try:
        with httpx.Client(timeout=25, trust_env=False) as client:
            r = client.post(base + path, content=body, headers=headers)
    except httpx.HTTPError:
        raise HTTPException(503, '录音服务暂时连不上。上传不受影响，请稍后再看纪要')
    if r.status_code != 200:
        try:
            detail = r.json().get('detail', '录音服务返回错误')
        except ValueError:
            detail = '录音服务返回错误'
        raise HTTPException(r.status_code if r.status_code in (400, 401, 403, 404, 409, 423) else 502, detail)
    return r.json()


async def worker(request: Request):
    """Authenticate a signed request from the Voice worker; return its JSON body."""
    body = await request.body()
    stamp = request.headers.get('x-voice-time', '')
    sig = request.headers.get('x-voice-signature', '')
    try:
        fresh = abs(time.time() - float(stamp)) < 30
    except ValueError:
        fresh = False
    expected = gw().sign(gw().bridge_key(), request.method, request.url.path, stamp, body)
    if not fresh or not hmac.compare_digest(expected, sig):
        raise HTTPException(401, '无效服务认证')
    try:
        return json.loads(body or b'{}')
    except ValueError:
        raise HTTPException(400, '请求格式无效')


def describe(r):
    return {'id': r['id'], 'user_id': r['user_id'], 'file_name': r['file_name'], 'size': r['size'],
            'sha256': r['sha256'], 'kind': r['kind'], 'title': r['title'],
            'recorded_at_ms': r['recorded_at_ms'], 'status': r['status']}


router = APIRouter(prefix='/internal/v1')


@router.get('/uploads/ready')
def ready(_=Depends(worker)):
    return {'items': [describe(r) for r in gw().ready_uploads()]}


@router.get('/uploads/{upload_id}')
def meta(upload_id: str, _=Depends(worker)):
    return describe(gw().upload_row(upload_id))


@router.get('/uploads/{upload_id}/file')
def file(upload_id: str, _=Depends(worker)):
    gw().upload_row(upload_id)
    path = gw().upload_path(upload_id)
    if not path.exists():
        raise HTTPException(410, '文件已清理')
    return FileResponse(path, media_type='application/octet-stream')


@router.post('/uploads/{upload_id}/claimed')
def claimed(upload_id: str, _=Depends(worker)):
    gw().upload_row(upload_id)
    gw().mark_claimed(upload_id)
    return {'ok': True}


@router.post('/uploads/{upload_id}/result')
def result(upload_id: str, payload=Depends(worker)):
    """Final result from the Voice worker: a finished recording, or `status: failed` with the reason."""
    keys = {'recording_id', 'title', 'asr_status', 'summary_status', 'status', 'stage', 'error'}
    if not isinstance(payload, dict) or set(payload) - keys:
        raise HTTPException(400, '结果格式无效')
    if payload.get('status') == 'failed':
        if not isinstance(payload.get('error'), str):
            raise HTTPException(400, '结果格式无效')
        return gw().fail_upload(upload_id, payload)
    if not isinstance(payload.get('recording_id'), str):
        raise HTTPException(400, '结果格式无效')
    return gw().finish_upload(upload_id, payload)


class AhamVoice(Provider):
    name = 'aham_voice'

    def install(self, app):
        app.include_router(router)

    def login(self, username, password):
        user = backend('login', {'username': username, 'password': password})
        return {'id': user['id'], 'name': user['name'], 'must_change_password': user.get('must_change_password', False)}

    def recordings(self, user, args):
        return backend('recordings', {'user_id': user['id'], 'arguments': args})

    def recording_part(self, user, recording_id, part, args):
        return backend(part, {'user_id': user['id'], 'arguments': {'recording_id': recording_id, **args}})


def provider():
    return AhamVoice()
