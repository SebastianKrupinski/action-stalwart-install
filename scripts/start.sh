#!/usr/bin/env bash
#
# Starts a throwaway Stalwart server and provisions its domains and user accounts
# with stalwart-cli. Used by the action, and runnable on its own.
#
# Everything lives under STALWART_DIR: the server and CLI binaries, the configuration,
# the data store and the log. The data store path is always given explicitly, since
# Stalwart's default store path can belong to a real installation on the machine.
#
#   STALWART_VERSION         server release                  (default: v1.1.1)
#   STALWART_CLI_VERSION     stalwart-cli release            (default: v2.0.0)
#   STALWART_DIR             working directory               (default: $PWD/.stalwart)
#   STALWART_URL             base URL the server publishes   (default: http://localhost:8080)
#   STALWART_HOSTNAME        server hostname                 (default: mail.<first domain>)
#   STALWART_ADMIN_USER      administrator name              (default: admin)
#   STALWART_ADMIN_PASSWORD  administrator password          (default: secretpassword)
#   STALWART_DOMAINS         JSON: [{"name": "example.com", "description": "..."}]
#   STALWART_USERS           JSON: [{"email": "user@example.com", "password": "...", "name": "...", "quota": 1073741824}]
#
# Domains of user addresses are created even when not listed in STALWART_DOMAINS.
# Running it again reuses a running server and applies the domains and users again.
# Stop it with: kill "$(cat "$STALWART_DIR/server.pid")"

set -euo pipefail

version=${STALWART_VERSION:-v1.1.1}
cli_version=${STALWART_CLI_VERSION:-v2.0.0}
dir=${STALWART_DIR:-$PWD/.stalwart}
url=${STALWART_URL:-http://localhost:8080}
admin_user=${STALWART_ADMIN_USER:-admin}
admin_password=${STALWART_ADMIN_PASSWORD:-secretpassword}
domains=${STALWART_DOMAINS:-[]}
users=${STALWART_USERS:-[]}
# the server always listens on 8080 for HTTP, whatever URL it publishes
local_url=http://127.0.0.1:8080

say() { echo "$*"; }
fail() { echo "::error::$*" >&2; exit 1; }

for command in curl jq tar xz sha256sum timeout; do
    command -v "$command" > /dev/null || fail "Required command '$command' not found"
done

sudo=
if [ "$(id -u)" -ne 0 ]; then
    # the server also opens the privileged mail ports
    command -v sudo > /dev/null || fail "Needs root, or sudo for the privileged mail ports"
    sudo=sudo
fi

case "$(uname -m)" in
    x86_64 | amd64) target=x86_64-unknown-linux-gnu ;;
    aarch64 | arm64) target=aarch64-unknown-linux-gnu ;;
    *) fail "Unsupported architecture $(uname -m)" ;;
esac

mkdir -p "$dir/bin" "$dir/data"

# Releases publish the SHA-256 of each archive: the server in its sigstore bundle,
# the CLI in a .sha256 file next to it
server_release=https://github.com/stalwartlabs/stalwart/releases/download/$version
cli_release=https://github.com/stalwartlabs/cli/releases/download/$cli_version

if [ ! -x "$dir/bin/stalwart" ]; then
    say "Downloading Stalwart $version ($target)"
    archive=$dir/stalwart-$version.tar.gz
    curl -sSfL -o "$archive" "$server_release/stalwart-$target.tar.gz"
    digest=$(curl -sSfL "$server_release/stalwart-$target.tar.gz.sigstore.json" \
        | jq -r '.messageSignature.messageDigest.digest' | base64 -d | od -An -tx1 | tr -d ' \n')
    echo "$digest  $archive" | sha256sum --check --quiet - || fail "Stalwart archive does not match its published digest"
    tar -xzf "$archive" -C "$dir/bin" stalwart
    chmod +x "$dir/bin/stalwart"
fi

