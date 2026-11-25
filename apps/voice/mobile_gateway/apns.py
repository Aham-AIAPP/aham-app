"""Apple Push Notification service, token-based authentication.

Push is optional: until all four APNS_* variables are set (they need a paid
Apple Developer account), send() records the notification as 'skipped'.
"""
from __future__ import annotations

import os
import threading
import time
from pathlib import Path

HOSTS = {'production': 'https://api.push.apple.com', 'sandbox': 'https://api.sandbox.push.apple.com'}
_lock = threading.Lock()
_cached = {'token': None, 'at': 0.0}


def configured():
    return all(os.environ.get(k) for k in ('APNS_KEY_PATH', 'APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_TOPIC'))


def provider_token():
    """APNs accepts a provider token for up to an hour; refresh it every 50 minutes."""
    import jwt
    with _lock:
        if _cached['token'] and time.time() - _cached['at'] < 3000:
            return _cached['token']
        key = Path(os.environ['APNS_KEY_PATH']).read_text()
        now = int(time.time())
        token = jwt.encode({'iss': os.environ['APNS_TEAM_ID'], 'iat': now}, key, algorithm='ES256',
                           headers={'kid': os.environ['APNS_KEY_ID']})
        _cached.update(token=token, at=now)
        return token


def send(device_token, payload, environment='production'):
    if not configured():
        return 'skipped'
    import httpx
    url = f"{HOSTS[environment]}/3/device/{device_token}"
    headers = {'authorization': 'bearer ' + provider_token(), 'apns-topic': os.environ['APNS_TOPIC'],
               'apns-push-type': 'alert', 'apns-priority': '10'}
    with httpx.Client(http2=True, timeout=15, trust_env=False) as client:
        r = client.post(url, json=payload, headers=headers)
    if r.status_code == 200:
        return 'sent'
    raise RuntimeError(f'APNs {r.status_code}: {r.text[:200]}')
