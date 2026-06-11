#Requires -Version 5.1
<#
.SYNOPSIS
    Azure CLI login + interactive command launcher.
.DESCRIPTION
    Signs in via device code, shows account context, then offers a menu
    to run common read-only az commands or a full discovery scan.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- UI helpers ---------------------------------------------------------------

function Write-Line {
    param([string]$Text = '', [ConsoleColor]$Color = 'DarkGray')
    Write-Host $Text -ForegroundColor $Color
}

function Write-Title {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=' * 60) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * 60) -ForegroundColor Cyan
}

function Write-Ok   { param([string]$Text) Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Err  { param([string]$Text) Write-Host "  [!!] $Text" -ForegroundColor Red }
function Write-Info { param([string]$Text) Write-Host "  >> $Text" -ForegroundColor Yellow }

function Write-Banner {
    Clear-Host
    Write-Host ''
    Write-Host '  +----------------------------------------------------------+' -ForegroundColor Cyan
    Write-Host '  |                                                          |' -ForegroundColor Cyan
    Write-Host '  |           AZURE CLI  -  COMMAND CENTER                   |' -ForegroundColor Cyan
    Write-Host '  |           Softlogic Holdings PLC                         |' -ForegroundColor DarkCyan
    Write-Host '  |                                                          |' -ForegroundColor Cyan
    Write-Host '  +----------------------------------------------------------+' -ForegroundColor Cyan
    Write-Host ''
}

function Wait-Continue {
    Write-Host ''
    Write-Host '  Press Enter to return to menu...' -ForegroundColor DarkGray
    [void](Read-Host)
}

function Invoke-AzMenuCommand {
    param(
        [string]$Label,
        [string]$Command
    )

    Write-Title $Label
    Write-Info $Command
    Write-Host ''

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    try {
        Invoke-Expression $Command
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
            Write-Err "Command exited with code $LASTEXITCODE"
        }
    }
    catch {
        Write-Err $_.Exception.Message
    }
    finally {
        $ErrorActionPreference = $prevEap
    }

    Wait-Continue
}

# -- Login --------------------------------------------------------------------

function Test-AzureSession {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $null = az account show 2>$null
        return $LASTEXITCODE -eq 0
    }
    finally {
        $ErrorActionPreference = $prevEap
    }
}

function Start-AzureLogin {
    param([switch]$Force)

    Write-Banner
    Write-Title 'Sign in to Azure'
    Write-Host ''

    if (-not $Force -and (Test-AzureSession)) {
        $existing = Get-AccountContext
        if ($existing) {
            Write-Ok 'Existing Azure session found'
            Show-AccountSummary -Context $existing
            Write-Host ''
            Write-Host '  [Y]  Use this session' -ForegroundColor Green
            Write-Host '  [L]  Login again (device code)' -ForegroundColor White
            Write-Host '  [Q]  Quit' -ForegroundColor DarkGray
            Write-Host ''
            $reuse = (Read-Host '  Choice').Trim().ToUpper()
            if ($reuse -eq 'Q') { return $false }
            if ($reuse -ne 'L') { return $true }
            Write-Host ''
        }
    }

    Write-Host '  Device-code login starting...' -ForegroundColor White
    Write-Host '  A URL and code will appear below.' -ForegroundColor DarkGray
    Write-Host '  Open the URL in your browser and enter the code.' -ForegroundColor DarkGray
    Write-Host ''

    # Do not pipe az login — piping hides/buffers the device-code output.
    & az login --allow-no-subscriptions --use-device-code

    if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Err 'Login failed or was cancelled.'
        return $false
    }

    Write-Host ''
    Write-Ok 'Login successful'
    return $true
}

function Get-AccountContext {
    $json = az account show 2>$null | ConvertFrom-Json
    if (-not $json) { return $null }
    return [PSCustomObject]@{
        User         = $json.user.name
        Subscription = $json.name
        SubId        = $json.id
        Tenant       = $json.tenantDisplayName
        State        = $json.state
    }
}

function Show-AccountSummary {
    param($Context)

    Write-Host ''
    Write-Host '  +-- Signed in ----------------------------------------------+' -ForegroundColor Green
    Write-Host ('  |  User          : {0,-42} |' -f $Context.User) -ForegroundColor White
    Write-Host ('  |  Subscription  : {0,-42} |' -f $Context.Subscription) -ForegroundColor White
    Write-Host ('  |  Tenant        : {0,-42} |' -f $Context.Tenant) -ForegroundColor White
    Write-Host ('  |  State         : {0,-42} |' -f $Context.State) -ForegroundColor White
    Write-Host '  +----------------------------------------------------------+' -ForegroundColor Green
    Write-Host ''
}

