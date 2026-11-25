# Mobile upload gateway

The mobile gateway lets a phone or desktop client upload recordings and read summaries while the Voice backend stays private on the Mac. It runs on the cloud server next to the MCP gateway. Uploads succeed while the Mac is offline; sign-in and reads need the Mac online.

## Data flow

1. The client signs in at `POST /v1/login`. The gateway forwards the username and password to the Voice backend with a signed request and keeps neither. It issues its own bearer token, valid for 90 days, and stores only its hash.
2. The client creates an upload with `POST /v1/uploads` (file name, size, SHA-256, kind `note`, `call` or `import`). The same user, size and SHA-256 return the existing upload, so a retry never creates a duplicate.
3. The client sends chunks of at most 8 MB with `PUT /v1/uploads/{id}/chunk?offset=N`, in order. `GET /v1/uploads/{id}` returns `received`, so an interrupted upload resumes from that offset.
4. `POST /v1/uploads/{id}/complete` verifies the size and SHA-256. A mismatch discards the received bytes and the client starts over.
5. The Voice worker on the Mac polls `GET /internal/v1/uploads/ready` every 60 seconds, downloads the file, marks it claimed and runs download → import → transcribe → summary → title → report → done. The `report` stage posts the result to the gateway.
6. The gateway records the result and sends one APNs notification per upload. A repeated report does not notify again.

Reads (`GET /v1/recordings`, `/v1/recordings/{id}/summary|transcript|detail`) go to the backend through the tunnel, which checks the user's current status and recording permissions on every call.

## Pluggable provider

`GATEWAY_PROVIDER` selects the processing service; the default is `aham_voice`. A provider subclasses `mobile_gateway.providers.Provider` and implements `install`, `login`, `upload_ready`, `recordings` and `recording_part`. The client API under `/v1` does not change when the provider changes.

## Gateway configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `GATEWAY_HOME` | `~/.cache/voice-mobile-gateway` | Database, uploads and `private/` |
| `GATEWAY_PROVIDER` | `aham_voice` | Processing provider |
| `GATEWAY_MAX_MB` | `2048` | Largest accepted file |
| `GATEWAY_KEEP_DAYS` | `7` | Days to keep audio after the Mac has claimed it |
| `VOICE_BACKEND_URL` | none | Backend address through the tunnel, for example `http://127.0.0.1:18768` |
| `APNS_KEY_PATH`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC` | none | APNs token authentication; all four are needed |

APNs needs a paid Apple Developer Program membership. Until all four `APNS_*` variables are set, notifications are recorded as `skipped` and clients see results by refreshing.

`GATEWAY_HOME/private/bridge-key` holds 32 random bytes. Copy the same bytes to `RECORDING_AI_HOME/private/mobile-gateway-key` on the Mac. Every request between the gateway and the Mac is signed with HMAC-SHA256 over method, path, timestamp and body, and is rejected after 30 seconds.

Install and run:

```sh
python3 -m venv /opt/voice-mobile-gateway
/opt/voice-mobile-gateway/bin/pip install -r apps/voice/mobile_gateway/requirements.txt
cd apps/voice && /opt/voice-mobile-gateway/bin/uvicorn mobile_gateway.app:app --host 127.0.0.1 --port 8780
```

## Mac configuration

Create `RECORDING_AI_HOME/private/mobile-gateway.json`:

```json
{"gateway_url": "https://voice.example.com/voice/mobile"}
```

The worker enables the mobile source only when this file and `mobile-gateway-key` exist. Errors from the last scan appear in `voice_state` under `mobile_last_error`.

Extend the existing reverse SSH tunnel with a second forward from the cloud server loopback 18768 to the Mac loopback 8000. The backend accepts `/api/internal/mobile` only with a valid signature; nginx must not expose port 18768.

## nginx

```nginx
location /voice/mobile/ {
    proxy_pass http://127.0.0.1:8780/;
    proxy_request_buffering off;
    client_max_body_size 9m;
    proxy_read_timeout 120s;
}
```

`client_max_body_size` covers one 8 MB chunk.

## Limits

- Login is limited to 10 attempts per IP in 5 minutes on the gateway. The backend also locks an account for 15 minutes after 5 failed passwords.
- Administrators cannot sign in through the mobile gateway.
- Audio is deleted `GATEWAY_KEEP_DAYS` days after the Mac claims it; upload records remain. Unfinished uploads expire after 30 days.
