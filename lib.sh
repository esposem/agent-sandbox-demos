#!/bin/bash
# lib.sh - Demo helper functions for agent-sandbox recording
# Provides narration, typing simulation, and formatting utilities.

# --- Colors ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# --- Configuration ---
TYPE_SPEED="${TYPE_SPEED:-25}"       # Characters per second for typing
NARRATE_PAUSE="${NARRATE_PAUSE:-3}"  # Seconds to pause after narration
CMD_PAUSE="${CMD_PAUSE:-2}"          # Seconds to pause after command output
ACT_PAUSE="${ACT_PAUSE:-4}"          # Seconds to pause on act title screen
KUBECTL="${KUBECTL:-kubectl}"        # kubectl or oc

# --- Typing Simulation ---
# Simulates typing a command using pv
type_cmd() {
    printf "${GREEN}\$ ${NC}"
    echo -n "$1" | pv -qL "$TYPE_SPEED"
    echo ""
}

# --- Narration ---
# Displays narration text (cyan) -- acts as subtitles/captions
narrate() {
    echo ""
    echo -e "${CYAN}  $1${NC}"
    echo ""
    sleep "$NARRATE_PAUSE"
}

# Displays a key observation (yellow, indented with arrow)
key_point() {
    echo ""
    echo -e "  ${YELLOW}${BOLD}>>> $1${NC}"
    echo ""
    sleep "$NARRATE_PAUSE"
}

# Displays an informational note (dim)
note() {
    echo -e "  ${DIM}$1${NC}"
}

# --- Section Headers ---
# Displays an act/section title card
show_act() {
    clear
    local title="$1"
    shift
    local line="════════════════════════════════════════════════════════════"
    echo ""
    echo ""
    echo -e "${WHITE}  ${line}${NC}"
    echo -e "${WHITE}  $title${NC}"
    for subtitle in "$@"; do
        if [ -n "$subtitle" ]; then
            echo -e "${WHITE}    $subtitle${NC}"
        fi
    done
    echo -e "${WHITE}  ${line}${NC}"
    echo ""
    echo ""
    sleep "$ACT_PAUSE"
}

# Displays a step header within an act
show_step() {
    echo ""
    echo -e "${BLUE}${BOLD}  ── $1 ──${NC}"
    echo ""
    sleep 1
}

# --- Command Execution ---
# Types and executes a command, showing output
run() {
    local cmd="$1"
    type_cmd "$cmd"
    sleep 0.5
    eval "$cmd"
    echo ""
    sleep "$CMD_PAUSE"
}

# Types and executes, with a longer pause for important output
run_slow() {
    local cmd="$1"
    type_cmd "$cmd"
    sleep 0.5
    eval "$cmd"
    echo ""
    sleep 4
}

# Executes silently (no typing, no output)
run_silent() {
    eval "$@" > /dev/null 2>&1
}

# --- File Display ---
# Shows a YAML file with a header
show_yaml() {
    local file="$1"
    local desc="${2:-}"
    if [ -n "$desc" ]; then
        narrate "$desc"
    fi
    echo -e "${DIM}  ─── $file ───${NC}"
    cat "$file"
    echo -e "${DIM}  ───────────────────────────────────${NC}"
    echo ""
    sleep "$NARRATE_PAUSE"
}

