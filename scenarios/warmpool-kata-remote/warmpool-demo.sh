#!/bin/bash
# =============================================================================
# warmpool-demo.sh - Warm Pool with kata-remote: Instant Sandbox Provisioning
# =============================================================================
#
# Demonstrates the Warm Pool pattern using kata-remote runtime:
#   1. Create a SandboxTemplate with kata-remote
#   2. Pre-warm 2 Kata remote VMs via SandboxWarmPool
#   3. Claim a sandbox instantly via SandboxClaim
#   4. Observe pool auto-replenishment
#
# Usage:
#   asciinema rec warmpool-demo.cast --cols 120 --rows 45
#   ./warmpool-demo.sh
#   # Ctrl+D to stop
#   agg warmpool-demo.cast warmpool-demo.gif
#
# =============================================================================

set -euo pipefail

DEMO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCENARIO_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${DEMO_DIR}/lib.sh"

cd "$SCENARIO_DIR"

maybe_pause() {
    if [ "${INTERACTIVE:-0}" = "1" ]; then
        press_enter
    fi
}

# =============================================================================
# TITLE
# =============================================================================

show_act "Warm Pool Pattern with kata-remote" \
         "Pre-warmed Kata Remote VMs for Instant Provisioning"

narrate_block \
    "This demo shows the Warm Pool pattern using kata-remote runtime." \
    "" \
    "kata-remote runs each sandbox in a dedicated peer-pod VM," \
    "provisioned on cloud infrastructure via the Cloud API Adaptor." \
    "VM boot times can be significant -- the Warm Pool pattern" \
    "eliminates this latency for end users."

narrate_block \
    "What we'll cover:" \
    "  1. Create a SandboxTemplate with kata-remote runtime" \
    "  2. Pre-warm 2 VMs via SandboxWarmPool" \
    "  3. Claim a sandbox instantly via SandboxClaim" \
    "  4. Observe pool auto-replenishment"

maybe_pause

# =============================================================================
# CLEANUP
# =============================================================================

show_act "[1/4] Setup" \
         "Clean up previous resources"

narrate "First, clean up any previous runs."

run_silent "kubectl delete sandboxclaim my-kata-remote-session --ignore-not-found --wait=false"
run_silent "kubectl delete sandbox my-kata-remote-session --ignore-not-found --wait=false"
run_silent "kubectl delete sandboxwarmpool kata-remote-warm-pool --ignore-not-found --wait=false"
run_silent "kubectl delete sandboxtemplate kata-remote-template --ignore-not-found --wait=false"
sleep 5

narrate "Clean. Let's begin."

maybe_pause

# =============================================================================
# ACT 2: SANDBOX TEMPLATE
# =============================================================================

show_act "[2/4] SandboxTemplate" \
         "Define a reusable sandbox specification"

narrate_block \
    "A SandboxTemplate captures the sandbox specification:" \
    "  - Runtime class (kata-remote for peer-pod VMs)" \
    "  - Security context (non-root)" \
    "  - Container image, command, ports" \
    "" \
    "Templates are reusable across warm pools and claims."

show_step "Examine the template"

show_manifest "template.yaml" \
    "kata-remote runtime with a Python HTTP server (health, info, status endpoints)."

show_step "Create the SandboxTemplate"

run "kubectl apply -f template.yaml"

run "kubectl get sandboxtemplate"

key_point "SandboxTemplate created. This defines the spec all warm pool pods will use."

maybe_pause

# =============================================================================
# ACT 3: WARM POOL
# =============================================================================

show_act "[3/4] SandboxWarmPool" \
         "Pre-warm 2 kata-remote VMs"

narrate_block \
    "With kata-remote, each pod runs in a dedicated peer-pod VM" \
    "provisioned via the Cloud API Adaptor. VM creation includes:" \
    "  - Cloud API call to provision the VM" \
    "  - VM boot and agent startup" \
    "  - Image pull inside the VM" \
    "" \
    "The Warm Pool pre-creates these VMs so users don't wait."

show_step "Create a SandboxWarmPool with 2 replicas"

show_manifest "warmpool.yaml" \
    "References the template. Pre-creates 2 Kata remote VMs, ready before any user needs them."

run "kubectl apply -f warmpool.yaml"

narrate "The controller is now provisioning 2 kata-remote VMs..."

# Show progress as VMs come up
sleep 5
run "kubectl get pods -l agents.x-k8s.io/pool"

wait_pods_by_label "agents.x-k8s.io/pool" 2 300

run_slow "kubectl get pods -l agents.x-k8s.io/pool -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName,AGE:.metadata.creationTimestamp"

key_point "2 pre-warmed kata-remote VMs running. Each is a dedicated peer-pod VM."

show_step "Verify VM isolation"

# Get the name of the first warm pool pod
WARM_POD=$(kubectl get pods -l agents.x-k8s.io/pool -o jsonpath='{.items[0].metadata.name}')

narrate "Let's verify isolation inside one of the warm pool pods."

run "kubectl exec ${WARM_POD} -- cat /proc/1/cgroup"

key_point "Cgroup '0::/' -- this process is PID 1 inside its own VM."

run "kubectl exec ${WARM_POD} -- uname -r"

key_point "Guest kernel inside the kata-remote VM. Separate from the host kernel."

show_step "Test the HTTP service inside the warm pod"

run "kubectl exec ${WARM_POD} -- python3 -c \"import urllib.request; print(urllib.request.urlopen('http://localhost:8888/info').read().decode())\""

