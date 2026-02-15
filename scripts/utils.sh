#!/usr/bin/env bash
#
# Utility functions for Stalwart installation and configuration scripts
#

# Color codes for output (if terminal supports it)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Logging functions with GitHub Actions workflow commands support

log_info() {
    local message="$1"
    echo -e "${BLUE}ℹ${NC} ${message}"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}✓${NC} ${message}"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}⚠${NC} ${message}"
    # Also output as GitHub Actions warning
    echo "::warning::${message}"
}

log_error() {
    local message="$1"
    echo -e "${RED}✗${NC} ${message}" >&2
    # Also output as GitHub Actions error
    echo "::error::${message}" >&2
}

log_debug() {
    local message="$1"
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${BLUE}[DEBUG]${NC} ${message}"
    fi
}

# Validate JSON string
# Args: $1 = JSON string
# Returns: 0 if valid, 1 if invalid
validate_json() {
    local json_string="$1"
    
    if [ -z "$json_string" ]; then
        return 1
    fi
    
    if ! echo "$json_string" | jq empty >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Check if a command exists
# Args: $1 = command name
# Returns: 0 if exists, 1 if not
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Ensure a command exists, exit with error if not
# Args: $1 = command name
require_command() {
    local cmd="$1"
    
    if ! command_exists "$cmd"; then
        log_error "Required command '$cmd' not found. Please install it first."
        exit 1
    fi
}

# Wait for a TCP port to be available
# Args: $1 = host, $2 = port, $3 = timeout (seconds)
# Returns: 0 if available, 1 if timeout
wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-30}"
    
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if timeout 1 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    
    return 1
}

# Check if a URL is accessible
# Args: $1 = URL, $2 = timeout (seconds, optional)
# Returns: 0 if accessible, 1 if not
check_url() {
    local url="$1"
    local timeout="${2:-5}"
    
    if curl -sf -m "$timeout" "$url" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Retry a command multiple times
# Args: $1 = max attempts, $2 = delay between attempts, $3+ = command and args
# Returns: 0 if command succeeds, 1 if all attempts fail
retry_command() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local cmd=("$@")
    
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if "${cmd[@]}"; then
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_debug "Command failed (attempt $attempt/$max_attempts), retrying in ${delay}s..."
            sleep "$delay"
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "Command failed after $max_attempts attempts: ${cmd[*]}"
    return 1
}

# Mask sensitive data in logs (for GitHub Actions)
# Args: $1 = sensitive string
mask_secret() {
    local secret="$1"
    
    if [ -n "$secret" ]; then
        echo "::add-mask::${secret}"
    fi
}

# Create a GitHub Actions group (collapsible section in logs)
# Args: $1 = group name
start_group() {
    local group_name="$1"
    echo "::group::${group_name}"
}

# End a GitHub Actions group
end_group() {
    echo "::endgroup::"
}

# Set a GitHub Actions output
# Args: $1 = output name, $2 = output value
set_output() {
    local name="$1"
    local value="$2"
    
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        echo "${name}=${value}" >> "$GITHUB_OUTPUT"
    else
        echo "::set-output name=${name}::${value}"
    fi
}

# Generate a random password
# Args: $1 = length (default: 16)
# Returns: random password on stdout
generate_password() {
    local length="${1:-16}"
    
    if command_exists openssl; then
        openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
    elif command_exists pwgen; then
        pwgen -s "$length" 1
    else
        # Fallback to /dev/urandom
        tr -dc 'A-Za-z0-9!@#$%^&*' </dev/urandom | head -c "$length"
    fi
}

# Check if running as root
# Returns: 0 if root, 1 if not
is_root() {
    [ "$(id -u)" -eq 0 ]
}

# Ensure script is running as root
require_root() {
    if ! is_root; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Get the Linux distribution name
get_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        echo "$DISTRIB_ID" | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

# Check if systemd is available
has_systemd() {
    command_exists systemctl && [ -d /run/systemd/system ]
}

# URL encode a string
# Args: $1 = string to encode
url_encode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o
    
    for (( pos=0; pos<strlen; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] )
                o="${c}"
                ;;
            * )
                printf -v o '%%%02x' "'$c"
                ;;
        esac
        encoded+="${o}"
    done
    
    echo "${encoded}"
}

# Parse JSON value from a JSON string
# Args: $1 = JSON string, $2 = key path (e.g., ".data.token")
# Returns: value on stdout
json_get() {
    local json="$1"
    local key="$2"
    
    echo "$json" | jq -r "$key // empty" 2>/dev/null
}

# Check if a file is writable or can be created
# Args: $1 = file path
# Returns: 0 if writable, 1 if not
is_writable() {
    local filepath="$1"
    
    if [ -e "$filepath" ]; then
        [ -w "$filepath" ]
    else
        local dirpath=$(dirname "$filepath")
        [ -w "$dirpath" ]
    fi
}

# Export all functions for use in other scripts
export -f log_info log_success log_warning log_error log_debug
export -f validate_json command_exists require_command
export -f wait_for_port check_url retry_command
export -f mask_secret start_group end_group set_output
export -f generate_password is_root require_root
export -f get_distro has_systemd url_encode json_get is_writable
