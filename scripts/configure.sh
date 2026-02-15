#!/usr/bin/env bash
#
# Stalwart Post-Installation Configuration Script
# Configures admin password, domains, and users via REST API
#

set -euo pipefail

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Configuration
readonly STALWART_PATH="${STALWART_INSTALL_PATH:-/opt/stalwart}"
readonly API_URL="http://localhost:8080/api"
readonly MAX_RETRIES=60
readonly RETRY_DELAY=2

# Read the generated password from installation
DEFAULT_ADMIN_PASSWORD="changeme"
if [ -f "${STALWART_PATH}/.init_password" ]; then
    DEFAULT_ADMIN_PASSWORD=$(cat "${STALWART_PATH}/.init_password" | tr -d '\n\r')
    log_info "Using generated password from installation"
    # Clean up the password file for security
    rm -f "${STALWART_PATH}/.init_password"
else
    log_warning "Password file not found, using default password"
fi
readonly DEFAULT_ADMIN_PASSWORD

# Environment variables (passed from action.yml)
DOMAINS_JSON="${STALWART_DOMAINS:-}"
USERS_JSON="${STALWART_USERS:-}"

# Main configuration function
main() {
    log_info "Starting Stalwart post-installation configuration"
    
    # Wait for Stalwart API to be ready
    if ! wait_for_stalwart_api; then
        log_error "Stalwart API failed to become ready within timeout"
        return 1
    fi
    
    # Set current password (start with generated one)
    local current_password="$DEFAULT_ADMIN_PASSWORD"
    
    # Test authentication with generated password
    log_info "Verifying API access with generated password..."
    if ! test_auth "$current_password"; then
        log_error "Failed to authenticate with generated password"
        return 1
    fi
    
    log_success "API authentication verified"
    log_info "📝 Generated admin password: ${current_password}"
    log_warning "⚠️  Save this password securely - it won't be shown again!"
    
    # Save admin password to temp file for testing/debugging (remove in production)
    echo "$current_password" > /tmp/stalwart_admin_password
    chmod 600 /tmp/stalwart_admin_password
    
    # Create domains if provided
    if [ -n "$DOMAINS_JSON" ]; then
        log_info "Creating domains..."
        if validate_json "$DOMAINS_JSON"; then
            create_domains "$current_password" "$DOMAINS_JSON"
        else
            log_error "Invalid domains JSON format"
            return 1
        fi
    else
        log_info "No domains specified, skipping domain creation"
    fi
    
    # Create users if provided
    if [ -n "$USERS_JSON" ]; then
        log_info "Creating users..."
        if validate_json "$USERS_JSON"; then
            create_users "$current_password" "$USERS_JSON"
        else
            log_error "Invalid users JSON format"
            return 1
        fi
    else
        log_info "No users specified, skipping user creation"
    fi
    
    log_success "Stalwart configuration completed successfully!"
    return 0
}

# Wait for Stalwart API to be ready
wait_for_stalwart_api() {
    log_info "Waiting for Stalwart API to be ready (timeout: ${MAX_RETRIES}s)..."
    
    local attempt=0
    while [ $attempt -lt $MAX_RETRIES ]; do
        # Try to access the API login endpoint
        if curl -sf -m 5 "${API_URL%/api}/login" >/dev/null 2>&1; then
            log_success "Stalwart API is ready"
            return 0
        fi
        
        attempt=$((attempt + 1))
        if [ $attempt -lt $MAX_RETRIES ]; then
            sleep $RETRY_DELAY
        fi
    done
    
    return 1
}

# Test authentication with Stalwart API using Basic Auth
# Args: $1 = password
# Returns: 0 if auth works, 1 otherwise
test_auth() {
    local password="$1"
    
    local http_code
    local response
    
    # Test by querying domains endpoint (works on fresh and configured systems)
    response=$(curl -s -w "\n%{http_code}" \
        -u "admin:${password}" \
        "${API_URL}/principal?types=domain&limit=1")
    
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" = "200" ]; then
        return 0
    else
        log_error "Authentication test failed with HTTP $http_code"
        response=$(echo "$response" | sed '$d')
        log_error "Response: $response"
        return 1
    fi
}