# -- Command catalogue --------------------------------------------------------

$CommandCatalog = [ordered]@{
    '1' = @{
        Title    = 'Account & Subscription'
        Commands = @(
            @{ Key = '1'; Label = 'Show current account';           Command = 'az account show' }
            @{ Key = '2'; Label = 'List all subscriptions (table)'; Command = 'az account list -o table' }
            @{ Key = '3'; Label = 'List role assignments for me';   Command = 'az role assignment list --assignee (az account show --query user.name -o tsv) -o table' }
            @{ Key = '4'; Label = 'Switch subscription (interactive)'; Command = '__SWITCH_SUB__' }
        )
    }
    '2' = @{
        Title    = 'Resource Groups'
        Commands = @(
            @{ Key = '1'; Label = 'List resource groups (table)'; Command = 'az group list -o table' }
            @{ Key = '2'; Label = 'List resource groups (JSON)';  Command = 'az group list' }
        )
    }
    '3' = @{
        Title    = 'All Resources'
        Commands = @(
            @{ Key = '1'; Label = 'List all resources (table)';     Command = 'az resource list -o table' }
            @{ Key = '2'; Label = 'List VMs only';                  Command = 'az resource list --resource-type Microsoft.Compute/virtualMachines -o table' }
            @{ Key = '3'; Label = 'List storage accounts (resource)'; Command = 'az resource list --resource-type Microsoft.Storage/storageAccounts -o table' }
        )
    }
    '4' = @{
        Title    = 'Virtual Machines'
        Commands = @(
            @{ Key = '1'; Label = 'List VMs (table)';  Command = 'az vm list -o table' }
            @{ Key = '2'; Label = 'List VMs (JSON)';   Command = 'az vm list' }
            @{ Key = '3'; Label = 'List VM sizes in region'; Command = 'az vm list-sizes --location southeastasia -o table' }
        )
    }
    '5' = @{
        Title    = 'Storage'
        Commands = @(
            @{ Key = '1'; Label = 'List storage accounts (table)'; Command = 'az storage account list -o table' }
            @{ Key = '2'; Label = 'List storage accounts (JSON)'; Command = 'az storage account list' }
        )
    }
    '6' = @{
        Title    = 'Networking'
        Commands = @(
            @{ Key = '1'; Label = 'List virtual networks';  Command = 'az network vnet list -o table' }
            @{ Key = '2'; Label = 'List NSGs';              Command = 'az network nsg list -o table' }
            @{ Key = '3'; Label = 'List public IPs';        Command = 'az network public-ip list -o table' }
            @{ Key = '4'; Label = 'List NICs';              Command = 'az network nic list -o table' }
            @{ Key = '5'; Label = 'List load balancers';    Command = 'az network lb list -o table' }
        )
    }
    '7' = @{
        Title    = 'App Service & Functions'
        Commands = @(
            @{ Key = '1'; Label = 'List App Service plans'; Command = 'az appservice plan list -o table' }
            @{ Key = '2'; Label = 'List web apps';          Command = 'az webapp list -o table' }
            @{ Key = '3'; Label = 'List function apps';     Command = 'az functionapp list -o table' }
        )
    }
    '8' = @{
        Title    = 'Databases'
        Commands = @(
            @{ Key = '1'; Label = 'List SQL servers';   Command = 'az sql server list -o table' }
            @{ Key = '2'; Label = 'List Cosmos DB';     Command = 'az cosmosdb list -o table' }
        )
    }
    '9' = @{
        Title    = 'Key Vault'
        Commands = @(
            @{ Key = '1'; Label = 'List Key Vaults (table)'; Command = 'az keyvault list -o table' }
        )
    }
    '10' = @{
        Title    = 'Containers & Kubernetes'
        Commands = @(
            @{ Key = '1'; Label = 'List container registries'; Command = 'az acr list -o table' }
            @{ Key = '2'; Label = 'List AKS clusters';         Command = 'az aks list -o table' }
            @{ Key = '3'; Label = 'List container instances';  Command = 'az container list -o table' }
        )
    }
    '11' = @{
        Title    = 'Monitoring & Governance'
        Commands = @(
            @{ Key = '1'; Label = 'Recent activity log';      Command = 'az monitor activity-log list --offset 7d -o table' }
            @{ Key = '2'; Label = 'Log Analytics workspaces'; Command = 'az monitor log-analytics workspace list -o table' }
            @{ Key = '3'; Label = 'Policy assignments';       Command = 'az policy assignment list -o table' }
            @{ Key = '4'; Label = 'Resource locks';           Command = 'az lock list -o table' }
        )
    }
    '12' = @{
        Title    = 'Entra ID (via az)'
        Commands = @(
            @{ Key = '1'; Label = 'List users';         Command = 'az ad user list -o table' }
            @{ Key = '2'; Label = 'Show my user profile'; Command = 'az ad user show --id (az account show --query user.name -o tsv)' }
            @{ Key = '3'; Label = 'List groups';          Command = 'az ad group list -o table' }
            @{ Key = '4'; Label = 'List service principals'; Command = 'az ad sp list --query "[].{DisplayName:displayName, AppId:appId}" -o table' }
        )
    }
}

