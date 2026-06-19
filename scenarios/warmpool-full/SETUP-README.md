# Warm Pool Setup via Sandbox Router

End-to-end setup for warm pool scenarios in this folder. A `SandboxWarmPool` pre-provisions sandboxes; a `SandboxClaim` adopts one instantly; you reach the workload through the sandbox router on OpenShift.

Two kata variants are included:

| Example | Path | Runtime | Use when |
|---------|------|---------|----------|
| **kata-remote** | `kata-warmpool/` | `kata-remote` | Peer pods on cloud (Azure, AWS, GCP) |
| **kata bare metal** | `kata-bm-warmpool/` | `kata` | OSC kata on bare-metal nodes |

## Prerequisites

- [agent-sandbox](../../../install.md) installed on the cluster
- [OpenShift sandboxed containers (OSC)](https://docs.redhat.com/en/documentation/openshift_sandboxed_containers/1.10/html/deploying_openshift_sandboxed_containers/about-osc) configured for your platform
- Matching RuntimeClass for the example you run: `kata-remote` (peer pods) or `kata` (bare metal)
- Sandbox router deployed in `agent-sandbox-system` (see [router scenario](../router/README.md) if you have not installed it yet)
- `oc` CLI logged in

## 1. Expose the sandbox router

Create an edge Route to the router Service in `agent-sandbox-system`:

```bash
oc create route edge agent-sandbox-router \
  --service=sandbox-router-svc \
  --port=8080 \
  -n agent-sandbox-system
```

Save the Route hostname for later:

```bash
export ROUTE_HOST=$(oc get route agent-sandbox-router \
  -o jsonpath='{.spec.host}' \
  -n agent-sandbox-system)
echo "$ROUTE_HOST"
```

---

## Example A: kata-remote warm pool

Uses `runtimeClassName: kata-remote` for peer-pod VMs on supported cloud platforms.

### A.1 Deploy the warm pool

```bash
oc apply -f kata-warmpool/kata-warmpool.yaml
```

Wait until the pool has ready replicas:

```bash
oc get sandboxwarmpool kata-warm-pool
oc get pods -l agents.x-k8s.io/warm-pool-sandbox
```

### A.2 Claim a sandbox

```bash
oc apply -f kata-warmpool/kata-claim.yaml
```

### A.3 Test access through the router

```bash
export SANDBOX_ID=$(oc get sandboxclaim kata-claim \
  -o jsonpath='{.metadata.annotations.agents\.x-k8s\.io/sandbox-name}')
echo "$SANDBOX_ID"

curl -sS \
  -H "X-Sandbox-ID: ${SANDBOX_ID}" \
  -H "X-Sandbox-Port: 8888" \
  -H "X-Sandbox-Namespace: default" \
  "https://${ROUTE_HOST}/"
```

A successful response includes JSON such as `{"status": "ready", "pool": "warm-pool"}`. The `/info` endpoint reports `"runtime": "kata-remote"`.

---

## Example B: kata bare-metal warm pool

Uses `runtimeClassName: kata` for VM-isolated sandboxes on bare-metal OSC nodes (no peer pods).

### B.1 Deploy the warm pool

```bash
oc apply -f kata-bm-warmpool/kata-warmpool.yaml
```

Wait until the pool has ready replicas:

```bash
oc get sandboxwarmpool kata-bm-warm-pool
oc get pods -l agents.x-k8s.io/warm-pool-sandbox
```

### B.2 Claim a sandbox

```bash
oc apply -f kata-bm-warmpool/kata-claim.yaml
oc wait --for=condition=Ready sandboxclaim/kata-bm-claim --timeout=300s
```

### B.3 Test access through the router

```bash
export SANDBOX_ID=$(oc get sandboxclaim kata-bm-claim \
  -o jsonpath='{.metadata.annotations.agents\.x-k8s\.io/sandbox-name}')
echo "$SANDBOX_ID"

curl -sS \
  -H "X-Sandbox-ID: ${SANDBOX_ID}" \
  -H "X-Sandbox-Port: 8888" \
  -H "X-Sandbox-Namespace: default" \
  "https://${ROUTE_HOST}/"
```

A successful response includes JSON such as `{"status": "ready", "pool": "warm-pool"}`. The `/info` endpoint reports `"runtime": "kata"`.

You can also hit `/health` or `/info` on either example:

```bash
curl -sS \
  -H "X-Sandbox-ID: ${SANDBOX_ID}" \
  -H "X-Sandbox-Port: 8888" \
  -H "X-Sandbox-Namespace: default" \
  "https://${ROUTE_HOST}/health"
```

---

## Cleanup

Remove resources in reverse order. Resolve the adopted sandbox name before deleting each claim.

**kata-remote example:**

```bash
SANDBOX_ID=$(oc get sandboxclaim kata-claim \
  -o jsonpath='{.metadata.annotations.agents\.x-k8s\.io/sandbox-name}' 2>/dev/null)

oc delete -f kata-warmpool/kata-claim.yaml --ignore-not-found --wait=false
[[ -n "$SANDBOX_ID" ]] && oc delete sandbox "$SANDBOX_ID" --ignore-not-found --wait=false
oc delete -f kata-warmpool/kata-warmpool.yaml --ignore-not-found --wait=false
```

**kata bare-metal example:**

```bash
SANDBOX_ID=$(oc get sandboxclaim kata-bm-claim \
  -o jsonpath='{.metadata.annotations.agents\.x-k8s\.io/sandbox-name}' 2>/dev/null)

oc delete -f kata-bm-warmpool/kata-claim.yaml --ignore-not-found --wait=false
[[ -n "$SANDBOX_ID" ]] && oc delete sandbox "$SANDBOX_ID" --ignore-not-found --wait=false
oc delete -f kata-bm-warmpool/kata-warmpool.yaml --ignore-not-found --wait=false
```

**Other manifests in this folder:**

```bash
oc delete -f simple-warmpool/simple-claim.yaml --ignore-not-found --wait=false
oc delete -f simple-warmpool/simple-warmpool.yaml --ignore-not-found --wait=false
oc delete -f simple-pod.yaml --ignore-not-found --wait=false
oc delete -f simple-kata.yaml --ignore-not-found --wait=false
```

## Other manifests in this folder

| Path | Purpose |
|------|---------|
| `kata-warmpool/` | Warm pool with `kata-remote` (peer pods, cloud) |
| `kata-bm-warmpool/` | Warm pool with `kata` (bare-metal OSC) |
| `simple-warmpool/` | Warm pool without kata (default container runtime) |
| `simple-pod.yaml` | Standalone Pod + Service + Route (no sandbox API) |
| `simple-kata.yaml` | Standalone `kata-remote` Pod + Service + Route (no warm pool) |

## Troubleshooting

- **Route or router errors** — Confirm the router pod is Running in `agent-sandbox-system` and `/healthz` responds on port 8080.
- **Claim not Ready** — Check `oc describe sandboxclaim <claim-name>` and warm pool status; VM provisioning can take several minutes (`kata-remote` peer pods often longer than bare-metal `kata`).
- **curl fails with 502** — Verify `SANDBOX_ID`, namespace (`default`), and port (`8888`) match the claimed sandbox and its template manifest.
- **Wrong runtime** — Use `kata-warmpool/` on cloud peer-pod clusters and `kata-bm-warmpool/` on bare-metal OSC; mixing them will fail if the RuntimeClass is not available.
