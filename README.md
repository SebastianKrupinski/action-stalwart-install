# Stalwart Mail Server Installation Action

A GitHub Action to install and configure [Stalwart Mail Server](https://stalw.art/) with optional automated setup for admin password, domains, and users.

## Features

- 🚀 **One-step installation** of Stalwart Mail Server
- 🔐 **Automated configuration** via REST API
- 🌐 **Multi-domain support** with JSON array input
- 👥 **Bulk user creation** from JSON configuration
- 🔒 **Secure handling** of passwords using GitHub Secrets
- 📦 **Cross-platform** support (Linux systemd/init.d, macOS)

## Prerequisites

- Root/sudo access (action must run as root)
- Required commands: `curl`, `jq`, `tar`
- Linux (Ubuntu, Debian, RHEL, etc.) or macOS
- Network access to download Stalwart binaries

## Quick Start

### Basic Installation (No Configuration)

```yaml
name: Install Stalwart
on: [push]

jobs:
  setup:
    runs-on: ubuntu-latest
    
    steps:
      - name: Install Stalwart Mail Server
        uses: SebastianKrupinski/action-stalwart-install@v1
        # This installs with default settings
        # Web admin: http://localhost:8080/login
        # Default password: changeme
```

### Full Automated Setup

```yaml
name: Install and Configure Stalwart
on: [push]

jobs:
  setup:
    runs-on: ubuntu-latest
    
    steps:
      - name: Install and Configure Stalwart
        uses: SebastianKrupinski/action-stalwart-install@v1
        with:
          # Use GitHub Secrets for sensitive data!
          admin_password: ${{ secrets.STALWART_ADMIN_PASSWORD }}
          
          domains: |
            [
              {
                "name": "example.com",
                "description": "Primary domain"
              },
              {
                "name": "example.org",
                "description": "Secondary domain"
              }
            ]
          
          users: |
            [
              {
                "email": "admin@example.com",
                "password": "${{ secrets.ADMIN_USER_PASSWORD }}",
                "name": "System Administrator",
                "quota": 5368709120
              },
              {
                "email": "support@example.com",
                "password": "${{ secrets.SUPPORT_USER_PASSWORD }}",
                "name": "Support Team",
                "quota": 2147483648
              }
            ]
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `admin_password` | No | `changeme` | Admin password for Stalwart web interface. **Use GitHub Secrets!** |
| `domains` | No | `""` | JSON array of domains to create. See [Domain Schema](#domain-json-schema) |
| `users` | No | `""` | JSON array of users to create. See [User Schema](#user-json-schema) |

## JSON Schemas

### Domain JSON Schema

```json
[
  {
    "name": "example.com",          // Required: domain name
    "description": "Primary domain"  // Optional: description
  }
]
```

**Fields:**
- `name` (string, **required**): Domain name (e.g., "example.com")
- `description` (string, optional): Human-readable description

### User JSON Schema

```json
[
  {
    "email": "user@example.com",     // Required: email address
    "password": "SecurePass123!",    // Required: user password
    "name": "Full Name",             // Optional: display name
    "quota": 1073741824              // Optional: storage quota in bytes
  }
]
```

**Fields:**
- `email` (string, **required**): User email address
- `password` (string, **required**): User password (use GitHub Secrets!)
- `name` (string, optional): Display name (defaults to email if not provided)
- `quota` (integer, optional): Storage quota in bytes (default: 1GB = 1073741824)

**Common quota values:**
- 1 GB = `1073741824`
- 5 GB = `5368709120`
- 10 GB = `10737418240`
- 50 GB = `53687091200`

## Usage Examples

### Example 1: Basic Installation Only

Install Stalwart without any configuration. You'll configure it manually via web UI.

```yaml
- uses: SebastianKrupinski/action-stalwart-install@v1
```

After installation, access the web admin at `http://your-server:8080/login` with username `admin` and password `changeme`.

### Example 2: Set Admin Password Only

```yaml
- uses: SebastianKrupinski/action-stalwart-install@v1
  with:
    admin_password: ${{ secrets.STALWART_ADMIN_PASSWORD }}
```

### Example 3: Create Domains Only

```yaml
- uses: SebastianKrupinski/action-stalwart-install@v1
  with:
    admin_password: ${{ secrets.STALWART_ADMIN_PASSWORD }}
    domains: |
      [
        {"name": "example.com", "description": "Main"},
        {"name": "example.net", "description": "Secondary"}
      ]
```

### Example 4: Complete Setup with Multiple Users

```yaml
- uses: SebastianKrupinski/action-stalwart-install@v1
  with:
    admin_password: ${{ secrets.STALWART_ADMIN_PASSWORD }}
    
    domains: |
      [
        {"name": "mycompany.com"},
        {"name": "mycompany.net"}
      ]
    
    users: |
      [
        {
          "email": "ceo@mycompany.com",
          "password": "${{ secrets.CEO_PASSWORD }}",
          "name": "CEO",
          "quota": 10737418240
        },
        {
          "email": "team@mycompany.com",
          "password": "${{ secrets.TEAM_PASSWORD }}",
          "name": "Team Mailbox",
          "quota": 5368709120
        },
        {
          "email": "noreply@mycompany.com",
          "password": "${{ secrets.NOREPLY_PASSWORD }}",
          "name": "No Reply",
          "quota": 1073741824
        }
      ]
```

### Example 5: Using JSON from Files

Store your configuration in separate files:

```yaml
- name: Checkout repository
  uses: actions/checkout@v4

- name: Install Stalwart
  uses: SebastianKrupinski/action-stalwart-install@v1
  with:
    admin_password: ${{ secrets.STALWART_ADMIN_PASSWORD }}
    domains: ${{ readFile('.github/stalwart/domains.json') }}
    users: ${{ readFile('.github/stalwart/users.json') }}
```

## Security Best Practices

### 🔒 Always Use GitHub Secrets

**NEVER** hardcode passwords in your workflow files!

```yaml
# ❌ WRONG - Password visible in repository
- uses: SebastianKrupinski/action-stalwart-install@v1
  with:
    admin_password: "MyPassword123"

# ✅ CORRECT - Password stored in GitHub Secrets
- uses: SebastianKrupinski/action-stalwart-install@v1
  with:
    admin_password: ${{ secrets.STALWART_ADMIN_PASSWORD }}
```

### Setting Up GitHub Secrets

1. Go to your repository → **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Add your secrets:
   - `STALWART_ADMIN_PASSWORD`
   - `USER1_PASSWORD`
   - `USER2_PASSWORD`
   - etc.

### Password Requirements

- Use strong, unique passwords (16+ characters)
- Include uppercase, lowercase, numbers, and symbols
- Never reuse passwords across services
- Rotate passwords regularly

### Additional Security Tips

- Restrict Stalwart web admin to localhost or VPN
- Configure firewall rules (ports 25, 465, 587, 993, 8080)
- Enable TLS/SSL for all email protocols
- Regularly update Stalwart to latest version
- Monitor logs for suspicious activity
- Use fail2ban or similar intrusion prevention

## How It Works

1. **Prerequisites Check**: Validates root access and required commands (`curl`, `jq`, `tar`)
2. **Installation**: Downloads and installs Stalwart Mail Server binary
3. **Service Setup**: Creates system user and service (systemd/init.d/launchd)
4. **API Wait**: Waits for Stalwart API to become available (up to 60 seconds)
5. **Authentication**: Authenticates with default password (`changeme`)
6. **Password Update**: Changes admin password if provided
7. **Domain Creation**: Creates domains via REST API
8. **User Creation**: Creates users with passwords and quotas via REST API

## Troubleshooting

### Action Fails: "Required command 'jq' not found"

Install `jq` before running the action:

```yaml
- name: Install dependencies
  run: |
    sudo apt-get update
    sudo apt-get install -y jq curl

- name: Install Stalwart
  uses: SebastianKrupinski/action-stalwart-install@v1
```

### Action Fails: "This action must run as root"

Use `sudo` in your workflow:

```yaml
- name: Install Stalwart
  run: sudo -E env "PATH=$PATH" ...
```

Or use a container that runs as root:

```yaml
jobs:
  setup:
    runs-on: ubuntu-latest
    container:
      image: ubuntu:latest
      options: --user root
```

### Stalwart API Timeout

If the API doesn't become available in 60 seconds:
- Check system resources (CPU, memory)
- Review Stalwart logs: `journalctl -u stalwart -n 50`
- Verify port 8080 is not already in use: `netstat -tuln | grep 8080`

### Domain/User Creation Fails

- Verify JSON syntax is valid (use a JSON validator)
- Check Stalwart logs for detailed errors
- Ensure domains are created before users
- Verify email addresses match created domains

### "Failed to authenticate" Error

- Installation might already be configured
- Try accessing web UI manually: `http://localhost:8080/login`
- Check if admin password was previously changed
- Review configuration script logs

## Advanced Configuration

### Custom Installation Path

The installation path is fixed at `/opt/stalwart` to match Stalwart defaults. If you need a different path, fork this action and modify `STALWART_INSTALL_PATH`.

### Running in Docker

```yaml
jobs:
  setup:
    runs-on: ubuntu-latest
    container:
      image: ubuntu:22.04
      options: --privileged
    
    steps:
      - name: Install dependencies
        run: |
          apt-get update
          apt-get install -y curl jq sudo systemd
      
      - name: Install Stalwart
        uses: SebastianKrupinski/action-stalwart-install@v1
        with:
          admin_password: ${{ secrets.STALWART_ADMIN_PASSWORD }}
```

### Post-Installation Configuration

After installation, Stalwart's web admin is available at `http://localhost:8080/login`. You can:
- Configure SMTP, IMAP, POP3 settings
- Set up SSL/TLS certificates
- Configure spam filters and antivirus
- Manage additional domains and users
- View logs and statistics

## Service Management

### Check Service Status

```bash
# Systemd (most Linux distributions)
sudo systemctl status stalwart

# Init.d (older systems)
sudo service stalwart status

# macOS
sudo launchctl list | grep stalwart
```

### Restart Service

```bash
# Systemd
sudo systemctl restart stalwart

# Init.d
sudo service stalwart restart

# macOS
sudo launchctl stop system/stalwart.mail
sudo launchctl start system/stalwart.mail
```

### View Logs

```bash
# Systemd
sudo journalctl -u stalwart -f

# Traditional logs
sudo tail -f /opt/stalwart/logs/*.log
```

## Uninstallation

To remove Stalwart:

```bash
# Stop service
sudo systemctl stop stalwart
sudo systemctl disable stalwart

# Remove service file
sudo rm /etc/systemd/system/stalwart.service
sudo systemctl daemon-reload

# Remove installation directory
sudo rm -rf /opt/stalwart

# Remove system user (optional)
sudo userdel stalwart
```

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This action is licensed under the AGPL-3.0 License. See [LICENSE](LICENSE) for details.

Stalwart Mail Server is developed by [Stalwart Labs](https://stalw.art/) and is licensed under AGPL-3.0-only OR LicenseRef-SEL.

## Support

- **Stalwart Documentation**: https://stalw.art/docs
- **Issue Tracker**: https://github.com/SebastianKrupinski/action-stalwart-install/issues
- **Stalwart Community**: https://github.com/stalwartlabs/stalwart/discussions

## Acknowledgments

- Based on the official [Stalwart installation script](https://github.com/stalwartlabs/stalwart)
- Thanks to the Stalwart Labs team for creating an excellent mail server

---

**Note**: This is an unofficial GitHub Action and is not affiliated with or endorsed by Stalwart Labs.