$DiscoveryCommands = @(
    @{ Label = 'Current account';           Command = 'az account show' }
    @{ Label = 'Subscriptions';             Command = 'az account list -o table' }
    @{ Label = 'Resource groups';           Command = 'az group list -o table' }
    @{ Label = 'All resources';             Command = 'az resource list -o table' }
    @{ Label = 'Virtual machines';          Command = 'az vm list -o table' }
    @{ Label = 'Storage accounts';          Command = 'az storage account list -o table' }
    @{ Label = 'Virtual networks';          Command = 'az network vnet list -o table' }
    @{ Label = 'NSGs';                      Command = 'az network nsg list -o table' }
    @{ Label = 'Public IPs';                Command = 'az network public-ip list -o table' }
    @{ Label = 'Web apps';                  Command = 'az webapp list -o table' }
    @{ Label = 'Function apps';             Command = 'az functionapp list -o table' }
    @{ Label = 'SQL servers';               Command = 'az sql server list -o table' }
    @{ Label = 'Key Vaults';                Command = 'az keyvault list -o table' }
    @{ Label = 'AKS clusters';              Command = 'az aks list -o table' }
    @{ Label = 'Container registries';      Command = 'az acr list -o table' }
    @{ Label = 'Log Analytics workspaces'; Command = 'az monitor log-analytics workspace list -o table' }
)

# -- Menus --------------------------------------------------------------------

function Show-CategoryMenu {
    param([string]$CategoryKey)

    $cat = $CommandCatalog[$CategoryKey]
    if (-not $cat) { return }

    while ($true) {
        Write-Banner
        $ctx = Get-AccountContext
        if ($ctx) { Show-AccountSummary -Context $ctx }

        Write-Title $cat.Title
        Write-Host ''

        foreach ($cmd in $cat.Commands) {
            Write-Host ("    [{0}]  {1}" -f $cmd.Key, $cmd.Label) -ForegroundColor White
        }
        Write-Host ''
        Write-Host '    [B]  Back to main menu' -ForegroundColor DarkGray
        Write-Host ''

        $choice = (Read-Host '  Select command').Trim().ToUpper()
        if ($choice -eq 'B') { return }

        $selected = $cat.Commands | Where-Object { $_.Key -eq $choice } | Select-Object -First 1
        if (-not $selected) {
            Write-Err 'Invalid choice.'
            Start-Sleep -Seconds 1
            continue
        }

        if ($selected.Command -eq '__SWITCH_SUB__') {
            Invoke-SwitchSubscription
            continue
        }

        Invoke-AzMenuCommand -Label $selected.Label -Command $selected.Command
    }
}

function Invoke-SwitchSubscription {
    Write-Banner
    Write-Title 'Switch Subscription'
    Write-Host ''
    az account list -o table
    Write-Host ''
    $name = Read-Host '  Enter subscription name or ID'
    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Info 'Cancelled.'
        Wait-Continue
        return
    }
    az account set --subscription $name.Trim()
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Switched to: $name"
        $ctx = Get-AccountContext
        if ($ctx) { Show-AccountSummary -Context $ctx }
    }
    else {
        Write-Err 'Could not switch subscription. Check name/ID and permissions.'
    }
    Wait-Continue
}

