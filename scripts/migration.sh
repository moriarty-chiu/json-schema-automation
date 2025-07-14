#!/bin/bash
set -euo pipefail

# Configuration
SOURCE_DOMAIN="gitlab.example.com"
SOURCE_PROTOCOL="http"
DESTINATION_DOMAIN="new-gitlab.example.com"
DESTINATION_PROTOCOL="https"
TEMP_DIR="migration_tmp"
MAX_RETRY=2
LOG_FILE="migration_$(date +%Y%m%d_%H%M%S).log"

# Counters
total=0
success=0
fail=0
current=0

# Progress bar function
show_progress() {
    local done=$1
    local total=$2
    local width=40
    local percent=$(( 100 * done / total ))
    local fill=$(( width * done / total ))

    printf "\r["

    for ((i=0; i<fill; i++)); do
        printf "#"
    done

    for ((i=fill; i<width; i++)); do
        printf "-"
    done

    printf "] %3d%% (%d/%d)" "$percent" "$done" "$total"
}

# General log function (write to main LOG_FILE)
log() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Per-project log function (write to $PROJECT_LOG)
project_log() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] ${message}" >> "$PROJECT_LOG"
}

generate_url() {
    local domain=$1
    local protocol=$2
    local group=$3
    local project=$4

    case "$protocol" in
        ssh)
            echo "git@${domain}:${group}/${project}.git"
            ;;
        http|https)
            echo "${protocol}://${domain}/${group}/${project}.git"
            ;;
        auto)
            if curl --output /dev/null --silent --head --fail "https://${domain}/${group}/${project}.git"; then
                echo "https://${domain}/${group}/${project}.git"
            elif curl --output /dev/null --silent --head --fail "http://${domain}/${group}/${project}.git"; then
                echo "http://${domain}/${group}/${project}.git"
            else
                echo "git@${domain}:${group}/${project}.git"
            fi
            ;;
        *)
            log "ERROR" "Invalid protocol: $protocol"
            exit 1
            ;;
    esac
}

migrate_project() {
    local src_grp=$1
    local src_prj=$2
    local dst_grp=$3
    local dst_prj=$4

    local src_url
    src_url=$(generate_url "$SOURCE_DOMAIN" "$SOURCE_PROTOCOL" "$src_grp" "$src_prj")

    local dst_url
    dst_url=$(generate_url "$DESTINATION_DOMAIN" "$DESTINATION_PROTOCOL" "$dst_grp" "$dst_prj")

    local clone_dir="${TEMP_DIR}/${src_prj}_$(date +%s)"
    PROJECT_LOG="${clone_dir}/migration.log"

    log "INFO" "Starting migration: $src_url → $dst_url (Logs: $PROJECT_LOG)"
    mkdir -p "$clone_dir"

    for ((retry=1; retry<=MAX_RETRY; retry++)); do
        if git clone --bare "$src_url" "$clone_dir" >> "$PROJECT_LOG" 2>&1; then
            if ! cd "$clone_dir"; then
                project_log "ERROR" "Failed to enter directory $clone_dir"
                rm -rf "$clone_dir"
                return 1
            fi

            git remote set-url origin "$dst_url" >> "$PROJECT_LOG" 2>&1

            if git push --all >> "$PROJECT_LOG" 2>&1 && git push --tags >> "$PROJECT_LOG" 2>&1; then
                project_log "SUCCESS" "Push successful: ${dst_grp}/${dst_prj}"
                cd - >/dev/null || exit 1
                rm -rf "$clone_dir"
                return 0
            else
                project_log "WARNING" "Push failed (attempt ${retry}), retrying..."
            fi

            cd - >/dev/null || exit 1
        else
            project_log "WARNING" "Clone failed (attempt ${retry}), retrying..."
        fi

        rm -rf "$clone_dir"
        sleep $((retry * 3))
    done

    project_log "ERROR" "Migration failed: $src_url"
    rm -rf "$clone_dir"
    return 1
}

validate_input() {
    if [ ! -f "$PROJECT_LIST" ]; then
        log "ERROR" "Project list file not found: $PROJECT_LIST"
        exit 1
    fi

    while IFS= read -r line; do
        if [ "$(echo "$line" | wc -w)" -ne 4 ]; then
            log "ERROR" "Invalid format: $line (Expected: source_group source_project destination_group destination_project)"
            exit 1
        fi
    done < <(grep -vE '^#|^$' "$PROJECT_LIST")
}

main() {
    PROJECT_LIST=${1:-project_list.txt}
    validate_input

    mkdir -p "$TEMP_DIR"
    total=$(grep -vcE '^#|^$' "$PROJECT_LIST")
    log "INFO" "Starting migration of ${total} projects"

    while IFS= read -r line; do
        current=$((current + 1))
        read -r src_grp src_prj dst_grp dst_prj <<< "$line"

        show_progress "$current" "$total"

        if migrate_project "$src_grp" "$src_prj" "$dst_grp" "$dst_prj"; then
            success=$((success + 1))
            log "INFO" "Project ${src_grp}/${src_prj} migrated successfully."
        else
            fail=$((fail + 1))
            log "ERROR" "Project ${src_grp}/${src_prj} migration failed."
        fi

    done < <(grep -vE '^#|^$' "$PROJECT_LIST")

    echo ""
    log "INFO" "Migration completed: Success ${success}, Failures ${fail}"
    exit $fail
}

main "$@"
