#!/bin/bash
# =============================================================================
# demo.sh - Agent Sandbox + Kata Containers Demo Recording
# =============================================================================
#
#
# Usage:
#   1. Start recording:  asciinema rec demo.cast --cols 120 --rows 40
#   2. Run the demo:     ./demo.sh
#   3. Stop recording:   Ctrl+D or 'exit'
#   4. Replay:           asciinema play demo.cast
#   5. Convert to GIF:   agg demo.cast demo.gif
#
# Environment variables:
#   KUBECTL        - kubectl or oc (default: kubectl)
#   TYPE_SPEED     - typing speed chars/sec (default: 25)
#   NARRATE_PAUSE  - seconds to pause after narration (default: 3)
#   CMD_PAUSE      - seconds to pause after command output (default: 2)
#   SKIP_CLEANUP   - set to 1 to skip initial cleanup
#   INTERACTIVE    - set to 1 to pause between acts (press Enter)
#
# =============================================================================

set -euo pipefail

DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DEMO_DIR"
source "${DEMO_DIR}/lib.sh"

# Optional: pause between acts if INTERACTIVE=1
maybe_pause() {
    if [ "${INTERACTIVE:-0}" = "1" ]; then
        press_enter
    fi
}

# =============================================================================
# TITLE SCREEN
# =============================================================================

show_act "Agent Sandbox + Kata Containers" \
         "Secure, Isolated AI Agent Environments using" \
	 "OpenShift sandboxed containers"

narrate_block \
    "This demo shows how the Agent Sandbox project" \
    "(kubernetes-sigs/agent-sandbox) provides a declarative API" \
    "for managing isolated AI agent workloads with VM-level" \
    "security via Kata Containers."

narrate_block \
    "What we'll cover:" \
    "  1. The problem with managing agent environments today" \
    "  2. How Agent Sandbox solves it with a single CRD" \
    "  3. The Warm Pool pattern for instant provisioning" \
    "  4. Value summary"

maybe_pause

# =============================================================================
# CLEANUP
# =============================================================================

if [ "${SKIP_CLEANUP:-0}" != "1" ]; then
    cleanup_all
fi

# =============================================================================
# ACT 1: THE PROBLEM
# =============================================================================

show_act "[1/4] The Problem" \
         "Managing AI Agent Environments the Hard Way"

narrate "To run an AI agent today, you manage multiple resources by hand."

show_step "First, you need a Pod manifest"

show_manifest "manifests/act1-pod.yaml"

show_step "Then, a separate Service for network access"

show_manifest "manifests/act1-svc.yaml"

narrate "For persistent storage you'd also need a PVC. That's 3+ resources per agent."

show_step "Apply both resources"

run "kubectl apply -f manifests/act1-pod.yaml"
run "kubectl apply -f manifests/act1-svc.yaml"

wait_pod_running "my-agent" 120

show_step "Check what was created"

run "kubectl get pod,svc my-agent"

show_step "Inspect the isolation boundary"

narrate "With the default container runtime (runc), the pod shares the host kernel."

run "kubectl exec my-agent -- cat /proc/1/cgroup"

key_point "The cgroup path shows this container runs INSIDE the host's cgroup tree."
key_point "No VM boundary. A kernel exploit in one container can affect all others."

run "kubectl exec my-agent -- uname -r"

HOST_KERNEL=$(kubectl get node -o jsonpath='{.items[0].status.nodeInfo.kernelVersion}' 2>/dev/null || echo "unknown")
key_point "Kernel: same as the host (${HOST_KERNEL}). No kernel-level isolation."

show_step "Cleanup is entirely manual"

narrate "You must delete each resource individually. No auto-expiry. No lifecycle management."

run "kubectl delete pod my-agent --wait=false"
run "kubectl delete svc my-agent"

narrate "Now imagine managing hundreds of these agent environments..."

sleep 2
maybe_pause

# =============================================================================
# ACT 2: ENTER AGENT SANDBOX
# =============================================================================

show_act "[2/4] Agent Sandbox + Kata" \
         "One Resource. VM Isolation. Lifecycle Management."

narrate_block \
    "The Agent Sandbox project provides a Sandbox CRD that:" \
    "  - Bundles Pod + Service + PVCs in a single resource" \
    "  - Adds built-in lifecycle management (auto-expiry)" \
    "  - Works with Kata Containers for VM-level isolation" \
    "  - Supports scale-to-zero to preserve state"

show_step "A simple Sandbox with Kata runtime"

show_manifest "manifests/act2-hello-world.yaml" \
    "One YAML file. The key field: runtimeClassName: kata"

run "kubectl apply -f manifests/act2-hello-world.yaml"

wait_sandbox_pod "hello-world-kata" 120

show_step "The controller created Pod AND Service automatically"

run "kubectl get sandbox,pod,svc"

key_point "One 'kubectl apply' -> Sandbox controller created the Pod and headless Service."

