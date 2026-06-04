# Router Scenario: Browser Access to Agent Sandboxes

Use the [sandbox-router](https://github.com/kubernetes-sigs/agent-sandbox/tree/main/clients/python/agentic-sandbox-client/sandbox-router) to reach sandbox workloads from a browser. The router runs in the cluster; you expose it with an OpenShift Route and send routing headers from Chrome (via [ModHeader](https://modheader.com/)).

## Prerequisites

- OpenShift cluster with [agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox) installed
- `kata-remote` RuntimeClass (used by the example Sandbox manifests)
- `oc` CLI access to the namespace where you deploy the router and sandboxes

## 1. Deploy the sandbox router

Use the pre-built image `quay.io/eesposit/sandbox-router:latest`, or build from the [upstream sandbox-router](https://github.com/kubernetes-sigs/agent-sandbox/tree/main/clients/python/agentic-sandbox-client/sandbox-router) and update the image in `sandbox-router.yaml`.

```bash
oc apply -f sandbox-router.yaml
oc wait --for=condition=available deployment/sandbox-router-deployment --timeout=120s
```

For local clusters, load your image and set `imagePullPolicy: Never` on the router container (see comments in the manifest).

## 2. Expose the router on OpenShift

Create a Route to the router Service:

```bash
oc expose svc sandbox-router-svc --port=8080
```

Note the Route hostname:

```bash
oc get route sandbox-router-svc -o jsonpath='{.spec.host}{"\n"}'
```

## 3. Configure Chrome (ModHeader)

Install the [ModHeader](https://modheader.com/) extension. You will add request headers per example below so the router knows which sandbox and port to proxy.

## 4. Example: Jupyter notebook

Deploy the sandbox:

```bash
oc apply -f jupyter-notebook.yaml
```

Wait until the Sandbox pod is ready, then open the Route URL in Chrome with these ModHeader values:

| Header | Value |
|--------|-------|
| `X-Sandbox-ID` | `jupyter-notebook` |
| `X-Sandbox-Port` | `8888` |
| `X-Sandbox-Namespace` | `default` |

Jupyter token (password): `aro_workshop123`

Confirm the notebook UI loads through the router and you are able to execute the steps.

## 5. Example: VS Code (envbuilder)

Deploy the sandbox. The envbuilder workload needs elevated permissions on OpenShift; grant the `anyuid` SCC to the default service account in the namespace first:

```bash
oc adm policy add-scc-to-user anyuid -z default -n default
oc apply -f vscode.yaml
```

Wait until the Sandbox pod is ready, then open the Route URL in Chrome with:

| Header | Value |
|--------|-------|
| `X-Sandbox-ID` | `vscode-sandbox` |
| `X-Sandbox-Port` | `13337` |
| `X-Sandbox-Namespace` | `default` |

Confirm the VS Code web UI loads through the router.

## Troubleshooting

- **Router not ready** — `oc logs deployment/sandbox-router-deployment` and check `/healthz` on port 8080 inside the pod.
- **502 / timeout** — Verify the Sandbox exists, the pod is Running, and header values match `metadata.name`, container port, and namespace in the YAML.
- **Auth errors** — `ALLOW_UNAUTHENTICATED_ROUTER` is `false` by default; uncomment `ROUTER_AUTH_TOKEN` in `sandbox-router.yaml` and set ModHeader to send the same token if you enable auth.
