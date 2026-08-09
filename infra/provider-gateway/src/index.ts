type Provider = "alchemy" | "coinbase" | "privy" | "reown" | "github";

type Env = {
  WEBHOOK_DB: D1Database;
  WEBHOOK_QUEUE: Queue<QueuedWebhookEvent>;
  APP_ORIGIN: string;
  LOCAL_PROCESSOR_ENABLED: string;
  LOCAL_PROCESSOR_URL?: string;
  LOCAL_PROCESSOR_TOKEN?: string;

  ALCHEMY_SIGNING_KEY?: string;
  ALCHEMY_MOIST_SIGNING_KEY?: string;
  ALCHEMY_USDC_SIGNING_KEY?: string;
  ALCHEMY_DCC3_SIGNING_KEY?: string;
  ALCHEMY_9E9_SIGNING_KEY?: string;
};

type ExecutionContextLike = ExecutionContext;

type AlchemyPayload = {
  webhookId?: string;
  id?: string;
  createdAt?: string;
  type?: string;
  event?: unknown;
};

type QueuedWebhookEvent = {
  id: string;
  provider: Provider;
  capability: string;
  webhookId?: string;
  providerEventId?: string;
  monitor?: string;
  monitoredAddress?: string;
  eventType?: string;
  receivedAt: string;
  payload: unknown;
};

type NormalizedFields = {
  chain?: string;
  txHash?: string;
  blockNumber?: number;
  fromAddress?: string;
  toAddress?: string;
  contractAddress?: string;
  methodSelector?: string;
};

const PROVIDERS: Provider[] = ["alchemy", "coinbase", "privy", "reown", "github"];

const ALCHEMY_WEBHOOKS: Record<string, { monitor: string; address?: string; secret: keyof Env }> = {
  wh_axh9cg25g9dusr0w: {
    monitor: "MOIST",
    secret: "ALCHEMY_MOIST_SIGNING_KEY",
  },
  wh_axg3dr6rlm3b57w9: {
    monitor: "USDC Transfers",
    secret: "ALCHEMY_USDC_SIGNING_KEY",
  },
  wh_f9cif705m28bj5fq: {
    monitor: "DCC3",
    address: "0x75e732608Bc17B23D01f01728562Ee844196DCC3",
    secret: "ALCHEMY_DCC3_SIGNING_KEY",
  },
  wh_zfo0r9e0l6ixeaj4: {
    monitor: "9e9",
    address: "0x1b4C289c4f6e0565f1E432654254485c490679e9",
    secret: "ALCHEMY_9E9_SIGNING_KEY",
  },
};

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContextLike): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return json({ ok: true, service: "moist-provider-gateway", now: new Date().toISOString() });
    }

    const segments = url.pathname.split("/").filter(Boolean);
    const provider = segments[0] as Provider | undefined;
    const capability = segments[1];

    if (!provider || !PROVIDERS.includes(provider)) {
      return json({ error: "unknown_provider", providers: PROVIDERS }, 404);
    }

    if (!capability) {
      return json({
        provider,
        capabilities: provider === "alchemy"
          ? ["webhooks", "rpc", "status", "events", "aa", "monitor"]
          : ["webhooks"],
      });
    }

    if (capability !== "webhooks") {
      return json({
        error: "capability_not_implemented",
        provider,
        capability,
      }, 501);
    }

    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405, { Allow: "POST" });
    }

    if (provider === "alchemy") {
      return handleAlchemyWebhook(request, env, ctx);
    }

    return json({
      error: "provider_webhook_adapter_not_implemented",
      provider,
      route: `/${provider}/webhooks`,
    }, 501);
  },

  async queue(batch: MessageBatch<QueuedWebhookEvent>, env: Env): Promise<void> {
    for (const message of batch.messages) {
      const event = message.body;
      try {
        await processQueuedEvent(event, env);
        message.ack();
      } catch (error) {
        console.error(JSON.stringify({
          level: "error",
          phase: "queue_consumer",
          event_id: event.id,
          provider: event.provider,
          error: error instanceof Error ? error.message : String(error),
        }));
        message.retry();
      }
    }
  },
};