# Create domains from JSON array
# Args: $1 = password, $2 = domains JSON array
create_domains() {
    local password="$1"
    local domains_json="$2"
    
    local domain_count
    domain_count=$(echo "$domains_json" | jq 'length' 2>/dev/null)
    
    if [ -z "$domain_count" ] || [ "$domain_count" = "0" ]; then
        log_warning "No domains found in JSON array"
        return 0
    fi
    
    log_info "Creating $domain_count domain(s)..."
    
    local index=0
    local created=0
    local failed=0
    
    while [ $index -lt "$domain_count" ]; do
        local domain
        domain=$(echo "$domains_json" | jq -c ".[$index]" 2>/dev/null)
        
        if [ -z "$domain" ] || [ "$domain" = "null" ]; then
            log_warning "Skipping invalid domain at index $index"
            failed=$((failed + 1))
            index=$((index + 1))
            continue
        fi
        
        local domain_name
        domain_name=$(echo "$domain" | jq -r '.name // empty' 2>/dev/null)
        
        if [ -z "$domain_name" ]; then
            log_warning "Skipping domain without 'name' field at index $index"
            failed=$((failed + 1))
            index=$((index + 1))
            continue
        fi
        
        # Build API payload with required structure
        local payload
        payload=$(echo "$domain" | jq '{
            type: "domain",
            quota: (.quota // 0),
            name: .name,
            description: (.description // ""),
            secrets: [],
            emails: [],
            urls: [],
            memberOf: [],
            roles: [],
            lists: [],
            members: [],
            enabledPermissions: [],
            disabledPermissions: [],
            externalMembers: []
        }' 2>/dev/null)
        
        # Create domain via API
        if curl -sf -X POST "${API_URL}/principal" \
            -u "admin:${password}" \
            -H "Content-Type: application/json" \
            -d "$payload" >/dev/null 2>&1; then
            log_success "✓ Created domain: $domain_name"
            created=$((created + 1))
        else
            log_warning "✗ Failed to create domain: $domain_name"
            failed=$((failed + 1))
        fi
        
        index=$((index + 1))
    done
    
    log_info "Domain creation summary: $created created, $failed failed"
    return 0
}

# Create users from JSON array
# Args: $1 = password, $2 = users JSON array
create_users() {
    local password="$1"
    local users_json="$2"
    
    local user_count
    user_count=$(echo "$users_json" | jq 'length' 2>/dev/null)
    
    if [ -z "$user_count" ] || [ "$user_count" = "0" ]; then
        log_warning "No users found in JSON array"
        return 0
    fi
    
    log_info "Creating $user_count user(s)..."
    
    local index=0
    local created=0
    local failed=0
    
    while [ $index -lt "$user_count" ]; do
        local user
        user=$(echo "$users_json" | jq -c ".[$index]" 2>/dev/null)
        
        if [ -z "$user" ] || [ "$user" = "null" ]; then
            log_warning "Skipping invalid user at index $index"
            failed=$((failed + 1))
            index=$((index + 1))
            continue
        fi
        
        local email
        email=$(echo "$user" | jq -r '.email // empty' 2>/dev/null)
        
        if [ -z "$email" ]; then
            log_warning "Skipping user without 'email' field at index $index"
            failed=$((failed + 1))
            index=$((index + 1))
            continue
        fi
        
        # Hash the password with SHA-512 (API requires hashed passwords in secrets array)
        local hashed_password=""
        local raw_password
        raw_password=$(echo "$user" | jq -r '.password // empty' 2>/dev/null)
        
        if [ -n "$raw_password" ]; then
            if command -v mkpasswd >/dev/null 2>&1; then
                hashed_password=$(mkpasswd -m sha-512 "$raw_password")
            elif command -v openssl >/dev/null 2>&1; then
                hashed_password=$(openssl passwd -6 "$raw_password")
            else
                log_warning "Cannot hash password for $email - no mkpasswd or openssl found"
            fi
        fi
        
        # Build API payload with required structure  
        local payload
        if [ -n "$hashed_password" ]; then
            payload=$(echo "$user" | jq --arg email "$email" --arg pwd "$hashed_password" '{
                type: "individual",
                quota: (.quota // 0),
                name: $email,
                description: (.name // ""),
                secrets: [$pwd],
                emails: [$email],
                urls: [],
                memberOf: [],
                roles: ["user"],
                lists: [],
                members: [],
                enabledPermissions: [],
                disabledPermissions: [],
                externalMembers: []
            }' 2>/dev/null)
        else
            payload=$(echo "$user" | jq --arg email "$email" '{
                type: "individual",
                quota: (.quota // 0),
                name: $email,
                description: (.name // ""),
                secrets: [],
                emails: [$email],
                urls: [],
                memberOf: [],
                roles: ["user"],
                lists: [],
                members: [],
                enabledPermissions: [],
                disabledPermissions: [],
                externalMembers: []
            }' 2>/dev/null)
        fi
        
        # Create user via API
        if curl -sf -X POST "${API_URL}/principal" \
            -u "admin:${password}" \
            -H "Content-Type: application/json" \
            -d "$payload" >/dev/null 2>&1; then
            log_success "✓ Created user: $email"
            created=$((created + 1))
        else
            log_warning "✗ Failed to create user: $email"
            failed=$((failed + 1))
        fi
        
        index=$((index + 1))
    done
    
    log_info "User creation summary: $created created, $failed failed"
    return 0
}

# Execute main function
main "$@"
