#!/bin/bash

################################################################################
# Database Snapshot & Restore Script
#
# Purpose: Pull database snapshot from remote production server and restore
#          to local development environment
#
# Usage: ./sync_db_from_remote.sh [OPTIONS]
#
# Options:
#   --skip-local-backup    Skip creating local safety backup
#   --snapshot-only        Only pull snapshot, don't restore
#   --restore-from FILE    Restore from existing snapshot file
#   --dry-run             Show what would be done without doing it
#   -h, --help            Show this help message
#
# Requirements:
#   - SSH access to root@69.167.170.85
#   - /Volumes/databank directory exists and is writable
#   - Docker and docker-compose installed locally
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

################################################################################
# Configuration
################################################################################

REMOTE_HOST="69.167.170.85"
REMOTE_USER="root"
REMOTE_APP_USER="tianzhic"
REMOTE_PROJECT_PATH="/home/tianzhic/dogetionary"
REMOTE_CONTAINER="dogetionary_postgres_1"

LOCAL_PROJECT_PATH="/Users/biubiu/projects/dogetionary"
LOCAL_CONTAINER="dogetionary-postgres-1"

BACKUP_DIR="/Volumes/databank"
LOG_DIR="/Volumes/databank"

DB_NAME="dogetionary"
DB_USER="dogeuser"
DB_PASS="dogepass"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/db_sync_${TIMESTAMP}.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Command line options
################################################################################

SKIP_LOCAL_BACKUP=false
SNAPSHOT_ONLY=false
RESTORE_FROM=""
DRY_RUN=false

################################################################################
# Functions
################################################################################

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}ℹ ${NC}$@"
    log "INFO" "$@"
}

log_success() {
    echo -e "${GREEN}✓${NC} $@"
    log "SUCCESS" "$@"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $@"
    log "WARNING" "$@"
}

log_error() {
    echo -e "${RED}✗${NC} $@" >&2
    log "ERROR" "$@"
}

die() {
    log_error "$@"
    log_error "Script failed. Check log file: ${LOG_FILE}"
    exit 1
}

show_help() {
    cat << EOF
Database Snapshot & Restore Script

Usage: $0 [OPTIONS]

Options:
  --skip-local-backup    Skip creating local safety backup
  --snapshot-only        Only pull snapshot, don't restore
  --restore-from FILE    Restore from existing snapshot file
  --dry-run             Show what would be done without doing it
  -h, --help            Show this help message

Examples:
  # Full sync (snapshot + restore)
  $0

  # Only pull snapshot without restoring
  $0 --snapshot-only

  # Restore from existing snapshot
  $0 --restore-from /Volumes/databank/dogetionary_snapshot_20251213_120000.sql.gz

  # Dry run to see what would happen
  $0 --dry-run

EOF
}

confirm() {
    local prompt="$1"
    local response

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would prompt: ${prompt}"
        return 0
    fi

    read -p "${prompt} (yes/no): " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            log_warning "Operation cancelled by user"
            return 1
            ;;
    esac
}

check_prerequisites() {
    log_info "Running pre-flight checks..."

    # Check if backup directory exists
    if [ ! -d "$BACKUP_DIR" ]; then
        die "Backup directory does not exist: ${BACKUP_DIR}"
    fi

    if [ ! -w "$BACKUP_DIR" ]; then
        die "Backup directory is not writable: ${BACKUP_DIR}"
    fi

    # Check if docker-compose is available
    if ! command -v docker-compose &> /dev/null; then
        die "docker-compose command not found"
    fi

    # Check if local project exists
    if [ ! -f "${LOCAL_PROJECT_PATH}/docker-compose.yml" ]; then
        die "Local project docker-compose.yml not found: ${LOCAL_PROJECT_PATH}/docker-compose.yml"
    fi

    # Check SSH access to remote
    log_info "Testing SSH connection to remote server..."
    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "${REMOTE_USER}@${REMOTE_HOST}" "echo 'SSH connection successful'" &> /dev/null; then
        log_warning "Cannot connect to remote server with key-based auth. You may be prompted for password."
    fi

    # Check if local container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${LOCAL_CONTAINER}$"; then
        log_warning "Local PostgreSQL container '${LOCAL_CONTAINER}' is not running"
        log_info "Starting local containers..."
        if [ "$DRY_RUN" = false ]; then
            cd "${LOCAL_PROJECT_PATH}"
            docker-compose up -d postgres
            sleep 5
        fi
    fi

    log_success "Pre-flight checks passed"
}

