# Installing agent-sandbox on OpenShift

Steps to prepare a cluster for the demos in this repository: OSC prerequisites, [Operator SDK](https://sdk.operatorframework.io/docs/installation/), then the agent-sandbox Operator bundle.

## Prerequisites

- `oc` CLI logged in to a cluster where you can install Operators (OLM)
- Cluster admin or permission to run `operator-sdk run bundle` in the target namespace

## 1. Install and configure OSC

Ensure [OpenShift sandboxed containers (OSC)](https://docs.redhat.com/en/documentation/openshift_sandboxed_containers/1.10/html/deploying_openshift_sandboxed_containers/about-osc) is installed and configured on the cluster before deploying agent-sandbox. Follow your platform or workshop documentation for OSC setup (including `kata-remote` / peer pods if you run the router or warmpool scenarios).

## 2. Install Operator SDK

[Operator SDK](https://sdk.operatorframework.io/docs/installation/) is currently the quickest way to deploy the agent-sandbox bundle locally.

```bash
# Example (macOS, Homebrew) — use the install method that matches your OS
brew install operator-sdk
operator-sdk version
```

## 3. Install the agent-sandbox Operator

Run the published bundle image (pinned by digest):

```bash
operator-sdk run bundle \
  quay.io/redhat-user-workloads/ose-osc-tenant/agent-sandbox-bundle@sha256:83e4ad73b3562760485ce2d4ea9deb0ba9dcb9c9af2f3900003597090251f51c
```

Confirm the Operator is running (namespace may vary depending on how you ran the bundle):

```bash
oc get csv -A | grep -i agent-sandbox
oc get pods -A | grep -i agent-sandbox
```

After installation, use the scenario READMEs under `scenarios/` (for example [router](scenarios/router/README.md) or [warmpool-kata-remote](scenarios/warmpool-kata-remote/README.md)) for runtime-specific setup such as `kata` or `kata-remote`.