show_step "Verify VM isolation with Kata Containers"

run "kubectl exec hello-world-kata -- cat /proc/1/cgroup"

key_point "Cgroup: '0::/' -- PID 1 in its own VM! This is NOT the host's cgroup tree."

run "kubectl exec hello-world-kata -- uname -r"

key_point "Guest kernel inside the Kata VM. Different from host kernel (${HOST_KERNEL})."
key_point "Each sandbox runs a separate kernel -- independent security boundary."

show_step "Automatic stable network identity"

run "kubectl get sandbox hello-world-kata -o jsonpath='{.status.serviceFQDN}'"
echo ""

key_point "Every Sandbox gets a stable FQDN via auto-created headless Service."

transition

# --- Python Sandbox with Lifecycle ---

show_step "Deploy a Python agent sandbox with lifecycle management"

# Generate shutdownTime 1 hour from now
SHUTDOWN_TIME=$(date -u -v+1H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
                date -u -d '+1 hour' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
                echo "2099-12-31T23:59:59Z")

# Substitute the placeholder in the manifest
sed "s|PLACEHOLDER|${SHUTDOWN_TIME}|" manifests/act2-python-sandbox.yaml > /tmp/demo-python-sandbox.yaml

show_manifest "/tmp/demo-python-sandbox.yaml" \
    "Built-in lifecycle: shutdownTime auto-expires the sandbox and cleans up resources."

run "kubectl apply -f /tmp/demo-python-sandbox.yaml"

wait_sandbox_pod "python-sandbox-kata" 120

narrate "The Python sandbox has an HTTP API running inside its Kata VM."

run "kubectl exec python-sandbox-kata -- python3 -c \"import urllib.request; print(urllib.request.urlopen('http://localhost:8888/health').read().decode())\""

key_point "Python HTTP server running inside a Kata VM, accessible via auto-created Service."

run "kubectl exec python-sandbox-kata -- python3 -c \"import urllib.request; print(urllib.request.urlopen('http://localhost:8888/info').read().decode())\""

key_point "The /info endpoint confirms: isolated VM kernel, root cgroup."

show_step "Scale to Zero: hibernate without losing state"

narrate_block \
    "Sandbox supports replicas: 0 to stop the VM while preserving" \
    "the Sandbox resource and any PVCs. Zero compute cost when idle."

run "kubectl patch sandbox python-sandbox-kata --type merge -p '{\"spec\":{\"replicas\":0}}'"

sleep 4

run "kubectl get sandbox python-sandbox-kata"
run "kubectl get pod python-sandbox-kata 2>/dev/null || echo 'Pod is gone (scaled to zero)'"

key_point "Sandbox still exists, but the Pod/VM is stopped. PVCs (if any) are preserved."

show_step "Resume: scale back to 1"

run "kubectl patch sandbox python-sandbox-kata --type merge -p '{\"spec\":{\"replicas\":1}}'"

wait_sandbox_pod "python-sandbox-kata" 120

run "kubectl get sandbox,pod python-sandbox-kata"

key_point "Pod recreated with the same identity. Agent resumes where it left off."

sleep 2
maybe_pause

# =============================================================================
# ACT 3: THE WARM POOL PATTERN
# =============================================================================

show_act "[3/4] Warm Pool Pattern" \
         "Pre-warmed Sandboxes for Instant Provisioning"

narrate_block \
    "The Warm Pool pattern is Agent Sandbox's most powerful feature." \
    "It is impossible to achieve with raw Pod manifests." \
    "" \
    "The idea:" \
    "  1. Define a SandboxTemplate (reusable spec)" \
    "  2. Create a SandboxWarmPool (pre-creates Kata VM pods)" \
    "  3. Users submit a SandboxClaim (adopts a warm pod instantly)"

show_step "Step 1: Create a SandboxTemplate"

show_manifest "manifests/act3-template.yaml" \
    "A reusable template: runtime, security context, image, ports -- all standardized."

run "kubectl apply -f manifests/act3-template.yaml"

run "kubectl get sandboxtemplate"

show_step "Step 2: Create a SandboxWarmPool with 3 replicas"

show_manifest "manifests/act3-warmpool.yaml" \
    "References the template. Pre-creates 3 Kata VM pods, ready before any user needs them."

run "kubectl apply -f manifests/act3-warmpool.yaml"

narrate "The controller is now spinning up 3 Kata VMs from the template..."

# Wait and show progress
sleep 5
run "kubectl get pods -l agents.x-k8s.io/pool"

wait_pods_by_label "agents.x-k8s.io/pool" 3 180

run_slow "kubectl get pods -l agents.x-k8s.io/pool"

key_point "3 pre-warmed Kata VM pods running and ready. No user has claimed them yet."

run "kubectl get sandboxwarmpool kata-warm-pool"

show_step "Step 3: A user claims a sandbox -- instant provisioning"