function Invoke-FullDiscovery {
    Write-Banner
    Write-Title 'Full Discovery Scan'
    Write-Host ''
    Write-Host '  Running all read-only list commands against the current subscription.' -ForegroundColor White
    Write-Host '  This may take a minute on large environments.' -ForegroundColor DarkGray
    Write-Host ''

    $confirm = (Read-Host '  Continue? [Y/n]').Trim().ToUpper()
    if ($confirm -eq 'N') { return }

    $i = 0
    $total = $DiscoveryCommands.Count

    foreach ($item in $DiscoveryCommands) {
        $i++
        Write-Host ''
        Write-Host ("  -- [{0}/{1}] {2} " -f $i, $total, $item.Label) -ForegroundColor Cyan
        Write-Host ("  >> $($item.Command)") -ForegroundColor DarkGray
        Write-Host ''

        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            Invoke-Expression $item.Command 2>&1 | Out-Host
        }
        catch {
            Write-Err $_.Exception.Message
        }
        finally {
            $ErrorActionPreference = $prevEap
        }
    }

    Write-Host ''
    Write-Ok "Discovery complete ($total sections)."
    Wait-Continue
}

function Invoke-CustomCommand {
    Write-Banner
    Write-Title 'Run Custom az Command'
    Write-Host ''
    Write-Host '  Type any az command (without the word "az" prefix is OK either way).' -ForegroundColor DarkGray
    Write-Host '  Example:  group list -o table' -ForegroundColor DarkGray
    Write-Host ''

    $userCmd = Read-Host '  az'
    if ([string]::IsNullOrWhiteSpace($userCmd)) {
        Write-Info 'Cancelled.'
        Wait-Continue
        return
    }

    $userCmd = $userCmd.Trim()
    if ($userCmd -notmatch '^az\s') {
        $userCmd = "az $userCmd"
    }

    Invoke-AzMenuCommand -Label 'Custom command' -Command $userCmd
}

function Show-MainMenu {
    while ($true) {
        Write-Banner
        $ctx = Get-AccountContext
        if ($ctx) { Show-AccountSummary -Context $ctx }

        Write-Title 'Main Menu'
        Write-Host ''
        Write-Host '  CATEGORIES' -ForegroundColor DarkCyan
        Write-Host ''

        foreach ($key in $CommandCatalog.Keys) {
            $title = $CommandCatalog[$key].Title
            Write-Host ("    [{0,2}]  {1}" -f $key, $title) -ForegroundColor White
        }

        Write-Host ''
        Write-Host '  QUICK ACTIONS' -ForegroundColor DarkCyan
        Write-Host ''
        Write-Host '    [A]   Run full discovery scan (all list commands)' -ForegroundColor Yellow
        Write-Host '    [C]   Run a custom az command' -ForegroundColor White
        Write-Host '    [R]   Refresh account info' -ForegroundColor White
        Write-Host '    [L]   Re-login to Azure' -ForegroundColor White
        Write-Host '    [Q]   Quit' -ForegroundColor DarkGray
        Write-Host ''

        $choice = (Read-Host '  Select option').Trim().ToUpper()

        switch ($choice) {
            'A' { Invoke-FullDiscovery }
            'C' { Invoke-CustomCommand }
            'R' { continue }
            'L' {
                if (-not (Start-AzureLogin -Force)) {
                    Wait-Continue
                }
            }
            'Q' { return }
            default {
                if ($CommandCatalog.Contains($choice)) {
                    Show-CategoryMenu -CategoryKey $choice
                }
                else {
                    Write-Err 'Invalid choice. Enter 1-12, A, C, R, L, or Q.'
                    Start-Sleep -Seconds 1
                }
            }
        }
    }
}

# -- Entry point --------------------------------------------------------------

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Err 'Azure CLI (az) is not installed or not in PATH.'
    Write-Host '  Install: https://aka.ms/installazurecliwindows' -ForegroundColor DarkGray
    exit 1
}

if (-not (Start-AzureLogin)) {
    exit 1
}

$account = Get-AccountContext
if ($account) {
    Show-AccountSummary -Context $account
    Write-Host '  Loading command center...' -ForegroundColor DarkGray
    Start-Sleep -Milliseconds 800
}

Show-MainMenu

Write-Banner
Write-Ok 'Session ended. Run init.ps1 again to reconnect.'
Write-Host ''
