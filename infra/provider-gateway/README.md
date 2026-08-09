# Moist Provider Gateway

Provider-first Cloudflare ingress for `app.moistbandz.com`.

## Canonical route contract

```text
/<provider>/<capability>
```

Initial namespaces:

```text
/alchemy/webhooks
/alchemy/rpc        (reserved)
/alchemy/status     (reserved)
/alchemy/events     (reserved)
/alchemy/aa         (reserved)
/alchemy/monitor    (reserved)

/coinbase/webhooks (adapter reserved)
/privy/webhooks    (adapter reserved)
/reown/webhooks    (adapter reserved)
/github/webhooks   (adapter reserved)
```

Only the Alchemy webhook adapter is active in the first implementation. Other namespaces intentionally return `501` until their provider-specific signature verification is implemented.

## Ingress flow

```text
Provider
  |
  | HTTPS
  v
app.moistbandz.com/<provider>/webhooks
  |
  v
Cloudflare Worker
  |-- validate provider signature using raw request body
  |-- normalize envelope metadata
  |-- INSERT OR IGNORE into D1 (idempotent durable receipt)
  |-- enqueue Cloudflare Queue message
  `-- return 2xx quickly
           |
           v
     Cloudflare Queue
           |
           v
    Worker queue consumer
           |
           | optional private delivery
           v
 Cloudflare Tunnel / private service
           |
           v
    localhost processor
 decode / trace / enrich / execute
```

D1 is the durable source of truth. The localhost processor is downstream and may be offline without making the public webhook endpoint unavailable.

## Alchemy webhook mapping

The current Alchemy webhook IDs are mapped to env-only signing keys:

| Monitor | Webhook ID | Monitored address | Secret binding |
|---|---|---|---|
| MOIST | `wh_axh9cg25g9dusr0w` | custom/GraphQL | `ALCHEMY_MOIST_SIGNING_KEY` |
| USDC Transfers | `wh_axg3dr6rlm3b57w9` | custom/GraphQL | `ALCHEMY_USDC_SIGNING_KEY` |
| DCC3 | `wh_f9cif705m28bj5fq` | `0x75e732608Bc17B23D01f01728562Ee844196DCC3` | `ALCHEMY_DCC3_SIGNING_KEY` |
| 9e9 | `wh_zfo0r9e0l6ixeaj4` | `0x1b4C289c4f6e0565f1E432654254485c490679e9` | `ALCHEMY_9E9_SIGNING_KEY` |

Alchemy verification uses HMAC-SHA256 over the **raw request body** and compares it to `X-Alchemy-Signature`.

## Durable event fields

`webhook_events` stores both the original payload and searchable normalized fields:

```text
provider
capability
webhook_id
provider_event_id
monitor
monitored_address
event_type
chain
tx_hash
block_number
from_address
to_address
contract_address
method_selector
signature_valid
raw_payload
received_at
queued_at
processed_at
processing_status
processing_attempts
last_error
```

This is the layer used to answer which addresses are actually flowing through the integration rather than only which addresses are configured in the upstream provider.

## Cloudflare resources

The Worker expects:

- D1 binding `WEBHOOK_DB`
- Queue binding `WEBHOOK_QUEUE`
- queue `moist-webhook-events`
- dead-letter queue `moist-webhook-events-dlq`
- Workers Logs/Observability enabled
- production Workers routes scoped to the provider namespaces on `app.moistbandz.com`

`wrangler.jsonc` intentionally does not contain secret values.

## Secret configuration

Set production secrets using Cloudflare secret bindings, for example:

```bash
npx wrangler secret put ALCHEMY_MOIST_SIGNING_KEY
npx wrangler secret put ALCHEMY_USDC_SIGNING_KEY
npx wrangler secret put ALCHEMY_DCC3_SIGNING_KEY
npx wrangler secret put ALCHEMY_9E9_SIGNING_KEY
```

For local development, copy `.dev.vars.example` to `.dev.vars`. Never commit `.dev.vars`.

## Database setup

From `infra/provider-gateway`:

```bash
npm install
npx wrangler d1 create moist-webhooks
npm run db:migrate:remote
```

Cloudflare/Wrangler may provision resource IDs automatically depending on the deployment flow. Treat `wrangler.jsonc` as the configuration source of truth and verify the final D1/Queue bindings in the Cloudflare dashboard after first deployment.

## Local processor / Tunnel

The queue consumer supports optional forwarding to `LOCAL_PROCESSOR_URL` only when:

```text
LOCAL_PROCESSOR_ENABLED=true
```

Recommended production boundary:

```text
Worker/Queue -> Cloudflare private network/Tunnel -> HTTPS localhost service
```

Do not expose the localhost service directly to the public Internet. Do not use `noTLSVerify` as the permanent configuration. Install a trusted Cloudflare Origin CA/private-origin certificate and validate the origin certificate.

`LOCAL_PROCESSOR_TOKEN` is an optional second application-layer credential and must also be stored as a Cloudflare secret.

## Certificate/TLS TODO

- verify Cloudflare edge certificate coverage for `app.moistbandz.com`
- use Full (strict) TLS for origin connections
- create/install the private-origin certificate for the localhost service
- configure `cloudflared` Tunnel to the localhost HTTPS listener
- configure origin server name / CA trust
- keep all private keys outside Git and outside normal Worker vars
- optionally add mTLS once the private service path is established

## Provider adapter TODO

Each provider adapter must own its exact authentication algorithm. Do not share a generic signature verifier across providers unless their protocol is actually identical.

Planned adapters:

- Alchemy: active
- Coinbase: reserved
- Privy: reserved
- Reown: reserved
- GitHub: reserved

For each new provider:

1. preserve raw bytes/body
2. verify provider signature/authentication before parsing business data
3. derive a stable provider event ID for idempotency
4. normalize searchable envelope fields
5. persist raw + normalized data to D1
6. enqueue processing
7. return success quickly
8. add retry/DLQ tests

## Cutover checklist

Do not repoint the live Alchemy webhooks until all of these are true:

- [ ] Cloudflare account/plugin access is connected
- [ ] DNS for `app.moistbandz.com` is confirmed proxied through Cloudflare
- [ ] Worker is deployed
- [ ] D1 is created and migration `0001_webhook_events.sql` applied
- [ ] producer queue exists
- [ ] dead-letter queue exists
- [ ] all Alchemy signing keys are configured as encrypted secrets
- [ ] `/health` returns `200`
- [ ] signed test delivery to `/alchemy/webhooks` returns `200`
- [ ] test event appears in D1
- [ ] test event is queued exactly once
- [ ] duplicate delivery remains `200` without duplicate storage
- [ ] Worker logs show provider/webhook/event/tx/address metadata
- [ ] Tunnel/private localhost processing path is configured
- [ ] TLS certificate validation is enabled end-to-end
- [ ] replace the old ngrok Alchemy URL with `https://app.moistbandz.com/alchemy/webhooks`
- [ ] re-enable Alchemy webhooks
- [ ] verify no recurrence of `TOO_MANY_ERRORS`
- [ ] investigate `CAPPED_CAPACITY` separately for the 9e9 monitor

## Current status

Architecture baseline is implemented. Production deployment and provider cutover are intentionally pending Cloudflare account access and secret/resource configuration.