if [ ! -x "$dir/bin/stalwart-cli" ]; then
    say "Downloading stalwart-cli $cli_version ($target)"
    archive=$dir/stalwart-cli-$cli_version.tar.xz
    curl -sSfL -o "$archive" "$cli_release/stalwart-cli-$target.tar.xz"
    digest=$(curl -sSfL "$cli_release/stalwart-cli-$target.tar.xz.sha256" | cut -d' ' -f1)
    echo "$digest  $archive" | sha256sum --check --quiet - || fail "stalwart-cli archive does not match its published digest"
    tar -xJf "$archive" -C "$dir/bin" --strip-components=1 "stalwart-cli-$target/stalwart-cli"
    chmod +x "$dir/bin/stalwart-cli"
fi

# With a configuration file naming the data store, Stalwart skips bootstrap mode and
# starts with default settings, which the plan below completes
if [ -f "$dir/server.pid" ] && $sudo kill -0 "$(cat "$dir/server.pid")" 2> /dev/null; then
    say "Stalwart is already running (pid $(cat "$dir/server.pid"))"
else
    say "Starting Stalwart"
    printf '{"@type":"RocksDb","path":"%s/"}\n' "$dir/data" > "$dir/config.json"
    $sudo env STALWART_RECOVERY_ADMIN="$admin_user:$admin_password" STALWART_PUBLIC_URL="$url" \
        nohup "$dir/bin/stalwart" --config "$dir/config.json" > "$dir/server.log" 2>&1 &
    echo $! > "$dir/server.pid"
fi

if ! timeout 60 sh -c "until curl -sf '$local_url/healthz/ready' > /dev/null; do sleep 1; done"; then
    cat "$dir/server.log" >&2
    fail "Stalwart did not become ready"
fi

# One plan: the domains (listed, then those of user addresses), the default domain
# and hostname, then the user accounts. Upserts match existing objects by name.
jq -nc --argjson domains "$domains" --argjson users "$users" --arg hostname "${STALWART_HOSTNAME:-}" '
    def domain_of: split("@")[1];
    ([$domains[].name] + [$users[].email | domain_of]) as $names
    | (reduce $names[] as $name ([]; if index([$name]) then . else . + [$name] end)) as $names
    | ($names | to_entries | map({key: .value, value: "d\(.key)"}) | from_entries) as $ref
    | ($domains | map({key: .name, value: .}) | from_entries) as $listed
    | if $names == [] then empty else
        {"@type": "upsert", object: "Domain", matchOn: ["name"], value: (
            $names | map({key: $ref[.], value: ({name: .} + (if $listed[.].description then {description: $listed[.].description} else {} end))}) | from_entries
        )},
        {"@type": "update", object: "SystemSettings", value: {
            defaultHostname: (if $hostname != "" then $hostname else "mail.\($names[0])" end),
            defaultDomainId: "#d0"
        }}
      end,
    if $users == [] then empty else
        {"@type": "upsert", object: "Account", matchOn: ["name", "domainId"], value: (
            $users | to_entries | map({key: "u\(.key)", value: (
                {"@type": "User", name: (.value.email | split("@")[0]), domainId: "#\($ref[.value.email | domain_of])",
                 credentials: {"0": {"@type": "Password", secret: .value.password}}}
                + (if .value.name then {description: .value.name} else {} end)
                + (if .value.quota then {quotas: {maxDiskQuota: .value.quota}} else {} end)
            )}) | from_entries
        )}
    end
' > "$dir/plan.ndjson" || fail "STALWART_DOMAINS and STALWART_USERS must be JSON arrays"

if [ -s "$dir/plan.ndjson" ]; then
    say "Creating domains and accounts"
    STALWART_URL=$local_url STALWART_USER=$admin_user STALWART_PASSWORD=$admin_password \
        "$dir/bin/stalwart-cli" apply --file "$dir/plan.ndjson" --no-color --quiet
fi

say "Stalwart is ready at $url"