get_remote_db_info() {
    log_info "Gathering remote database information..."

    local remote_cmd="su - ${REMOTE_APP_USER} -c 'cd ${REMOTE_PROJECT_PATH} && docker exec ${REMOTE_CONTAINER} psql -U ${DB_USER} -d ${DB_NAME} -t -c \"SELECT pg_size_pretty(pg_database_size(\\\"${DB_NAME}\\\"))\"'"

    local db_size=$(ssh "${REMOTE_USER}@${REMOTE_HOST}" "${remote_cmd}" 2>/dev/null | xargs || echo "unknown")

    log_info "Remote database size: ${db_size}"
}

create_local_safety_backup() {
    if [ "$SKIP_LOCAL_BACKUP" = true ]; then
        log_warning "Skipping local safety backup (--skip-local-backup flag)"
        return 0
    fi

    log_info "Creating local safety backup..."

    local backup_file="${BACKUP_DIR}/dogetionary_local_backup_${TIMESTAMP}.sql.gz"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create: ${backup_file}"
        return 0
    fi

    if ! docker exec -t "${LOCAL_CONTAINER}" pg_dump -U "${DB_USER}" "${DB_NAME}" | gzip -9 > "${backup_file}"; then
        die "Failed to create local safety backup"
    fi

    local file_size=$(du -h "${backup_file}" | cut -f1)
    log_success "Local safety backup created: ${backup_file} (${file_size})"
}

pull_remote_snapshot() {
    log_info "Pulling database snapshot from remote server..."

    local snapshot_file="${BACKUP_DIR}/dogetionary_remote_snapshot_${TIMESTAMP}.sql.gz"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would pull snapshot to: ${snapshot_file}"
        echo "$snapshot_file"
        return 0
    fi

    # Create temporary script on remote to dump database
    local remote_dump_cmd="docker exec -t ${REMOTE_CONTAINER} pg_dump -U ${DB_USER} ${DB_NAME}"

    log_info "Executing pg_dump on remote server via SSH..."
    log_info "This may take a while for large databases..."

    if ! ssh "${REMOTE_USER}@${REMOTE_HOST}" "su - ${REMOTE_APP_USER} -c 'cd ${REMOTE_PROJECT_PATH} && ${remote_dump_cmd}'" | gzip -9 > "${snapshot_file}"; then
        die "Failed to pull remote snapshot"
    fi

    # Verify file was created and has content
    if [ ! -s "${snapshot_file}" ]; then
        die "Snapshot file is empty or was not created: ${snapshot_file}"
    fi

    local file_size=$(du -h "${snapshot_file}" | cut -f1)
    log_success "Remote snapshot pulled successfully: ${snapshot_file} (${file_size})"

    # Verify gzip integrity
    log_info "Verifying snapshot file integrity..."
    if ! gunzip -t "${snapshot_file}" 2>/dev/null; then
        die "Snapshot file is corrupted (gzip test failed)"
    fi

    log_success "Snapshot file integrity verified"

    echo "$snapshot_file"
}

stop_dependent_services() {
    log_info "Stopping dependent services (app, nginx)..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would stop: app, nginx"
        return 0
    fi

    cd "${LOCAL_PROJECT_PATH}"
    docker-compose stop app nginx || log_warning "Failed to stop some services (they may not be running)"

    log_success "Dependent services stopped"
}

restore_snapshot() {
    local snapshot_file="$1"

    log_info "Preparing to restore from: ${snapshot_file}"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would restore database from snapshot"
        return 0
    fi

    if [ ! -f "$snapshot_file" ]; then
        die "Snapshot file not found: ${snapshot_file}"
    fi

    local file_size=$(du -h "${snapshot_file}" | cut -f1)
    log_info "Snapshot file size: ${file_size}"

    if ! confirm "This will DESTROY the current local database and replace it with the snapshot. Continue?"; then
        die "Restore cancelled by user"
    fi

    # Terminate all connections to the database
    log_info "Terminating all connections to database..."
    docker exec -i "${LOCAL_CONTAINER}" psql -U "${DB_USER}" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid();" 2>&1 | tee -a "${LOG_FILE}" || log_warning "Connection termination completed with warnings"

    # Drop existing database
    log_info "Dropping existing database..."
    if ! docker exec -i "${LOCAL_CONTAINER}" dropdb -U "${DB_USER}" --if-exists "${DB_NAME}" 2>&1 | tee -a "${LOG_FILE}"; then
        log_warning "dropdb command completed with warnings (this may be normal)"
    fi

    # Create fresh database
    log_info "Creating fresh database..."
    if ! docker exec -i "${LOCAL_CONTAINER}" createdb -U "${DB_USER}" "${DB_NAME}"; then
        die "Failed to create database"
    fi

    log_success "Database recreated successfully"

    # Restore from snapshot
    log_info "Restoring data from snapshot..."
    log_info "This may take several minutes..."

    if ! gunzip -c "${snapshot_file}" | docker exec -i "${LOCAL_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" --set ON_ERROR_STOP=on 2>&1 | tee -a "${LOG_FILE}"; then
        log_error "Restore failed! Database may be in inconsistent state"
        log_error "You can restore from local backup: ${BACKUP_DIR}/dogetionary_local_backup_${TIMESTAMP}.sql.gz"
        die "Database restore failed"
    fi

    log_success "Database restored successfully"
}

