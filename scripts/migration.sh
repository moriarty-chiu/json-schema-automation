#!/bin/bash

# Configuration
SOURCE_DOMAIN="gitlab.example.com"             # Source server domain
SOURCE_PROTOCOL="http"                         # Source protocol (http/https/ssh)
DESTINATION_DOMAIN="new-gitlab.example.com"    # Destination server domain
DESTINATION_PROTOCOL="https"                   # Destination protocol (https/ssh)
TEMP_DIR="migration_tmp"                       # Temporary directory
MAX_RETRY=2                                    # Max retry count
LOG_FILE="migration_$(date +%Y%m%d_%H%M%S).log" # Main log file

# Counters
total=0
success=0
fail=0
current=0

# Cleanup function (cleans whole temp dir on exit)
cleanup() {
    rm -rf "$TEMP_DIR"
    echo "Temporary directory cleaned."
}
trap cleanup EXIT

# Logging function
log() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Generate URL for git clone/push
generate_url() {
    local domain=$1
    local protocol=$2
    local group=$3
    local project=$4

    case $protocol in
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

# Migration function
migrate_project() {
    local src_grp=$1
    local src_prj=$2
    local dst_grp=$3
    local dst_prj=$4

    local src_url
    src_url=$(generate_url "$SOURCE_DOMAIN" "$SOURCE_PROTOCOL" "$src_grp" "$src_prj")

    local dst_url
    dst_url=$(generate_url "$DESTINATION_DOMAIN" "$DESTINATION_PROTOCOL" "$dst_grp" "$dst_prj")

    local clone_dir="${TEMP_DIR}/${src_prj}_$(date +%s%N)_$$"

    log "INFO" "Migrating: $src_url → $dst_url"

    for ((retry=1; retry<=MAX_RETRY; retry++)); do
        rm -rf "$clone_dir"
        mkdir -p "$clone_dir"

        if git clone --mirror "$src_url" "$clone_dir" >> "$LOG_FILE" 2>&1; then
            cd "$clone_dir" || { log "ERROR" "Failed to enter directory $clone_dir"; return 1; }

            git remote set-url origin "$dst_url" >> "$LOG_FILE" 2>&1

            # Mirror push with hidden ref rejection handling
            push_output=$(git push --mirror 2>&1)
            push_exit=$?

            if [ $push_exit -ne 0 ]; then
                hidden_ref_errors=$(echo "$push_output" | grep -c "deny updating a hidden ref")
                total_rejected=$(echo "$push_output" | grep -c "\[remote rejected\]")

                if [ "$total_rejected" -gt 0 ] && [ "$hidden_ref_errors" -eq "$total_rejected" ]; then
                    log "WARNING" "All rejections are hidden refs, ignoring."
                    push_exit=0
                else
                    log "ERROR" "Push failed with other errors at attempt $retry: $push_output"
                fi
            fi

            if [ $push_exit -eq 0 ]; then
                log "SUCCESS" "Mirror push succeeded for $dst_grp/$dst_prj"
                cd - >/dev/null || exit
                rm -rf "$clone_dir"
                return 0
            fi

            cd - >/dev/null || exit
            rm -rf "$clone_dir"
            sleep $((retry * 3))
        else
            log "WARNING" "Clone failed at attempt $retry, retrying..."
            rm -rf "$clone_dir"
            sleep $((retry * 3))
        fi
    done

    log "ERROR" "Migration failed for $src_url"
    return 1
}

# Input validation
validate_input() {
    if [ ! -f "$PROJECT_LIST" ]; then
        log "ERROR" "Project list file not found: $PROJECT_LIST"
        exit 1
    fi

    while IFS= read -r line; do
        if [ "$(echo "$line" | wc -w)" -ne 4 ]; then
            log "ERROR" "Invalid line format: $line (expecting 4 params)"
            exit 1
        fi
    done < <(grep -vE '^#|^$' "$PROJECT_LIST")
}

# Main program
main() {
    PROJECT_LIST=${1:-project_list.txt}
    validate_input

    mkdir -p "$TEMP_DIR"
    total=$(grep -vcE '^#|^$' "$PROJECT_LIST")
    log "INFO" "Starting migration of $total projects"

    while IFS= read -r line; do
        ((current++))
        read -r src_grp src_prj dst_grp dst_prj <<< "$line"

        log "INFO" "Processing project $current/$total: $src_grp/$src_prj"

        if migrate_project "$src_grp" "$src_prj" "$dst_grp" "$dst_prj"; then
            ((success++))
        else
            ((fail++))
        fi

        echo "----------------------------------------" >> "$LOG_FILE"
    done < <(grep -vE '^#|^$' "$PROJECT_LIST")

    log "INFO" "Migration completed. Success: $success, Failures: $fail"
    exit $fail
}

# Run
main "$@"