narrate "Let's record the current warm pool pods before the claim."

run "kubectl get pods -l agents.x-k8s.io/pool -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,AGE:.metadata.creationTimestamp"

show_manifest "manifests/act3-claim.yaml" \
    "SandboxClaim references the same template. The controller will adopt a pre-warmed pod."

run "kubectl apply -f manifests/act3-claim.yaml"

narrate "Waiting for the claim to be processed..."
sleep 8

show_step "What happened?"

narrate "The SandboxClaim created a Sandbox which adopted a pre-warmed pod."

run "kubectl get sandbox my-agent-session"

# Show adoption annotation
ADOPTED_POD=$(kubectl get sandbox my-agent-session -o jsonpath='{.metadata.annotations.agents\.x-k8s\.io/pod-name}' 2>/dev/null || echo "")

if [ -n "$ADOPTED_POD" ]; then
    key_point "Adopted pod: ${ADOPTED_POD}"
    key_point "This pod was already running in the warm pool -- no image pull, no VM boot delay!"
fi

# Check ready status
READY=$(kubectl get sandbox my-agent-session -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
if [ "$READY" = "True" ]; then
    key_point "Sandbox status: Ready=True. Instant provisioning achieved!"
fi

show_step "The warm pool auto-replenishes"

narrate "The pool detects it lost a pod and creates a replacement to maintain the desired count."

sleep 3

run "kubectl get pods -l agents.x-k8s.io/pool -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,AGE:.metadata.creationTimestamp"

key_point "Pool automatically scaled back to 3. New pod created to replace the claimed one."

show_step "The complete Warm Pool flow"

narrate_block \
    "                                                            " \
    "  SandboxTemplate ──> SandboxWarmPool (pre-creates 3 pods) " \
    "                            |                               " \
    "  SandboxClaim    ──> Adopts a warm pod ──> Sandbox (Ready!)" \
    "                            |                               " \
    "                      Pool auto-replenishes to 3            " \
    "                                                            "

sleep 2
maybe_pause

# =============================================================================
# ACT 4: VALUE SUMMARY
# =============================================================================

show_act "[4/4] Summary" \
         "Agent Sandbox + Kata Containers: Value at a Glance"

show_step "Everything running on the cluster right now"

run "kubectl get sandbox"
run "kubectl get sandboxtemplate"
run "kubectl get sandboxwarmpool"
run "kubectl get sandboxclaim"

show_step "Before vs After"

echo ""
echo -e "${BOLD}  ┌───────────────────────┬─────────────────────┬───────────────────────┐${NC}"
echo -e "${BOLD}  │     Capability        │     Plain Pod       │  Agent Sandbox + Kata │${NC}"
echo -e "${BOLD}  ├───────────────────────┼─────────────────────┼───────────────────────┤${NC}"
echo -e "  │ Resources to manage   │ ${RED}3+ YAML files${NC}       │ ${GREEN}1 YAML file${NC}           │"
echo -e "  │ Lifecycle / TTL       │ ${RED}Manual${NC}              │ ${GREEN}Built-in auto-expiry${NC}  │"
echo -e "  │ Kernel isolation      │ ${RED}Shared (runc)${NC}       │ ${GREEN}Separate VM (Kata)${NC}    │"
echo -e "  │ Scale to zero         │ ${RED}Delete pod${NC}          │ ${GREEN}Preserves state${NC}       │"
echo -e "  │ Warm pool             │ ${RED}Impossible${NC}          │ ${GREEN}SandboxWarmPool${NC}       │"
echo -e "  │ Instant provisioning  │ ${RED}No${NC}                  │ ${GREEN}SandboxClaim${NC}          │"
echo -e "  │ Stable FQDN           │ ${RED}Manual Service${NC}      │ ${GREEN}Automatic${NC}             │"
echo -e "  │ Observability         │ ${RED}DIY${NC}                 │ ${GREEN}Built-in tracing${NC}      │"
echo -e "${BOLD}  └───────────────────────┴─────────────────────┴───────────────────────┘${NC}"
echo ""
sleep 6

narrate_block \
    "Agent Sandbox (kubernetes-sigs/agent-sandbox):" \
    "" \
    "  Declarative API for AI agent runtime environments" \
    "  VM-level isolation via Kata Containers" \
    "  Built-in lifecycle management with auto-expiry" \
    "  Warm Pool pattern for instant sandbox provisioning" \
    "  Single resource manages Pod + Service + PVCs" \
    "" \
    "  Also supports: Kata Confidential Containers (kata-cc)" \
    "  for hardware-encrypted memory via Intel TDX."

echo ""
echo -e "${MAGENTA}${BOLD}  https://github.com/kubernetes-sigs/agent-sandbox${NC}"
echo ""
sleep 5

# =============================================================================
# END
# =============================================================================

show_act "Demo Complete" \
         "Exit the recording with Ctrl+D or 'exit'"

echo ""