# --- Waiting ---
# Waits for a pod to be in Running state
wait_pod_running() {
    local pod_name="$1"
    local timeout="${2:-120}"
    local elapsed=0
    echo -ne "  ${DIM}Waiting for pod ${pod_name}..."
    while [ $elapsed -lt $timeout ]; do
        local phase
        phase=$($KUBECTL get pod "$pod_name" -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$phase" = "Running" ] || [ "$phase" = "Succeeded" ]; then
            echo -e " Ready.${NC}"
            sleep 1
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -ne "."
    done
    echo -e " Timeout.${NC}"
    return 1
}

# Waits for a sandbox's pod to be running (by sandbox name)
wait_sandbox_pod() {
    local sandbox_name="$1"
    local timeout="${2:-120}"
    local elapsed=0
    echo -ne "  ${DIM}Waiting for sandbox ${sandbox_name} pod..."
    while [ $elapsed -lt $timeout ]; do
        local phase
        phase=$($KUBECTL get pod "$sandbox_name" -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$phase" = "Running" ] || [ "$phase" = "Succeeded" ]; then
            echo -e " Ready.${NC}"
            sleep 1
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -ne "."
    done
    echo -e " Timeout.${NC}"
    return 1
}

# Waits for N pods matching a label to be Running
wait_pods_by_label() {
    local label="$1"
    local expected="$2"
    local timeout="${3:-180}"
    local elapsed=0
    echo -ne "  ${DIM}Waiting for ${expected} pods with label ${label}..."
    while [ $elapsed -lt $timeout ]; do
        local running
        running=$($KUBECTL get pods -l "$label" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [ "$running" -ge "$expected" ]; then
            echo -e " All ${expected} pods running.${NC}"
            sleep 1
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
        echo -ne "."
    done
    echo -e " Timeout (got $(running)/${expected}).${NC}"
    return 1
}

# --- Cleanup ---
# Deletes all sandbox-related resources
cleanup_all() {
    echo -e "  ${DIM}Cleaning up previous demo resources...${NC}"
    $KUBECTL delete sandbox --all --wait=false > /dev/null 2>&1
    $KUBECTL delete sandboxclaim --all --wait=false > /dev/null 2>&1
    $KUBECTL delete sandboxwarmpool --all --wait=false > /dev/null 2>&1
    $KUBECTL delete sandboxtemplate --all --wait=false > /dev/null 2>&1
    $KUBECTL delete pod my-agent --ignore-not-found > /dev/null 2>&1
    $KUBECTL delete svc my-agent --ignore-not-found > /dev/null 2>&1
    # Wait for pods to terminate
    sleep 5
    local remaining
    remaining=$($KUBECTL get pods --no-headers 2>/dev/null | grep -v "agent-sandbox" | wc -l | tr -d ' ')
    if [ "$remaining" -gt 0 ]; then
        echo -e "  ${DIM}Waiting for pods to terminate...${NC}"
        sleep 10
    fi
    echo -e "  ${DIM}Cleanup done.${NC}"
    echo ""
}

# --- Tables ---
# Renders a simple comparison table
show_comparison_table() {
    echo -e "${BOLD}$1${NC}"
    echo ""
    shift
    for line in "$@"; do
        echo -e "  $line"
    done
    echo ""
}

# --- Prompt ---
# Wait for user to press Enter (for manual pacing if needed)
press_enter() {
    echo ""
    echo -e "  ${DIM}[Press Enter to continue]${NC}"
    read -r
}

# --- Multi-line Narration ---
# Displays multiple lines of narration with a single pause at the end
narrate_block() {
    echo ""
    for line in "$@"; do
        echo -e "${CYAN}  $line${NC}"
    done
    echo ""
    sleep "$NARRATE_PAUSE"
}

# Single caption line without pause
caption() {
    echo -e "${CYAN}  $1${NC}"
}

# --- Transition ---
# Brief pause with a visual separator
transition() {
    echo ""
    echo -e "${DIM}  ────────────────────────────────────────${NC}"
    echo ""
    sleep 2
}

# --- Show YAML with basename only ---
show_manifest() {
    local file="$1"
    local desc="${2:-}"
    local basename
    basename=$(basename "$file")
    if [ -n "$desc" ]; then
        narrate "$desc"
    fi
    echo -e "${DIM}  ─── ${basename} ───${NC}"
    cat "$file"
    echo -e "${DIM}  ───────────────────────────────────${NC}"
    echo ""
    sleep "$NARRATE_PAUSE"
}
