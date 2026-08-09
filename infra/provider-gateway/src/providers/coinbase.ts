export const COINBASE_CAPABILITIES = {
  webhooks: {
    route: "/coinbase/webhooks",
    mode: "ingress",
    purpose: "Coinbase event ingestion into the shared D1 + Queue pipeline",
  },
  advancedTrade: {
    route: "/coinbase/advanced-trade",
    mode: "api-proxy",
    upstream: "https://api.coinbase.com/api/v3/brokerage",
    subroutes: [
      "accounts",
      "orders",
      "fills",
      "products",
      "portfolios",
      "fees",
      "market-data",
      "websocket",
    ],
  },
  embeddedWallets: {
    route: "/coinbase/embedded-wallets",
    mode: "wallet-control-plane",
    subroutes: [
      "auth",
      "accounts",
      "smart-accounts",
      "eip7702",
      "send",
      "sign",
      "status",
    ],
  },
  paymaster: {
    route: "/coinbase/paymaster",
    mode: "json-rpc-proxy",
    subroutes: [
      "rpc",
      "policies",
      "sponsorships",
      "status",
    ],
  },
  bundler: {
    route: "/coinbase/bundler",
    mode: "json-rpc-alias",
    sharedWith: "/coinbase/paymaster/rpc",
    methods: [
      "eth_supportedEntryPoints",
      "eth_getUserOperationByHash",
      "eth_getUserOperationReceipt",
      "eth_sendUserOperation",
      "eth_estimateUserOperationGas",
    ],
  },
} as const;

export type CoinbaseCapability = keyof typeof COINBASE_CAPABILITIES;

/**
 * Security boundary:
 * - Never expose Coinbase secret API keys to the browser.
 * - Browser-facing Embedded Wallet client identifiers/origin configuration stay distinct
 *   from server-side secret/JWT material.
 * - Paymaster/Bundler policy enforcement remains upstream in CDP, while this gateway
 *   records requests/results for observability and local processing.
 * - Advanced Trade order placement and account endpoints are server-side only.
 */
