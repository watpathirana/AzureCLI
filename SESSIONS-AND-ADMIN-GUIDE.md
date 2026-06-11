# Azure & Microsoft Graph Sessions — User & Admin Guide

This document explains how the PowerShell command centers in this repo work, how sessions are stored, how to view or remove them, and what tenant administrators can see in Microsoft web portals.

---

## Project files

| File | Purpose |
|------|---------|
| `Azure CLI.ps1` | Azure CLI login + interactive menu for `az` commands |
| `graph email.ps1` | Microsoft Graph login + interactive menu (mail, calendar, files, etc.) |
| `All.ps1` | Same as Graph menu but requests **all permissions in one sign-in** |
| `.graph-session.json` | Saved Graph token (created automatically; do not commit) |
| `old/` | Previous versions (`init.ps1`, `send.ps1`) for reference |

**Requirement:** [Azure CLI](https://aka.ms/installazurecliwindows) must be installed for `Azure CLI.ps1`. Graph scripts use device-code OAuth only (no `Connect-MgGraph` module).

---

## Overview: two separate sessions

| Script | Auth type | Used for | Session stored |
|--------|-----------|----------|----------------|
| `Azure CLI.ps1` | Azure CLI (`az login`) | VMs, storage, resource groups, networking | Azure CLI token cache (on disk) |
| `graph email.ps1` / `All.ps1` | Microsoft Graph (device code) | Mail, profile, calendar, files, Teams | `.graph-session.json` in repo folder |

These are **independent**. Signing into one does **not** sign you into the other.

---

## How the scripts work

### `Azure CLI.ps1`

1. Signs in with **device code** (`az login --use-device-code`)
2. Reuses existing Azure session if found (`[Y]` / `[L]` / `[Q]`)
3. Shows account card (user, subscription, tenant)
4. Main menu with **12 categories** + quick actions

**Categories:** Account, Resource Groups, All Resources, VMs, Storage, Networking, App Service, Databases, Key Vault, Containers/Kubernetes, Monitoring, Entra ID.

**Quick actions:**

| Key | Action |
|-----|--------|
| A | Full discovery scan (all list commands) |
| C | Custom `az` command |
| R | Refresh account info |
| L | Re-login to Azure |
| Q | Quit |

```powershell
.\Azure` CLI.ps1
```

### `graph email.ps1`

1. Signs in with **device code** (OAuth REST API, not `Connect-MgGraph`)
2. Saves token to `.graph-session.json`
3. Shows account card (user, scopes, expiry)
4. Main menu with **7 categories** + quick actions

**Categories:** Profile & Account, Mail, Calendar, OneDrive & Files, Contacts, Teams, To Do.

**Quick actions:**

| Key | Action |
|-----|--------|
| S | Send email (interactive) |
| T | Quick test email |
| A | Full discovery scan |
| C | Custom Graph GET request |
| R | Refresh account info |
| L | Re-login to Graph |
| Q | Quit |

```powershell
.\graph` email.ps1
```

> Use backticks or quotes for the space in the filename: `& ".\graph email.ps1"`

### `All.ps1` vs `graph email.ps1`

| | `graph email.ps1` | `All.ps1` |
|--|-------------------|-----------|
| Sign-in | Base scopes first; may prompt again per category | **All scopes in one device-code sign-in** |
| Best for | Minimal permissions at first | Full menu access without extra logins |

**All permissions in `All.ps1`:** `User.Read`, `Mail.Read`, `Mail.Send`, `Calendars.Read`, `Files.Read`, `Contacts.Read`, `Team.ReadBasic.All`, `Chat.Read`, `Tasks.Read`, `offline_access`

```powershell
.\All.ps1
```

---

## Part 1 — Local sessions (your machine)

### View Azure CLI session

```powershell
az account show
az account show -o table
az account list -o table
```

### View Graph session

Token file (same folder as the scripts):

```
.graph-session.json
```

Fields:

| Field | Description |
|-------|-------------|
| `account` | Signed-in email |
| `access_token` | Short-lived JWT — **do not share** |
| `refresh_token` | Used to renew access tokens |
| `scopes` | Permissions granted |
| `expires_at` | Access token expiry time |

The Graph menu shows user, scopes, and expiry at the top of each screen.

### Remove Azure CLI session

```powershell
az logout
```

### Remove Graph session

```powershell
Remove-Item ".graph-session.json" -Force
```

### Remove both sessions (full reset)

```powershell
cd D:\ps   # or your repo folder
az logout
Remove-Item ".graph-session.json" -Force -ErrorAction SilentlyContinue
```

### Security notes

- Never commit `.graph-session.json` to git.
- Never share access or refresh tokens.
- Delete the session file when finished on a shared computer.
- Revoke sessions in Entra ID for server-side invalidation (see Part 4).

---

## Part 2 — View sessions on the web (any user)

### Your sign-in history

**URL:** [https://mysignins.microsoft.com](https://mysignins.microsoft.com)

Shows recent sign-ins, app name, location, IP, and success/failure.

### Azure portal session

**URL:** [https://portal.azure.com](https://portal.azure.com)

Profile (top right) shows signed-in account. **Sign out** ends the browser session only.

### Apps with access to your Microsoft 365 data

**URL:** [https://myaccount.microsoft.com](https://myaccount.microsoft.com)

**Settings → Privacy → Apps and services** — review or revoke app access.

---

## Part 3 — Tenant admin: what you can and cannot see

### Cannot view (by design)

| Item | Admin can view? |
|------|-----------------|
| User `access_token` (JWT string) | **No** |
| User `refresh_token` | **No** |
| `.graph-session.json` on a user's PC | **No** |

Microsoft does not expose raw tokens in the portal, logs, or Graph API.

### Can view and audit

| What | Where |
|------|--------|
| Who signed in, when, from where | Entra **Sign-in logs** |
| Which app was used | Entra **Sign-in logs** |
| Who consented to an app | Entra **Audit logs** |
| Which users have access to an app | **Enterprise applications** |
| User activity (mail, files) | Microsoft 365 **Audit** (Purview) |

---

## Part 4 — Tenant admin: step-by-step

### Sign-in logs

1. Open [https://entra.microsoft.com](https://entra.microsoft.com)
2. **Identity → Monitoring & health → Sign-in logs**
3. Filter by **User**, **Application**, **Date**, **Status**

Applications to look for:

| Script | Application name in logs |
|--------|--------------------------|
| `Azure CLI.ps1` | **Azure CLI** |
| `graph email.ps1` / `All.ps1` | **Microsoft Graph Command Line Tools** |

Graph client ID: `14d82eec-204b-4c2f-b7e8-296a70dab67e`

### Enterprise applications

**Entra → Applications → Enterprise applications** → search *Microsoft Graph Command Line Tools*

- **Users and groups** — who has access
- **Permissions** — delegated scopes / admin consent

### Audit logs

**Entra → Monitoring → Audit logs** — filter for:

- *Consent to application*
- *Add delegated permission grant*
- *Add app role assignment*

### Revoke user access

| Action | Steps |
|--------|--------|
| Revoke all sessions for one user | **Entra → Users** → user → **Revoke sessions** |
| Remove user from an app | **Enterprise applications** → app → **Users and groups** → remove |
| Disable app for the org | **Enterprise applications** → app → **Properties** → disable sign-in |

### Example: “Did someone use Graph to send mail?”

1. **Sign-in logs** — filter user + *Microsoft Graph Command Line Tools*
2. **Enterprise applications** — check **Users and groups**
3. **Audit logs** — consent events
4. **Revoke sessions** if needed
5. **M365 Audit** — search mail send events

---

## Part 5 — Microsoft Graph permissions

### `graph email.ps1` (per-category scopes)

First sign-in grants base scopes. Using a new category may trigger an extra device-code prompt:

| Scope set | Permissions added | Used for |
|-----------|-------------------|----------|
| base | `User.Read`, `Mail.Send` | Profile, send email |
| mail | + `Mail.Read` | Inbox, folders |
| calendar | + `Calendars.Read` | Calendar events |
| files | + `Files.Read` | OneDrive |
| contacts | + `Contacts.Read` | Contacts |
| teams | + `Team.ReadBasic.All`, `Chat.Read` | Teams, chats |
| todo | + `Tasks.Read` | To Do lists |

### `All.ps1` (single sign-in)

All scopes above are requested in **one** device-code login. Use this to avoid repeated sign-in prompts.

Some permissions (e.g. Teams) may require **admin consent** in your tenant. Users see access denied (403) until an admin approves the app in Entra ID.

---

## Part 6 — Troubleshooting

| Issue | Solution |
|-------|----------|
| Device code not showing | Do not pipe `az login`; Graph uses REST device flow directly |
| Hidden WAM popup | Scripts avoid `Connect-MgGraph`; use device code in terminal |
| Extra login for calendar/files | Use `All.ps1`, or approve scopes when prompted in `graph email.ps1` |
| `scopes` property error | Delete `.graph-session.json` and sign in again |
| Photo metadata 404 | Normal — user has no profile photo set |
| Manager 404 | Normal — no manager assigned in directory |
| Command not configured | Update to latest script; menu items use URI or Action handlers |
| After send email, Enter shows error | Fixed in current scripts — press Enter to return to submenu, **B** for main menu |

---

## Part 7 — Quick reference links

| Purpose | URL |
|---------|-----|
| Your sign-in history | [mysignins.microsoft.com](https://mysignins.microsoft.com) |
| Azure portal | [portal.azure.com](https://portal.azure.com) |
| Entra admin center | [entra.microsoft.com](https://entra.microsoft.com) |
| Account & app permissions | [myaccount.microsoft.com](https://myaccount.microsoft.com) |
| Graph API reference | [Microsoft Graph REST API](https://learn.microsoft.com/en-us/graph/api/overview) |
| Graph permissions | [Permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference) |
| Install Azure CLI | [aka.ms/installazurecliwindows](https://aka.ms/installazurecliwindows) |

---

## Part 8 — Command cheat sheet

### Azure (`Azure CLI.ps1`)

```powershell
& ".\Azure CLI.ps1"
az account show
az account list -o table
az group list -o table
az vm list -o table
az logout
```

### Graph (`graph email.ps1` or `All.ps1`)

```powershell
& ".\graph email.ps1"
.\All.ps1
Remove-Item ".graph-session.json" -Force
```

### Admin (separate from these scripts)

```powershell
Connect-MgGraph -Scopes "AuditLog.Read.All","Directory.Read.All"
Get-MgAuditLogSignIn -Top 10 -Filter "userPrincipalName eq 'user@domain.com'"
```

---

## Summary

| Question | Answer |
|----------|--------|
| Can a tenant admin view user access tokens? | **No** |
| Can admin see who signed in and which app? | **Yes** — Sign-in logs |
| Can admin revoke access? | **Yes** — Revoke sessions, remove app assignment |
| Where is Graph session stored? | `.graph-session.json` in the repo folder |
| Where is Azure session stored? | Azure CLI token cache; clear with `az logout` |
| Are Azure and Graph sessions linked? | **No** — independent sign-ins |
| One login for all Graph features? | Use **`All.ps1`** |
| How to audit script usage? | Sign-in logs + Enterprise apps + Audit logs |

---

*Last updated: June 2026 — `Azure CLI.ps1`, `graph email.ps1`, `All.ps1`*
