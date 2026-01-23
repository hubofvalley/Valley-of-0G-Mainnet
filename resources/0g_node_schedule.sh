#!/usr/bin/env bash
set -euo pipefail

# Source environment variables
source $HOME/.bash_profile 2>/dev/null

# Set defaults for service names and resolve at runtime
OG_SERVICE_NAME=${OG_SERVICE_NAME:-0gchaind}
OG_GETH_SERVICE_NAME=${OG_GETH_SERVICE_NAME:-0g-geth}

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
YELLOW=$'\033[0;33m'
ORANGE=$'\033[38;5;214m'
RESET=$'\033[0m'

LOG_DIR="$HOME/.0gchaind/0g-home"
LOG_FILE="$LOG_DIR/0g_schedule_jobs.log"

if ! command -v at >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y at
    sudo systemctl enable --now atd
fi

echo -e "${CYAN}Current server time (UTC):${RESET}"
echo -e "${GREEN}$(date -u)${RESET}"
echo
echo -e "${YELLOW}Note: All input times are interpreted as UTC and will be scheduled for the equivalent local time on the server.${RESET}"
echo

read_year() {
    local __var=$1
    local val num
    while true; do
        read -r -p "${YELLOW}year (4 digits, or type 'back' to return to main menu): ${RESET}" val
        if [[ "${val,,}" == "back" ]]; then
            return 2
        fi
        if [[ ! "$val" =~ ^[0-9]{4}$ ]]; then
            echo -e "${RED}Please enter a 4-digit year (e.g., 2026).${RESET}"
            continue
        fi
        num=$((10#$val))
        if (( num < 1970 || num > 2099 )); then
            echo -e "${RED}Please enter a year between 1970 and 2099.${RESET}"
            continue
        fi
        printf -v "$__var" "%s" "$num"
        return 0
    done
}

read_range() {
    local __var=$1
    local prompt=$2
    local min=$3
    local max=$4
    local val num
    while true; do
        read -r -p "${YELLOW}${prompt} (or type 'back' to return to main menu): ${RESET}" val
        if [[ "${val,,}" == "back" ]]; then
            return 2
        fi
        if [[ ! "$val" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Please enter numbers only.${RESET}"
            continue
        fi
        num=$((10#$val))
        if (( num < min || num > max )); then
            echo -e "${RED}Please enter a value between $min and $max.${RESET}"
            continue
        fi
        printf -v "$__var" "%s" "$num"
        return 0
    done
}

pause_return() {
    read -r -p "${YELLOW}Press Enter to return to the schedule menu...${RESET}"
}

ensure_log_dir() {
    mkdir -p "$LOG_DIR"
}

write_job_log() {
    local job_id=$1
    local action_label=$2
    local dt_human=$3
    local dt_at=$4
    ensure_log_dir
    printf "%s|%s|%s|%s|%s\n" \
        "$job_id" \
        "$action_label" \
        "$dt_human" \
        "$dt_at" \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOG_FILE"
}

get_job_action() {
    local job_id=$1
    local line action_label
    [[ -f "$LOG_FILE" ]] || return 1
    line=$(awk -F'|' -v id="$job_id" '$1==id {last=$0} END{print last}' "$LOG_FILE")
    [[ -n "$line" ]] || return 1
    IFS='|' read -r _id action_label _dt_human _dt_at _created <<< "$line"
    printf "%s" "$action_label"
}

get_job_human_time() {
    local job_id=$1
    local line dt_human
    [[ -f "$LOG_FILE" ]] || return 1
    line=$(awk -F'|' -v id="$job_id" '$1==id {last=$0} END{print last}' "$LOG_FILE")
    [[ -n "$line" ]] || return 1
    IFS='|' read -r _id _action_label dt_human _dt_at _created <<< "$line"
    printf "%s" "$dt_human"
}

remove_job_log() {
    local job_id=$1
    local tmp_file
    [[ -f "$LOG_FILE" ]] || return 0
    tmp_file=$(mktemp)
    if ! grep -v "^${job_id}|" "$LOG_FILE" > "$tmp_file"; then
        true
    fi
    mv "$tmp_file" "$LOG_FILE"
}

list_jobs() {
    echo -e "${CYAN}Queued jobs:${RESET}"
    local queue line job_id action_label
    if ! queue=$(sudo atq 2>/dev/null); then
        echo -e "${RED}Failed to read job queue.${RESET}"
        return 1
    fi
    if [[ -z "$queue" ]]; then
        echo -e "${YELLOW}No scheduled jobs.${RESET}"
        return 0
    fi
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        job_id=${line%%[[:space:]]*}
        action_label=$(get_job_action "$job_id" || true)
        dt_human=$(get_job_human_time "$job_id" || true)
        if [[ -n "$action_label" ]]; then
            echo -e "${GREEN}$line${RESET} ${CYAN}| action:${RESET} ${YELLOW}$action_label${RESET} ${CYAN}| scheduled:${RESET} ${YELLOW}${dt_human:-unknown}${RESET}"
        else
            echo -e "${GREEN}$line${RESET} ${CYAN}| action:${RESET} ${YELLOW}unknown${RESET} ${CYAN}| scheduled:${RESET} ${YELLOW}${dt_human:-unknown}${RESET}"
        fi
    done <<< "$queue"
}

schedule_jobs() {
    local action_label=$1
    local commands=$2
    local Y M D h m s
    echo
    echo -e "${CYAN}This will schedule:${RESET}"
    echo -e "${GREEN}$commands${RESET}"
    echo
    echo -e "${CYAN}Example input:${RESET}"
    echo -e "  ${GREEN}year=2026 month=1 day=13 hour=6 minute=31 second=0${RESET}"
    echo -e "${YELLOW}Note:${RESET} you can enter 1 or 2 digits for month/day/hour/minute/second (e.g., 6 or 06)."
    echo -e "${YELLOW}Note:${RESET} scheduled jobs run as root because sudo at is used."
    echo

    if ! read_year Y; then
        return 2
    fi
    if ! read_range M "month (1-12)" 1 12; then
        return 2
    fi
    if ! read_range D "day (1-31)" 1 31; then
        return 2
    fi
    if ! read_range h "hour (24h format, 0-23)" 0 23; then
        return 2
    fi
    if ! read_range m "minute (0-59)" 0 59; then
        return 2
    fi
    if ! read_range s "second (0-59)" 0 59; then
        return 2
    fi

    DT_HUMAN_UTC="$(printf "%04d-%02d-%02d %02d:%02d:%02d UTC" "$Y" "$M" "$D" "$h" "$m" "$s")"
    # Validate the UTC datetime and convert to epoch (this will fail if the date is invalid, e.g., Feb 30)
    if ! epoch=$(date -u -d "$DT_HUMAN_UTC" +%s 2>/dev/null); then
        echo -e "${RED}Invalid date/time (does not exist in UTC).${RESET}"
        return 2
    fi
    local sleep_prefix=""
    if (( s > 0 )); then
        sleep_prefix="sleep $s"$'\n'
    fi
    # Convert epoch to server local time for `at -t` (at interprets timestamps in local timezone)
    # atq only shows minute precision, so we handle seconds via an optional sleep.
    if (( s > 0 )); then
        DT_AT="$(date -d "@$epoch" +%Y%m%d%H%M.00)"
    else
        DT_AT="$(date -d "@$epoch" +%Y%m%d%H%M.00)"
    fi
    echo -e "${GREEN}Scheduling $action_label at (UTC):${RESET} ${CYAN}$DT_HUMAN_UTC${RESET}"
    echo -e "${YELLOW}Note:${RESET} the job will be scheduled for the equivalent local time: ${CYAN}$(date -d "@$epoch" '+%Y-%m-%d %H:%M:%S %Z')${RESET}"
    if (( s > 0 )); then
        echo -e "${YELLOW}Note:${RESET} seconds are handled by sleeping inside the job; atq shows minute precision."
    fi

    local at_output job_id
    if ! at_output=$(echo -e "${sleep_prefix}${commands}\n" | sudo at -t "$DT_AT" 2>&1); then
        echo -e "${RED}Failed to schedule job.${RESET}"
        echo -e "${RED}$at_output${RESET}"
        return 1
    fi
    if [[ $at_output =~ job[[:space:]]+([0-9]+)[[:space:]]+at ]]; then
        job_id="${BASH_REMATCH[1]}"
        write_job_log "$job_id" "$action_label" "$DT_HUMAN_UTC" "$DT_AT"
        echo -e "${GREEN}Scheduled job ID:${RESET} ${CYAN}$job_id${RESET}"
    else
        echo -e "${YELLOW}Scheduled job, but job ID was not detected.${RESET}"
    fi
    echo
    if ! list_jobs; then
        return 1
    fi
}

while true; do
    echo -e "${CYAN}Choose an option:${RESET}"
    echo -e "${GREEN}1.${RESET} List scheduled jobs"
    echo -e "${GREEN}2.${RESET} Stop and disable 0g services"
    echo -e "${GREEN}3.${RESET} Restart and enable 0g services"
    echo -e "${GREEN}4.${RESET} Remove a scheduled job"
    echo -e "${GREEN}5.${RESET} Exit"
    read -r -p "${YELLOW}Enter choice (1-5): ${RESET}" ACTION

    case "$ACTION" in
        1)
            if ! list_jobs; then
                pause_return
                continue
            fi
            pause_return
            ;;
        2)
            if ! schedule_jobs "stop/disable" "systemctl stop ${OG_SERVICE_NAME} ${OG_GETH_SERVICE_NAME}"$'\n'"systemctl disable ${OG_SERVICE_NAME} ${OG_GETH_SERVICE_NAME}"; then
                rc=$?
                if (( rc == 2 )); then
                    echo -e "${YELLOW}Returning to main menu...${RESET}"
                    exit 0
                fi
                pause_return
                continue
            fi
            pause_return
            ;;
        3)
            if ! schedule_jobs "restart/enable" "systemctl daemon-reload"$'\n'"systemctl enable ${OG_SERVICE_NAME} ${OG_GETH_SERVICE_NAME}"$'\n'"systemctl restart ${OG_SERVICE_NAME} ${OG_GETH_SERVICE_NAME}"; then
                rc=$?
                if (( rc == 2 )); then
                    echo -e "${YELLOW}Returning to main menu...${RESET}"
                    exit 0
                fi
                pause_return
                continue
            fi
            pause_return
            ;;
        4)
            if ! list_jobs; then
                pause_return
                continue
            fi
            echo
            read -r -p "${YELLOW}Enter job ID to remove: ${RESET}" JOB_ID
            if [[ ! "$JOB_ID" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Invalid job ID.${RESET}"
                pause_return
                continue
            fi
            if sudo atrm "$JOB_ID"; then
                echo -e "${GREEN}Removed job ID $JOB_ID.${RESET}"
                remove_job_log "$JOB_ID"
            else
                echo -e "${RED}Failed to remove job ID $JOB_ID.${RESET}"
            fi
            pause_return
            ;;
        5)
            echo -e "${YELLOW}Exiting.${RESET}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Try again.${RESET}"
            pause_return
            ;;
    esac
done
