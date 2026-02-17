# Warm Pool Scenario: Instant Provisioning with kata-remote

Demonstrates the Warm Pool pattern using kata-remote runtime. A SandboxWarmPool pre-creates 2 peer-pod VMs so that when a user submits a SandboxClaim, the sandbox is ready instantly -- no VM boot, no image pull, no waiting.

![Warmpool Demo](warmpool-demo.gif)

## What the demo shows

| Step | Resource | What happens |
|---|---|---|
| 1 | SandboxTemplate | Defines the sandbox spec: kata-remote runtime, python:3.11-slim, HTTP server on port 8888 |
| 2 | SandboxWarmPool (2 replicas) | Controller provisions 2 peer-pod VMs via Cloud API Adaptor |
| 3 | SandboxClaim | User claims a sandbox -- controller adopts a pre-warmed pod instantly |
| 4 | Auto-replenish | Pool detects the claimed pod is gone and provisions a replacement |

## Without vs With Warm Pool

| | Without Warm Pool | With Warm Pool |
|---|---|---|
| VM provisioning | On-demand (slow) | Pre-provisioned |
| Image pull | Every request | Already cached |
| User wait time | Minutes | Seconds |
| Pool management | Manual | Auto-replenish |

## Running

```bash
asciinema rec warmpool-demo.cast --cols 120 --rows 45
./warmpool-demo.sh
# Ctrl+D to stop
agg warmpool-demo.cast warmpool-demo.gif
```

## Prerequisites

Same as the [main demo](../../README.md) -- a cluster with agent-sandbox and a `kata-remote` RuntimeClass installed (requires Cloud API Adaptor / peer-pods).
