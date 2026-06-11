# Azure & Microsoft Graph Command Centers

PowerShell interactive menus for **Azure CLI** and **Microsoft 365 (Graph)**. Sign in once with device code, then run common commands from a simple terminal UI — no need to memorize `az` or Graph API paths.

## Features

- **Azure CLI.ps1** — browse subscriptions, VMs, storage, networking, Key Vault, AKS, and more
- **graph email.ps1** — send mail, read profile, calendar, OneDrive, contacts, Teams, To Do
- **All.ps1** — full Graph menu with **all permissions in one sign-in**
- Device-code authentication (works in VS Code / Cursor terminals)
- Session reuse — stay signed in between runs
- Discovery scan — run many list commands in one go

## Prerequisites

| Requirement | Used by |
|-------------|---------|
| [Azure CLI](https://aka.ms/installazurecliwindows) | `Azure CLI.ps1` |
| PowerShell 5.1+ | All scripts |
| Microsoft 365 work/school account | Graph scripts |

Graph scripts use **OAuth device code + REST API**. No `Connect-MgGraph` module required.

## Quick start

```powershell
git clone <your-repo-url>
cd ps

# Azure resources (VMs, storage, resource groups, etc.)
& ".\Azure CLI.ps1"

# Microsoft 365 / Graph (mail, calendar, files, etc.)
& ".\graph email.ps1"

# Graph with all permissions in one login (recommended)
.\All.ps1
```

On first run, open the URL shown in the terminal (e.g. `https://login.microsoft.com/device`) and enter the code.

## Scripts

### Azure CLI.ps1

Signs in with `az login` (device code), then shows an interactive menu.

| Categories (1–12) | Examples |
|-------------------|----------|
| Account & Subscription | `az account show`, switch subscription |
| Resource Groups | List groups |
| Virtual Machines | List / inspect VMs |
| Storage, Networking, App Service | List resources |
| Key Vault, AKS, Monitoring | List and inspect |
| Entra ID | Users, groups (via `az`) |

| Quick key | Action |
|-----------|--------|
| **A** | Full discovery scan |
| **C** | Custom `az` command |
| **L** | Re-login |
| **Q** | Quit |

### graph email.ps1

Signs in to Microsoft Graph via device code. Token saved to `.graph-session.json`.

| Categories (1–7) | Examples |
|------------------|----------|
| Profile & Account | `/me`, manager, mailbox settings |
| Mail | Send email, list messages, folders |
| Calendar | Calendars, today's events |
| OneDrive & Files | Drive info, recent files |
| Contacts, Teams, To Do | List and inspect |

| Quick key | Action |
|-----------|--------|
| **S** | Send email (interactive) |
| **T** | Quick test email |
| **A** | Full discovery scan |
| **C** | Custom Graph GET |
| **L** | Re-login |
| **Q** | Quit |

> **Note:** First use of a category may prompt for extra Graph permissions. Use `All.ps1` to avoid multiple sign-ins.

### All.ps1

Same menu as `graph email.ps1`, but requests all scopes in **one** device-code login:

`User.Read` · `Mail.Read` · `Mail.Send` · `Calendars.Read` · `Files.Read` · `Contacts.Read` · `Team.ReadBasic.All` · `Chat.Read` · `Tasks.Read`

## Sessions

Azure and Graph use **separate** sessions. Signing into one does not sign you into the other.

| Script | Session | Clear |
|--------|---------|-------|
| `Azure CLI.ps1` | Azure CLI token cache | `az logout` |
| `graph email.ps1` / `All.ps1` | `.graph-session.json` | `Remove-Item ".graph-session.json" -Force` |

**Reset both:**

```powershell
az logout
Remove-Item ".graph-session.json" -Force -ErrorAction SilentlyContinue
```

**Check Azure session:**

```powershell
az account show -o table
```

For admin auditing, web portal sign-in history, and token security details, see **[SESSIONS-AND-ADMIN-GUIDE.md](SESSIONS-AND-ADMIN-GUIDE.md)**.

## Project structure

```
ps/
├── Azure CLI.ps1              # Azure CLI command center
├── graph email.ps1            # Microsoft Graph command center
├── All.ps1                    # Graph with all scopes in one login
├── SESSIONS-AND-ADMIN-GUIDE.md
├── README.md
├── .graph-session.json        # Created at runtime — do not commit
└── old/                       # Previous script versions
```

## Security

- **Never commit** `.graph-session.json` — it contains access and refresh tokens
- Never share tokens or paste them in tickets or chat
- Delete the session file on shared machines when done
- Tenant admins cannot view user tokens; they can revoke sessions in [Entra ID](https://entra.microsoft.com)
- Some Graph scopes (e.g. Teams) may require **admin consent** in your organization

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Device code not visible | Run script directly in terminal; do not pipe login output |
| Extra Graph login per category | Use `All.ps1` instead of `graph email.ps1` |
| Photo / manager 404 | Normal — no photo or manager set in directory |
| Access denied (403) | Admin may need to grant consent for the app in Entra ID |
| Stale session | Delete `.graph-session.json` or press **L** to re-login |

## License

Use at your own discretion. Ensure you comply with your organization's IT and security policies when using these scripts against production tenants.
