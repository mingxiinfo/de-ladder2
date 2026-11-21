// Express `trust proxy` for the Launcher API (de-ladder2 docs/47).
//
// L1: MX_HTTP_TRUST_PROXY_HOPS=1 — the Internal gateway Caddy is the only hop, so the
// client is the last X-Forwarded-For entry.
// L2: host-nginx → Gateway `internal` (NGINX Gateway Fabric) → Launcher, no Caddy on the
// API path. How many entries the gateway appends depends on whether it rewrites the client
// address, so trust by address range instead of by count: Express then takes the right-most
// X-Forwarded-For entry that is not one of these proxies.
import { parseTrustedProxyCidrs } from '../config.js';

export type TrustProxySetting = number | string[] | null;

export function httpTrustProxySetting(env: NodeJS.ProcessEnv = process.env): TrustProxySetting {
  const cidrs = parseTrustedProxyCidrs(env.MX_HTTP_TRUST_PROXY_CIDRS);
  if (cidrs.length) return cidrs;
  const hops = Number(env.MX_HTTP_TRUST_PROXY_HOPS);
  return Number.isInteger(hops) && hops > 0 ? hops : null;
}