async function handleAlchemyWebhook(
  request: Request,
  env: Env,
  _ctx: ExecutionContextLike,
): Promise<Response> {
  const receivedAt = new Date().toISOString();
  const rawBody = await request.text();
  const signature = request.headers.get("x-alchemy-signature");

  if (!signature) {
    return json({ error: "missing_alchemy_signature" }, 401);
  }

  let payload: AlchemyPayload;
  try {
    payload = JSON.parse(rawBody) as AlchemyPayload;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const webhookConfig = payload.webhookId ? ALCHEMY_WEBHOOKS[payload.webhookId] : undefined;
  const signingKey = webhookConfig
    ? (env[webhookConfig.secret] as string | undefined) ?? env.ALCHEMY_SIGNING_KEY
    : env.ALCHEMY_SIGNING_KEY;

  if (!signingKey) {
    console.error(JSON.stringify({
      level: "error",
      phase: "signature_verification",
      provider: "alchemy",
      webhook_id: payload.webhookId,
      error: "signing_key_not_configured",
    }));
    return json({ error: "signing_key_not_configured" }, 503);
  }

  const signatureValid = await verifyHmacSha256(rawBody, signature, signingKey);
  if (!signatureValid) {
    console.warn(JSON.stringify({
      level: "warn",
      phase: "signature_verification",
      provider: "alchemy",
      webhook_id: payload.webhookId,
      signature_valid: false,
    }));
    return json({ error: "invalid_signature" }, 401);
  }

  const providerEventId = payload.id ?? crypto.randomUUID();
  const id = `alchemy:${providerEventId}`;
  const normalized = normalizeAlchemy(payload);
  const monitor = webhookConfig?.monitor;
  const monitoredAddress = webhookConfig?.address;

  const result = await env.WEBHOOK_DB.prepare(`
    INSERT OR IGNORE INTO webhook_events (
      id, provider, capability, webhook_id, provider_event_id, monitor,
      monitored_address, event_type, chain, tx_hash, block_number,
      from_address, to_address, contract_address, method_selector,
      signature_valid, raw_payload, received_at, processing_status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    id,
    "alchemy",
    "webhooks",
    payload.webhookId ?? null,
    providerEventId,
    monitor ?? null,
    monitoredAddress ?? null,
    payload.type ?? null,
    normalized.chain ?? null,
    normalized.txHash ?? null,
    normalized.blockNumber ?? null,
    normalized.fromAddress ?? null,
    normalized.toAddress ?? null,
    normalized.contractAddress ?? null,
    normalized.methodSelector ?? null,
    1,
    rawBody,
    receivedAt,
    "received",
  ).run();

  const inserted = Number(result.meta.changes ?? 0) > 0;

  if (inserted) {
    const queuedEvent: QueuedWebhookEvent = {
      id,
      provider: "alchemy",
      capability: "webhooks",
      webhookId: payload.webhookId,
      providerEventId,
      monitor,
      monitoredAddress,
      eventType: payload.type,
      receivedAt,
      payload,
    };

    await env.WEBHOOK_QUEUE.send(queuedEvent);
    await env.WEBHOOK_DB.prepare(`
      UPDATE webhook_events
      SET queued_at = ?, processing_status = 'queued'
      WHERE id = ?
    `).bind(new Date().toISOString(), id).run();
  }

  console.log(JSON.stringify({
    level: "info",
    phase: "ingress",
    provider: "alchemy",
    capability: "webhooks",
    event_id: id,
    webhook_id: payload.webhookId,
    monitor,
    monitored_address: monitoredAddress,
    event_type: payload.type,
    signature_valid: true,
    inserted,
    tx_hash: normalized.txHash,
    from: normalized.fromAddress,
    to: normalized.toAddress,
    contract: normalized.contractAddress,
  }));

  // A duplicate is still a successful delivery. Returning quickly prevents
  // provider retry storms while preserving idempotency in D1.
  return json({ ok: true, id, duplicate: !inserted }, 200);
}

async function processQueuedEvent(event: QueuedWebhookEvent, env: Env): Promise<void> {
  const now = new Date().toISOString();

  if (env.LOCAL_PROCESSOR_ENABLED !== "true" || !env.LOCAL_PROCESSOR_URL) {
    await env.WEBHOOK_DB.prepare(`
      UPDATE webhook_events
      SET processing_status = 'stored', processed_at = ?, last_error = NULL
      WHERE id = ?
    `).bind(now, event.id).run();
    return;
  }

  const attemptRow = await env.WEBHOOK_DB.prepare(`
    SELECT processing_attempts FROM webhook_events WHERE id = ?
  `).bind(event.id).first<{ processing_attempts: number }>();
  const attempt = (attemptRow?.processing_attempts ?? 0) + 1;

  const headers = new Headers({
    "content-type": "application/json",
    "x-moist-event-id": event.id,
    "x-moist-provider": event.provider,
  });
  if (env.LOCAL_PROCESSOR_TOKEN) {
    headers.set("authorization", `Bearer ${env.LOCAL_PROCESSOR_TOKEN}`);
  }

  let statusCode: number | null = null;
  let deliveryError: string | null = null;

  try {
    const response = await fetch(env.LOCAL_PROCESSOR_URL, {
      method: "POST",
      headers,
      body: JSON.stringify(event),
    });
    statusCode = response.status;
    if (!response.ok) {
      throw new Error(`local_processor_http_${response.status}`);
    }

    await env.WEBHOOK_DB.batch([
      env.WEBHOOK_DB.prepare(`
        UPDATE webhook_events
        SET processing_status = 'processed', processed_at = ?,
            processing_attempts = ?, last_error = NULL
        WHERE id = ?
      `).bind(now, attempt, event.id),
      env.WEBHOOK_DB.prepare(`
        INSERT INTO processor_deliveries
          (event_id, destination, attempt, status_code, delivered_at, error)
        VALUES (?, ?, ?, ?, ?, NULL)
      `).bind(event.id, env.LOCAL_PROCESSOR_URL, attempt, statusCode, now),
    ]);
  } catch (error) {
    deliveryError = error instanceof Error ? error.message : String(error);

    await env.WEBHOOK_DB.batch([
      env.WEBHOOK_DB.prepare(`
        UPDATE webhook_events
        SET processing_status = 'retrying', processing_attempts = ?, last_error = ?
        WHERE id = ?
      `).bind(attempt, deliveryError, event.id),
      env.WEBHOOK_DB.prepare(`
        INSERT INTO processor_deliveries
          (event_id, destination, attempt, status_code, delivered_at, error)
        VALUES (?, ?, ?, ?, ?, ?)
      `).bind(event.id, env.LOCAL_PROCESSOR_URL, attempt, statusCode, now, deliveryError),
    ]);

    throw error;
  }
}

function normalizeAlchemy(payload: AlchemyPayload): NormalizedFields {
  const root = asRecord(payload.event);
  const activity = firstRecord(root.activity);
  const tx = asRecord(root.transaction ?? root.tx ?? activity);
  const log = firstRecord(root.logs);

  const input = stringValue(tx.input ?? tx.data ?? activity.input ?? root.input);

  return {
    chain: stringValue(root.network ?? root.chain ?? root.chainId),
    txHash: stringValue(
      root.hash ?? root.transactionHash ?? tx.hash ?? tx.transactionHash ?? activity.hash,
    ),
    blockNumber: numberValue(root.blockNumber ?? tx.blockNumber ?? activity.blockNum),
    fromAddress: stringValue(root.from ?? tx.from ?? activity.fromAddress),
    toAddress: stringValue(root.to ?? tx.to ?? activity.toAddress),
    contractAddress: stringValue(
      activity.rawContract && asRecord(activity.rawContract).address
        ? asRecord(activity.rawContract).address
        : log.address ?? root.contractAddress,
    ),
    methodSelector: input && input.startsWith("0x") && input.length >= 10
      ? input.slice(0, 10)
      : undefined,
  };
}

async function verifyHmacSha256(body: string, signature: string, secret: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign("HMAC", key, encoder.encode(body));
  const expected = [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  return timingSafeStringEqual(expected.toLowerCase(), signature.toLowerCase());
}

function timingSafeStringEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i += 1) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

function asRecord(value: unknown): Record<string, any> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, any>
    : {};
}

function firstRecord(value: unknown): Record<string, any> {
  return Array.isArray(value) && value.length > 0 ? asRecord(value[0]) : {};
}

function stringValue(value: unknown): string | undefined {
  if (typeof value === "string" && value.length > 0) return value;
  if (typeof value === "number" || typeof value === "bigint") return String(value);
  return undefined;
}

function numberValue(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = value.startsWith("0x") ? Number.parseInt(value, 16) : Number(value);
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  return undefined;
}

function json(
  value: unknown,
  status = 200,
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      ...headers,
    },
  });
}
