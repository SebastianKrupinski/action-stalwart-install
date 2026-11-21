# Stalwart Mail Server Action

Starts a throwaway [Stalwart](https://stalw.art/) server for development and testing, and creates its domains and user accounts.

The action downloads a pinned Stalwart release and `stalwart-cli`, checks both against the digests their releases publish, starts the server with its own data store, and creates the domains and accounts with `stalwart-cli apply`. The server is ready to use when the step completes.

For Stalwart v1.x. Linux runners, x86_64 or aarch64.

## Usage

```yaml
steps:
  - name: Start Stalwart
    id: stalwart
    uses: SebastianKrupinski/action-stalwart-install@v2
    with:
      domains: '[{"name":"example.com","description":"Primary domain"}]'
      users: |
        [
          {"email":"user1@example.com","password":"violet-harbor-cactus-lantern","name":"User One"},
          {"email":"user2@example.com","password":"amber-glacier-pocket-thunder","quota":1073741824}
        ]

  - name: Run tests
    run: ./run-tests.sh   # JMAP at http://localhost:8080/jmap/session, user1@example.com / violet-harbor-cactus-lantern

  - name: Show Stalwart log
    if: failure()
    run: cat "${{ steps.stalwart.outputs.log }}"
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `version` | `v1.1.1` | Stalwart server release |
| `cli-version` | `v2.0.0` | `stalwart-cli` release |
| `url` | `http://localhost:8080` | Base URL the server publishes in its JMAP session. The server always listens for HTTP on port 8080. |
| `hostname` | `mail.<first domain>` | Server hostname |
| `admin-user` | `admin` | Administrator name |
| `admin-password` | `secretpassword` | Administrator password |
| `domains` | `[]` | JSON array of `{"name", "description"}` |
| `users` | `[]` | JSON array of `{"email", "password", "name", "quota"}`; `quota` is disk space in bytes |
| `directory` | `$RUNNER_TEMP/stalwart` | Directory for the binaries, configuration, data store and log |

Domains of user addresses are created even when they are not listed in `domains`. User passwords must satisfy Stalwart's default password policy, so short or common passwords are refused. The administrator and user passwords are masked in the log.

## Outputs

| Output | Description |
| --- | --- |
| `url` | Base URL the server publishes |
| `directory` | Directory holding the binaries, configuration, data store and log |
| `cli` | Path to `stalwart-cli`, for further changes with the administrator credentials |
| `log` | Path to the server log |

## Notes

- The server is set up for development and tests, not for mail:
  - the limits that guard a real server are lifted: the inbound SMTP throttles (5 connections a second from one address, 25 messages an hour from a sender domain to a recipient) and the IMAP limits per account (2000 requests a minute, 16 connections at once), as tests send many messages and requests in quick succession;
  - IMAP and submission are offered both with implicit TLS (993, 465) and with STARTTLS (143, 587). Logins and authentication need TLS either way.
- The server also opens the mail ports (25, 143, 465, 587, 993, 995, 4190), so it runs with `sudo` when the job is not root.
- Running the action again in the same job reuses the server and applies the domains, users and settings again.
- The server starts from a configuration file naming its data store, so it never enters bootstrap mode. On its first start it is restarted once, as the STARTTLS listeners bind when the server starts.

## Running it locally

`scripts/start.sh` runs on its own, configured by environment variables:

```bash
STALWART_DIR=/tmp/stalwart \
STALWART_USERS='[{"email":"user1@example.com","password":"violet-harbor-cactus-lantern"}]' \
  scripts/start.sh

kill "$(cat /tmp/stalwart/server.pid)"
```

Give it a `STALWART_DIR` of its own: the data store always lives there, never in Stalwart's default store path, which may belong to a real installation.

## License

AGPL-3.0-only