key_point "HTTP server running inside the peer-pod VM, reporting kata-remote runtime."

run "kubectl get sandboxwarmpool kata-remote-warm-pool"

key_point "Warm pool shows 2/2 replicas ready. VMs are pre-provisioned and waiting."

maybe_pause

# =============================================================================
# ACT 4: CLAIM
# =============================================================================

show_act "[4/4] SandboxClaim" \
         "Instant provisioning via warm pod adoption"

narrate_block \
    "Now a user needs a sandbox. Without the warm pool, they'd wait" \
    "for the full VM provisioning cycle. With the warm pool," \
    "a SandboxClaim instantly adopts a pre-warmed pod."

show_step "Record the current warm pool pods"

run "kubectl get pods -l agents.x-k8s.io/pool -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,AGE:.metadata.creationTimestamp"

show_step "Submit a SandboxClaim"

show_manifest "claim.yaml" \
    "The SandboxClaim references the same template. The controller matches and adopts."

run "kubectl apply -f claim.yaml"

narrate "Waiting for the claim to be processed..."
sleep 8

show_step "What happened?"

narrate "The SandboxClaim created a Sandbox which adopted a pre-warmed pod."

run "kubectl get sandbox my-kata-remote-session"

# Get the actual pod name -- warm pool pods keep their original name after adoption
CLAIMED_POD=$(kubectl get sandbox my-kata-remote-session -o jsonpath='{.status.podName}' 2>/dev/null || echo "")
if [ -z "$CLAIMED_POD" ]; then
    # Fallback: try the annotation
    CLAIMED_POD=$(kubectl get sandbox my-kata-remote-session -o jsonpath='{.metadata.annotations.agents\.x-k8s\.io/pod-name}' 2>/dev/null || echo "")
fi

if [ -n "$CLAIMED_POD" ]; then
    key_point "Adopted pod: ${CLAIMED_POD}"
    key_point "This pod was already running -- no VM provisioning delay!"
fi

# Check ready status
READY=$(kubectl get sandbox my-kata-remote-session -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
if [ "$READY" = "True" ]; then
    key_point "Sandbox status: Ready=True. Instant provisioning achieved!"
fi

show_step "Test the claimed sandbox"

narrate "The adopted pod retains its original name from the warm pool."

run "kubectl exec ${CLAIMED_POD} -- python3 -c \"import urllib.request; print(urllib.request.urlopen('http://localhost:8888/health').read().decode())\""

key_point "The claimed sandbox is fully functional. HTTP service responds immediately."

show_step "Warm pool auto-replenishes"

narrate "The pool detects it lost a pod and creates a replacement."

sleep 5

run "kubectl get pods -l agents.x-k8s.io/pool -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,AGE:.metadata.creationTimestamp"

key_point "Pool automatically scaled back to 2 replicas. New VM provisioned to replace the claimed one."

show_step "The complete Warm Pool flow"

narrate_block \
    "                                                                  " \
    "  SandboxTemplate ──> SandboxWarmPool (pre-creates 2 kata-remote) " \
    "                            |                                     " \
    "  SandboxClaim    ──> Adopts a warm pod ──> Sandbox (Ready!)      " \
    "                            |                                     " \
    "                      Pool auto-replenishes to 2                  " \
    "                                                                  "

transition

show_step "Summary"

echo ""
echo -e "${BOLD}  ┌────────────────────────────┬──────────────────────────┬──────────────────────────┐${NC}"
echo -e "${BOLD}  │ Provisioning               │ Without Warm Pool        │ With Warm Pool           │${NC}"
echo -e "${BOLD}  ├────────────────────────────┼──────────────────────────┼──────────────────────────┤${NC}"
echo -e "  │ VM provisioning            │ ${RED}On-demand (slow)${NC}         │ ${GREEN}Pre-provisioned${NC}          │"
echo -e "  │ Image pull                 │ ${RED}Every request${NC}            │ ${GREEN}Already cached${NC}           │"
echo -e "  │ User wait time             │ ${RED}Minutes${NC}                  │ ${GREEN}Seconds${NC}                  │"
echo -e "  │ Pool management            │ ${RED}Manual${NC}                   │ ${GREEN}Auto-replenish${NC}           │"
echo -e "  │ Runtime isolation          │ ${GREEN}kata-remote (VM)${NC}         │ ${GREEN}kata-remote (VM)${NC}         │"
echo -e "${BOLD}  └────────────────────────────┴──────────────────────────┴──────────────────────────┘${NC}"
echo ""
sleep 6

narrate_block \
    "The Warm Pool pattern with kata-remote:" \
    "" \
    "  - Eliminates VM boot latency for end users" \
    "  - Each sandbox runs in a dedicated peer-pod VM" \
    "  - Pool auto-replenishes to maintain desired replica count" \
    "  - Same strong VM isolation as on-demand kata-remote sandboxes" \
    "" \
    "  Ideal for multi-tenant AI agent platforms where" \
    "  fast provisioning and strong isolation are both required."

echo ""
echo -e "${WHITE}  Agent Sandbox: secure AI agent environments by default.${NC}"
echo -e "${DIM}  https://github.com/kubernetes-sigs/agent-sandbox${NC}"
echo ""
sleep 5

# =============================================================================
# END
# =============================================================================

show_act "Demo Complete" \
         "Exit the recording with Ctrl+D or 'exit'"

echo ""
