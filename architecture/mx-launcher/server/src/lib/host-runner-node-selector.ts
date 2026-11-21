// L2 (de-ladder2 docs/47): pin the Internal host-runner DaemonSet that Launcher creates
// ("Ensure K8s Fallback") to the nodes that hold the service peer. L1 is a single node and
// leaves it unset, so the DaemonSet keeps running everywhere.
//
// MX_INTERNAL_HOST_RUNNER_NODE_SELECTOR="mx.ladder2/site-peer=true[,key=value…]"
const LABEL_KEY = /^([a-z0-9]([-a-z0-9.]*[a-z0-9])?\/)?[A-Za-z0-9]([-A-Za-z0-9_.]*[A-Za-z0-9])?$/;
const LABEL_VALUE = /^([A-Za-z0-9]([-A-Za-z0-9_.]*[A-Za-z0-9])?)?$/;

export function parseNodeSelector(raw: string | undefined): Record<string, string> | null {
  if (!raw?.trim()) return null;
  const selector: Record<string, string> = {};
  for (const item of raw.split(/[\s,;]+/).map((part) => part.trim()).filter(Boolean)) {
    const at = item.indexOf('=');
    const key = at > 0 ? item.slice(0, at) : '';
    const value = at > 0 ? item.slice(at + 1) : '';
    if (!LABEL_KEY.test(key) || key.length > 316 || !LABEL_VALUE.test(value) || value.length > 63) {
      throw new Error(`MX_INTERNAL_HOST_RUNNER_NODE_SELECTOR: "${item}" is not key=value with valid Kubernetes label syntax`);
    }
    selector[key] = value;
  }
  return Object.keys(selector).length ? selector : null;
}

export function hostRunnerNodeSelector(env: NodeJS.ProcessEnv = process.env): Record<string, string> | null {
  return parseNodeSelector(env.MX_INTERNAL_HOST_RUNNER_NODE_SELECTOR);
}
