#!/bin/bash
# =============================================================================
# security-demo.sh - Security Comparison: runc vs Agent Sandbox + Kata
# =============================================================================
#
# Shows what an LLM-generated "system analyzer" script can see
# when running in a plain Pod (runc) vs an Agent Sandbox (Kata VM).
#
# Usage:
#   asciinema rec security-demo.cast --cols 120 --rows 45
#   ./security-demo.sh
#   # Ctrl+D to stop
#   agg security-demo.cast security-demo.gif
#
# =============================================================================

set -euo pipefail

DEMO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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

show_act "When AI Generates Dangerous Code" \
         "Why AI agent workloads need VM-level isolation"

narrate_block \
    "Scenario: An AI code interpreter is asked to analyze system performance." \
    "The LLM generates a Python script that collects system metrics." \
    "" \
    "The script is legitimate -- but it also reveals sensitive details" \
    "about the underlying infrastructure. What can it see?"

narrate_block \
    "We'll run the SAME code in two environments:" \
    "  1. A plain Pod (default runc runtime -- shared host kernel)" \
    "  2. An Agent Sandbox with Kata (VM-isolated)"

maybe_pause

# =============================================================================
# SETUP
# =============================================================================

show_act "[1/3] Setup" \
         "Deploy two code interpreters: runc vs Kata"

narrate "First, clean up any previous runs."
run_silent "kubectl delete pod code-interpreter-runc --ignore-not-found --wait=false"
run_silent "kubectl delete sandbox code-interpreter-kata --ignore-not-found --wait=false"
sleep 5

show_step "Deploy a plain Pod (runc) and an Agent Sandbox (Kata)"

show_manifest "security-manifests.yaml" \
    "Same image (python:3.11-slim), same code. Only difference: the runtime."

run "kubectl apply -f security-manifests.yaml"

narrate "Waiting for both environments to be ready..."

wait_pod_running "code-interpreter-runc" 120
wait_sandbox_pod "code-interpreter-kata" 120

run "kubectl get pod code-interpreter-runc code-interpreter-kata"

show_step "The AI-generated code"

narrate_block \
    "An LLM was asked: 'Write a script to analyze system performance.'" \
    "It generated a Python script that collects system metrics." \
    "This is realistic -- LLMs routinely produce code that reads /proc, /sys, etc."

show_manifest "llm-generated-code.py"

maybe_pause

# =============================================================================
# COMPARISON
# =============================================================================

show_act "[2/3] Running the Code" \
         "Same script, two runtimes -- what can the AI see?"

show_step "Run in plain Pod (runc -- shared host kernel)"

narrate "Running the AI-generated code in the runc container..."

run_slow "kubectl exec -i code-interpreter-runc -- python3 /dev/stdin < llm-generated-code.py"

key_point "The code sees the REAL host: Dell PowerEdge server, 128 CPUs, ~1 TB RAM."
key_point "Host kernel version and symbols exposed -- enough to develop kernel exploits."
key_point "157 mount points including host disk devices visible."

transition

show_step "Run in Agent Sandbox (Kata VM)"

narrate "Now running the SAME code in the Kata-isolated sandbox..."

run_slow "kubectl exec -i code-interpreter-kata -- python3 /dev/stdin < llm-generated-code.py"

key_point "The code sees only a generic KVM virtual machine -- not the real hardware."
key_point "Different kernel version. Kernel symbols are for the VM, not the host."
key_point "Only 1 CPU core visible, ~1.8 GB RAM. Host capacity is hidden."
key_point "Only 24 mount points -- no host disk devices exposed."

maybe_pause

# =============================================================================
# ANALYSIS
# =============================================================================

show_act "[3/3] What This Means" \
         "The blast radius difference"

show_step "Side-by-side: what the AI code discovered"

echo ""
echo -e "${BOLD}  ┌─────────────────────────┬──────────────────────────┬─────────────────────────┐${NC}"
echo -e "${BOLD}  │ What the code sees      │ Plain Pod (runc)         │ Agent Sandbox (Kata)    │${NC}"
echo -e "${BOLD}  ├─────────────────────────┼──────────────────────────┼─────────────────────────┤${NC}"
echo -e "  │ Hardware identity       │ ${RED}Dell PowerEdge R760${NC}     │ ${GREEN}KVM (generic VM)${NC}        │"
echo -e "  │ Kernel version          │ ${RED}Host kernel (5.14)${NC}      │ ${GREEN}VM kernel (6.12)${NC}        │"
echo -e "  │ CPU cores               │ ${RED}128 (all host CPUs)${NC}     │ ${GREEN}1 (VM allocation only)${NC}  │"
echo -e "  │ Memory                  │ ${RED}~1 TB (all host RAM)${NC}    │ ${GREEN}~1.8 GB (VM only)${NC}       │"
echo -e "  │ Kernel symbols          │ ${RED}Host symbols (exploit)${NC}  │ ${GREEN}VM symbols (useless)${NC}    │"
echo -e "  │ Mount points            │ ${RED}157 (host storage)${NC}      │ ${GREEN}24 (VM only)${NC}            │"
echo -e "  │ Host disk devices       │ ${RED}Visible (/dev/sda4)${NC}    │ ${GREEN}Not visible${NC}             │"
echo -e "${BOLD}  └─────────────────────────┴──────────────────────────┴─────────────────────────┘${NC}"
echo ""
sleep 6

show_step "Why this matters for AI agent security"

narrate_block \
    "AI agents routinely execute LLM-generated code." \
    "That code can -- intentionally or not -- collect system information." \
    "" \
    "With runc (shared kernel):" \
    "  - The code learns the exact server model, kernel, and capacity" \
    "  - Kernel symbols enable targeted exploit development" \
    "  - A kernel exploit compromises the HOST and ALL workloads on it" \
    "" \
    "With Kata (VM isolation):" \
    "  - The code sees only a generic VM -- no real infrastructure details" \
    "  - A different kernel version means host-targeted exploits won't work" \
    "  - Even if the VM kernel is exploited, the HOST remains safe" \
    "  - The blast radius is limited to a single, disposable VM"

sleep 3

narrate_block \
    "Agent Sandbox makes this easy:" \
    "  Just set runtimeClassName: kata in your Sandbox spec." \
    "  The controller handles everything else."

echo ""
echo -e "${WHITE}  Agent Sandbox: secure AI agent environments by default.${NC}"
echo -e "${DIM}  https://github.com/kubernetes-sigs/agent-sandbox${NC}"
echo ""
sleep 5

# =============================================================================
# CLEANUP
# =============================================================================

show_act "Demo Complete" \
         "Exit the recording with Ctrl+D or 'exit'"

echo ""