verify_restore() {
    log_info "Verifying database restoration..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would verify database"
        return 0
    fi

    # Check table count
    local table_count=$(docker exec -i "${LOCAL_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'" | xargs)

    log_info "Tables in database: ${table_count}"

    if [ "$table_count" -eq 0 ]; then
        log_warning "No tables found in database - restore may have failed"
        return 1
    fi

    # Check for critical tables
    local critical_tables=("user_preferences" "saved_words" "reviews" "definitions")
    for table in "${critical_tables[@]}"; do
        local exists=$(docker exec -i "${LOCAL_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = '${table}')" | xargs)
        if [ "$exists" = "t" ]; then
            local row_count=$(docker exec -i "${LOCAL_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT COUNT(*) FROM ${table}" | xargs)
            log_info "  - ${table}: ${row_count} rows"
        else
            log_warning "  - ${table}: NOT FOUND"
        fi
    done

    log_success "Database verification completed"
}

restart_services() {
    log_info "Restarting all services..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would restart all services"
        return 0
    fi

    cd "${LOCAL_PROJECT_PATH}"
    docker-compose up -d

    # Wait for services to be healthy
    log_info "Waiting for services to become healthy..."
    sleep 5

    log_success "Services restarted"
}

check_health() {
    log_info "Checking application health..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would check health endpoint"
        return 0
    fi

    # Wait a bit for app to start
    sleep 3

    if curl -s -f http://localhost:5000/health > /dev/null 2>&1; then
        log_success "Application health check passed"
    else
        log_warning "Application health check failed (app may still be starting)"
        log_info "You can manually check: curl http://localhost:5000/health"
    fi
}

print_summary() {
    local snapshot_file="$1"
    local start_time="$2"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    echo "================================================================"
    log_success "Database sync completed successfully!"
    echo "================================================================"
    echo ""
    log_info "Summary:"
    log_info "  - Snapshot file: ${snapshot_file}"
    log_info "  - Log file: ${LOG_FILE}"
    log_info "  - Duration: ${duration} seconds"
    echo ""

    if [ "$SKIP_LOCAL_BACKUP" = false ] && [ "$DRY_RUN" = false ]; then
        log_info "Local backup created at:"
        log_info "  ${BACKUP_DIR}/dogetionary_local_backup_${TIMESTAMP}.sql.gz"
        echo ""
    fi

    log_info "To restore from this snapshot again, run:"
    log_info "  $0 --restore-from ${snapshot_file}"
    echo ""
}

################################################################################
# Main Script
################################################################################

main() {
    local start_time=$(date +%s)

    echo "================================================================"
    echo "  Database Snapshot & Restore Script"
    echo "  Started at: $(date)"
    echo "================================================================"
    echo ""

    log_info "Log file: ${LOG_FILE}"
    echo ""

    # Check prerequisites
    check_prerequisites

    # Get remote database info
    get_remote_db_info

    # Handle restore-from option
    if [ -n "$RESTORE_FROM" ]; then
        log_info "Restore mode: using existing snapshot file"
        SNAPSHOT_FILE="$RESTORE_FROM"

        if [ ! -f "$SNAPSHOT_FILE" ]; then
            die "Snapshot file not found: ${SNAPSHOT_FILE}"
        fi
    else
        # Create local safety backup
        create_local_safety_backup

        # Pull snapshot from remote
        SNAPSHOT_FILE=$(pull_remote_snapshot)
    fi

    # If snapshot-only mode, exit here
    if [ "$SNAPSHOT_ONLY" = true ]; then
        log_success "Snapshot-only mode: snapshot pulled successfully"
        log_info "Snapshot location: ${SNAPSHOT_FILE}"
        log_info "To restore this snapshot, run:"
        log_info "  $0 --restore-from ${SNAPSHOT_FILE}"
        exit 0
    fi

    # Stop dependent services
    stop_dependent_services

    # Restore snapshot
    restore_snapshot "$SNAPSHOT_FILE"

    # Verify restoration
    verify_restore

    # Restart services
    restart_services

    # Check application health
    check_health

    # Print summary
    print_summary "$SNAPSHOT_FILE" "$start_time"
}

################################################################################
# Parse command line arguments
################################################################################

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-local-backup)
                SKIP_LOCAL_BACKUP=true
                shift
                ;;
            --snapshot-only)
                SNAPSHOT_ONLY=true
                shift
                ;;
            --restore-from)
                RESTORE_FROM="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Parse arguments and run main
parse_args "$@"
main
