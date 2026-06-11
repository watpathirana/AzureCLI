#Requires -Version 5.1
<#
.SYNOPSIS
    Microsoft Graph login + interactive command launcher.
.DESCRIPTION
    Signs in via device code (all permissions in one sign-in), shows account
    context, then offers a menu to run common Graph commands.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Graph auth config --------------------------------------------------------

$script:GraphClientId  = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
$script:GraphTokenPath = Join-Path $PSScriptRoot '.graph-session.json'
$script:GraphDeviceUrl = 'https://login.microsoftonline.com/organizations/oauth2/v2.0/devicecode'
$script:GraphTokenUrl  = 'https://login.microsoftonline.com/organizations/oauth2/v2.0/token'
$script:GraphBaseUrl   = 'https://graph.microsoft.com/v1.0'

$script:GraphAllScopes = @(
    'User.Read'
    'Mail.Read'
    'Mail.Send'
    'Calendars.Read'
    'Files.Read'
    'Contacts.Read'
    'Team.ReadBasic.All'
    'Chat.Read'
    'Tasks.Read'
    'offline_access'
) -join ' '

# -- UI helpers ---------------------------------------------------------------

function Write-Title {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=' * 60) -ForegroundColor Magenta
    Write-Host "  $Text" -ForegroundColor Magenta
    Write-Host ('=' * 60) -ForegroundColor Magenta
}

function Write-Ok   { param([string]$Text) Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Err  { param([string]$Text) Write-Host "  [!!] $Text" -ForegroundColor Red }
function Write-Info { param([string]$Text) Write-Host "  >> $Text" -ForegroundColor Yellow }

function Write-Banner {
    Clear-Host
    Write-Host ''
    Write-Host '  +----------------------------------------------------------+' -ForegroundColor Magenta
    Write-Host '  |                                                          |' -ForegroundColor Magenta
    Write-Host '  |         MICROSOFT GRAPH  -  COMMAND CENTER               |' -ForegroundColor Magenta
    Write-Host '  |         Softlogic Holdings PLC                           |' -ForegroundColor DarkMagenta
    Write-Host '  |                                                          |' -ForegroundColor Magenta
    Write-Host '  +----------------------------------------------------------+' -ForegroundColor Magenta
    Write-Host ''
}

function Wait-Continue {
    Write-Host ''
    Write-Host '  Press Enter to go back...' -ForegroundColor DarkGray
    [void](Read-Host)
}

function Test-HasProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    return @($Object.PSObject.Properties.Name) -contains $Name
}

function Get-ItemProperty {
    param($Item, [string]$Name)
    if ($null -eq $Item) { return $null }
    if ($Item -is [hashtable]) {
        if ($Item.ContainsKey($Name)) { return $Item[$Name] }
        return $null
    }
    if (Test-HasProperty $Item $Name) { return $Item.$Name }
    return $null
}

function Test-ScopeSatisfied {
    param([string]$Granted, [string]$Required)
    if ([string]::IsNullOrWhiteSpace($Required)) { return $true }
    $grantedText = if ($Granted) { [string]$Granted } else { '' }
    $missing = @(
        $Required.Split(' ', [StringSplitOptions]::RemoveEmptyEntries) |
        Where-Object { $grantedText -notlike "*$_*" }
    )
    return (@($missing).Length -eq 0)
}

function Get-MissingScopes {
    param([string]$Granted, [string]$Required)
    $grantedText = if ($Granted) { [string]$Granted } else { '' }
    @(
        $Required.Split(' ', [StringSplitOptions]::RemoveEmptyEntries) |
        Where-Object { $grantedText -notlike "*$_*" }
    )
}

function Get-HttpStatusCode {
    param($ErrorRecord)
    if ($null -eq $ErrorRecord) { return $null }
    if (-not (Test-HasProperty $ErrorRecord.Exception 'Response')) { return $null }
    if ($null -eq $ErrorRecord.Exception.Response) { return $null }
    return [int]$ErrorRecord.Exception.Response.StatusCode
}

function Get-GraphErrorDetail {
    param($ErrorRecord)
    if ($null -eq $ErrorRecord) { return $null }
    if (-not (Test-HasProperty $ErrorRecord 'ErrorDetails')) { return $null }
    if ($null -eq $ErrorRecord.ErrorDetails) { return $null }
    if (-not (Test-HasProperty $ErrorRecord.ErrorDetails 'Message')) { return $null }
    return $ErrorRecord.ErrorDetails.Message
}

function Get-FriendlyNotFoundMessage {
    param([string]$Uri)
    if ($Uri -match '/me/photo') { return 'No profile photo is set for this account.' }
    if ($Uri -match '/me/manager') { return 'No manager is assigned in the directory for this user.' }
    if ($Uri -match '/directReports') { return 'No direct reports found for this account.' }
    return 'Resource not found. It may not exist or is not available for your account.'
}

function Write-GraphError {
    param($ErrorRecord, [string]$Uri = '')
    if ($null -eq $ErrorRecord) { return }

    $status = Get-HttpStatusCode $ErrorRecord
    $message = $ErrorRecord.Exception.Message
    if ($status -eq 404 -and $Uri) { $message = Get-FriendlyNotFoundMessage $Uri }

    Write-Err $message

    $detail = Get-GraphErrorDetail $ErrorRecord
    if ($detail -and $status -ne 404) {
        Write-Host "  $detail" -ForegroundColor DarkGray
        try {
            $json = $detail | ConvertFrom-Json -ErrorAction Stop
            if (Test-HasProperty $json 'error' -and (Test-HasProperty $json.error 'message')) {
                Write-Host "  $($json.error.message)" -ForegroundColor DarkGray
            }
        }
        catch { }
    }

    Write-Host ''
    switch ($status) {
        404 { Write-Host '  This is normal if the item was never set up in Microsoft 365.' -ForegroundColor DarkGray }
        401 { Write-Host '  Tip: Sign in again with [L] or complete the device-code prompt.' -ForegroundColor DarkGray }
        403 { Write-Host '  Tip: Extra permissions or admin consent may be required.' -ForegroundColor DarkGray }
        default { Write-Host '  Tip: Some commands need extra permissions or admin consent.' -ForegroundColor DarkGray }
    }
}

function Format-GraphOutput {
    param($Data)
    if ($null -eq $Data) { return '(no data)' }
    if ($Data -is [string]) { return $Data }
    return ($Data | ConvertTo-Json -Depth 8)
}

# -- Graph session ------------------------------------------------------------

function Get-JwtClaim {
    param([string]$Token, [string]$Claim)
    $part = $Token.Split('.')[1].Replace('-', '+').Replace('_', '/')
    switch ($part.Length % 4) { 2 { $part += '==' } 3 { $part += '=' } }
    return (ConvertFrom-Json ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part)))).$Claim
}

function Get-GraphSession {
    if (-not (Test-Path $script:GraphTokenPath)) { return $null }
    try {
        $raw = Get-Content -Raw $script:GraphTokenPath | ConvertFrom-Json
        return Normalize-GraphSession $raw
    }
    catch { return $null }
}

function Normalize-GraphSession($Session) {
    if (-not $Session) { return $null }

    $scopes = $null
    if (Test-HasProperty $Session 'scopes') { $scopes = $Session.scopes }

    if ([string]::IsNullOrWhiteSpace($scopes) -and $Session.access_token) {
        $scp = Get-JwtClaim $Session.access_token 'scp'
        if ($scp) { $scopes = $scp }
    }

    if ([string]::IsNullOrWhiteSpace($scopes)) { $scopes = $script:GraphAllScopes }

    $normalized = [PSCustomObject]@{
        account       = $Session.account
        access_token  = $Session.access_token
        refresh_token = $Session.refresh_token
        scopes        = $scopes
        expires_at    = $Session.expires_at
    }

    if (-not (Test-HasProperty $Session 'scopes') -or $Session.scopes -ne $scopes) {
        Save-GraphSession $normalized
    }

    return $normalized
}

function Save-GraphSession($Session) {
    $Session | ConvertTo-Json | Set-Content -Path $script:GraphTokenPath -Encoding UTF8
}

function Test-GraphSession {
    $s = Get-GraphSession
    if (-not $s -or -not $s.access_token) { return $false }
    if ([datetime]$s.expires_at -gt (Get-Date).AddMinutes(5)) { return $true }
    return [bool](Refresh-GraphToken $s)
}

function Refresh-GraphToken($Session) {
    if (-not $Session.refresh_token) { return $null }
    try {
        $token = Invoke-RestMethod -Method Post -Uri $script:GraphTokenUrl -Body @{
            client_id     = $script:GraphClientId
            grant_type    = 'refresh_token'
            refresh_token = $Session.refresh_token
            scope         = $Session.scopes
        }
        $new = [PSCustomObject]@{
            account       = $Session.account
            access_token  = $token.access_token
            refresh_token = if ($token.refresh_token) { $token.refresh_token } else { $Session.refresh_token }
            scopes        = $Session.scopes
            expires_at    = (Get-Date).AddSeconds($token.expires_in).ToString('o')
        }
        Save-GraphSession $new
        return $new
    }
    catch { return $null }
}

function Start-GraphDeviceLogin {
    param([string]$Scopes)

    $device = Invoke-RestMethod -Method Post -Uri $script:GraphDeviceUrl -Body @{
        client_id = $script:GraphClientId
        scope     = $Scopes
    }

    Write-Host ''
    Write-Host $device.message -ForegroundColor Yellow
    Write-Host ''

    $deadline = (Get-Date).AddSeconds($device.expires_in)
    $interval = [math]::Max($device.interval, 5)

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $interval
        try {
            $token = Invoke-RestMethod -Method Post -Uri $script:GraphTokenUrl -Body @{
                client_id   = $script:GraphClientId
                grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
                device_code = $device.device_code
            } -ErrorAction Stop

            $account = Get-JwtClaim $token.access_token 'upn'
            if (-not $account) { $account = Get-JwtClaim $token.access_token 'preferred_username' }

            $session = [PSCustomObject]@{
                account       = $account
                access_token  = $token.access_token
                refresh_token = $token.refresh_token
                scopes        = $Scopes
                expires_at    = (Get-Date).AddSeconds($token.expires_in).ToString('o')
            }
            Save-GraphSession $session
            return $session
        }
        catch {
            $err = $null
            if (Test-HasProperty $_ 'ErrorDetails' -and $_.ErrorDetails) {
                $err = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
            }
            if ($err.error -eq 'authorization_pending') { continue }
            if ($err.error -eq 'slow_down') { $interval += 5; continue }
            throw "Graph sign-in failed: $($err.error_description)"
        }
    }
    throw 'Graph sign-in timed out.'
}

function Get-GraphAccessToken {
    param([switch]$Force)

    $scopes = $script:GraphAllScopes

    if (-not $Force) {
        $existing = Get-GraphSession
        if ($existing -and $existing.access_token) {
            $valid = [datetime]$existing.expires_at -gt (Get-Date).AddMinutes(5)
            if (-not $valid) {
                $existing = Refresh-GraphToken $existing
                $valid = $null -ne $existing
            }
            if ($valid -and $existing.scopes -and (Test-ScopeSatisfied $existing.scopes $scopes)) {
                return $existing.access_token
            }
            if ($valid -and $existing.scopes) {
                $missing = @(Get-MissingScopes $existing.scopes $scopes)
                if ($missing.Length -gt 0) {
                    Write-Host ''
                    Write-Host '  Saved session is missing some permissions.' -ForegroundColor Yellow
                    Write-Host "  Missing: $($missing -join ', ')" -ForegroundColor DarkGray
                    Write-Host '  One sign-in will grant access to all menu features.' -ForegroundColor DarkGray
                }
            }
        }
    }

    Write-Host '  Device-code login (all features in one sign-in)...' -ForegroundColor White
    Write-Host '  Open the URL in your browser and enter the code.' -ForegroundColor DarkGray
    Write-Host '  Grants: profile, mail, calendar, files, contacts, teams, to-do' -ForegroundColor DarkGray
    $session = Start-GraphDeviceLogin -Scopes $scopes
    return $session.access_token
}

function Start-GraphLogin {
    param([switch]$Force)

    Write-Banner
    Write-Title 'Sign in to Microsoft Graph'
    Write-Host ''

    if (-not $Force -and (Test-GraphSession)) {
        $existing = Get-GraphAccountContext
        if ($existing) {
            $hasAll = Test-ScopeSatisfied $existing.Scopes $script:GraphAllScopes
            Write-Ok 'Existing Graph session found'
            Show-AccountSummary -Context $existing
            if (-not $hasAll) {
                Write-Host '  [!] Session has limited permissions — choose [L] to unlock all features.' -ForegroundColor Yellow
            }
            Write-Host ''
            Write-Host '  [Y]  Use this session' -ForegroundColor Green
            Write-Host '  [L]  Login again (all permissions)' -ForegroundColor White
            Write-Host '  [Q]  Quit' -ForegroundColor DarkGray
            Write-Host ''
            $reuse = (Read-Host '  Choice').Trim().ToUpper()
            if ($reuse -eq 'Q') { return $false }
            if ($reuse -eq 'L') { $Force = $true }
            elseif (-not $hasAll) {
                Write-Host ''
                Write-Host '  Upgrading permissions...' -ForegroundColor Yellow
                $Force = $true
            }
            else { return $true }
            Write-Host ''
        }
    }

    try {
        $null = Get-GraphAccessToken -Force:$Force
        Write-Host ''
        Write-Ok 'Login successful — all features enabled'
        return $true
    }
    catch {
        Write-Err $_.Exception.Message
        return $false
    }
}

function Get-GraphAccountContext {
    $s = Get-GraphSession
    if (-not $s) { return $null }
    return [PSCustomObject]@{
        User    = $s.account
        Scopes  = if ($s.scopes) { $s.scopes } else { $script:GraphAllScopes }
        Expires = $s.expires_at
    }
}

function Show-AccountSummary {
    param($Context)
    Write-Host ''
    Write-Host '  +-- Signed in ----------------------------------------------+' -ForegroundColor Green
    Write-Host ('  |  User          : {0,-42} |' -f $Context.User) -ForegroundColor White
    $scopeText = if ($Context.Scopes) { [string]$Context.Scopes } else { '(unknown)' }
    $scopeShort = if ($scopeText.Length -gt 42) { $scopeText.Substring(0, 39) + '...' } else { $scopeText }
    Write-Host ('  |  Scopes        : {0,-42} |' -f $scopeShort) -ForegroundColor White
    Write-Host ('  |  Expires       : {0,-42} |' -f $Context.Expires) -ForegroundColor White
    Write-Host '  +----------------------------------------------------------+' -ForegroundColor Green
    Write-Host ''
}

function Invoke-GraphApi {
    param(
        [string]$Method = 'GET',
        [string]$Uri,
        [string]$Body = $null
    )

    $token = Get-GraphAccessToken
    $headers = @{ Authorization = "Bearer $token" }

    try {
        if ($Body) {
            $headers['Content-Type'] = 'application/json'
            return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -Body $Body
        }
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers
    }
    catch {
        $status = Get-HttpStatusCode $_
        if ($status -eq 401 -or $status -eq 403) {
            throw "Access denied ($status). Complete the device-code sign-in when prompted, or use [L] to re-login."
        }
        if ($status -eq 404) {
            $path = ([uri]$Uri).AbsolutePath
            throw (Get-FriendlyNotFoundMessage $path)
        }
        throw
    }
}

function Invoke-GraphSendMail {
    param([string]$ToEmail, [string]$Subject, [string]$BodyText)

    $token = Get-GraphAccessToken
    $mailJson = @{
        message = @{
            subject = $Subject
            body    = @{ contentType = 'Text'; content = $BodyText }
            toRecipients = @(@{ emailAddress = @{ address = $ToEmail } })
        }
        saveToSentItems = $true
    } | ConvertTo-Json -Depth 10

    $response = Invoke-WebRequest `
        -Method POST `
        -Uri "$script:GraphBaseUrl/me/sendMail" `
        -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } `
        -Body $mailJson `
        -UseBasicParsing

    if ($response.StatusCode -ne 202) { throw "Unexpected response: $($response.StatusCode)" }
    return (Get-GraphSession).account
}

# -- Command catalogue --------------------------------------------------------

$CommandCatalog = [ordered]@{
    '1' = @{
        Title    = 'Profile & Account'
        Commands = @(
            @{ Key = '1'; Label = 'Show my profile';        Uri = '/me' }
            @{ Key = '2'; Label = 'Show my manager';        Uri = '/me/manager' }
            @{ Key = '3'; Label = 'List my direct reports'; Uri = '/me/directReports' }
            @{ Key = '4'; Label = 'Show mailbox settings';  Uri = '/me/mailboxSettings' }
            @{ Key = '5'; Label = 'Show my photo metadata'; Uri = '/me/photo' }
        )
    }
    '2' = @{
        Title    = 'Mail'
        Commands = @(
            @{ Key = '1'; Label = 'Send email (interactive)';  Action = '__SEND_INTERACTIVE__' }
            @{ Key = '2'; Label = 'Quick test email';          Action = '__QUICK_TEST__' }
            @{ Key = '3'; Label = 'List recent messages (10)'; Uri = '/me/messages?$top=10&$select=subject,from,receivedDateTime,isRead' }
            @{ Key = '4'; Label = 'List mail folders';         Uri = '/me/mailFolders?$select=displayName,totalItemCount,unreadItemCount' }
            @{ Key = '5'; Label = 'Unread mail count';         Uri = '/me/mailFolders/inbox' }
        )
    }
    '3' = @{
        Title    = 'Calendar'
        Commands = @(
            @{ Key = '1'; Label = 'List my calendars';  Uri = '/me/calendars?$select=name,isDefaultCalendar' }
            @{ Key = '2'; Label = 'Events next 7 days'; Uri = '__CALENDAR_WEEK__' }
            @{ Key = '3'; Label = 'Today''s events';    Uri = '__CALENDAR_TODAY__' }
        )
    }
    '4' = @{
        Title    = 'OneDrive & Files'
        Commands = @(
            @{ Key = '1'; Label = 'My drive info';       Uri = '/me/drive' }
            @{ Key = '2'; Label = 'Recent files (10)'; Uri = '/me/drive/recent?$top=10' }
            @{ Key = '3'; Label = 'Root folder items';   Uri = '/me/drive/root/children?$top=15&$select=name,size,lastModifiedDateTime' }
        )
    }
    '5' = @{
        Title    = 'Contacts'
        Commands = @(
            @{ Key = '1'; Label = 'List contacts (10)';   Uri = '/me/contacts?$top=10&$select=displayName,emailAddresses,mobilePhone' }
            @{ Key = '2'; Label = 'List contact folders'; Uri = '/me/contactFolders' }
        )
    }
    '6' = @{
        Title    = 'Teams'
        Commands = @(
            @{ Key = '1'; Label = 'List my teams';      Uri = '/me/joinedTeams?$select=displayName,description' }
            @{ Key = '2'; Label = 'List my chats';      Uri = '/me/chats?$top=10&$select=topic,chatType,lastUpdatedDateTime' }
            @{ Key = '3'; Label = 'My presence status'; Uri = '/me/presence' }
        )
    }
    '7' = @{
        Title    = 'To Do'
        Commands = @(
            @{ Key = '1'; Label = 'List To Do lists';   Uri = '/me/todo/lists' }
            @{ Key = '2'; Label = 'Default list tasks'; Uri = '__TODO_DEFAULT__' }
        )
    }
}

$DiscoveryCommands = @(
    @{ Label = 'Profile';         Uri = '/me' }
    @{ Label = 'Mailbox settings'; Uri = '/me/mailboxSettings' }
    @{ Label = 'Mail folders';     Uri = '/me/mailFolders?$select=displayName,totalItemCount' }
    @{ Label = 'Recent messages';  Uri = '/me/messages?$top=5&$select=subject,from,receivedDateTime' }
    @{ Label = 'Calendars';        Uri = '/me/calendars?$select=name' }
    @{ Label = 'Drive info';       Uri = '/me/drive' }
    @{ Label = 'Recent files';     Uri = '/me/drive/recent?$top=5' }
    @{ Label = 'Contacts';         Uri = '/me/contacts?$top=5&$select=displayName' }
    @{ Label = 'Teams';            Uri = '/me/joinedTeams?$select=displayName' }
    @{ Label = 'To Do lists';      Uri = '/me/todo/lists' }
)

# -- Action handlers ----------------------------------------------------------

function Invoke-SendInteractive {
    Write-Title 'Send Email'
    Write-Host ''

    $to = (Read-Host '  To (email address)').Trim()
    if ([string]::IsNullOrWhiteSpace($to)) { Write-Info 'Cancelled.'; Wait-Continue; return }
    if ($to -notmatch '^[^\s@]+@[^\s@]+\.[^\s@]+$') { Write-Err 'Invalid email address.'; Wait-Continue; return }

    $subject = (Read-Host '  Subject').Trim()
    if ([string]::IsNullOrWhiteSpace($subject)) { $subject = '(no subject)' }

    Write-Host '  Body (blank line to finish):' -ForegroundColor DarkGray
    $lines = @()
    while ($true) {
        $line = Read-Host '  '
        if ([string]::IsNullOrWhiteSpace($line)) { break }
        $lines += $line
    }
    $body = if ($lines.Count -gt 0) { $lines -join "`n" } else { ' ' }

    $confirm = (Read-Host '  Send? [Y/n]').Trim().ToUpper()
    if ($confirm -eq 'N') { Write-Info 'Cancelled.'; Wait-Continue; return }

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $sender = Invoke-GraphSendMail -ToEmail $to -Subject $subject -BodyText $body
        Write-Ok "Email sent from $sender"
    }
    catch { Write-Err $_.Exception.Message }
    finally { $ErrorActionPreference = $prevEap }
    Wait-Continue
}

function Invoke-QuickTestEmail {
    Write-Title 'Quick Test Email'
    Write-Host ''
    Write-Host '  To: Ashini.Thirimavithana@softlogiclife.lk' -ForegroundColor DarkGray
    Write-Host ''

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $sender = Invoke-GraphSendMail `
            -ToEmail 'Ashini.Thirimavithana@softlogiclife.lk' `
            -Subject 'Test Email from PowerShell' `
            -BodyText 'This is a test email sent from my signed-in Microsoft 365 account.'
        Write-Ok "Email sent from $sender"
    }
    catch { Write-Err $_.Exception.Message }
    finally { $ErrorActionPreference = $prevEap }
    Wait-Continue
}

function Resolve-GraphUri {
    param([string]$Uri)

    switch ($Uri) {
        '__CALENDAR_WEEK__' {
            $start = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
            $end   = (Get-Date).AddDays(7).ToString('yyyy-MM-ddTHH:mm:ss')
            return "/me/calendarView?startDateTime=$start&endDateTime=$end&`$select=subject,start,end,location&`$top=20"
        }
        '__CALENDAR_TODAY__' {
            $start = (Get-Date).Date.ToString('yyyy-MM-ddTHH:mm:ss')
            $end   = (Get-Date).Date.AddDays(1).ToString('yyyy-MM-ddTHH:mm:ss')
            return "/me/calendarView?startDateTime=$start&endDateTime=$end&`$select=subject,start,end&`$top=20"
        }
        '__TODO_DEFAULT__' {
            $lists = Invoke-GraphApi -Uri "$script:GraphBaseUrl/me/todo/lists"
            $default = $lists.value | Where-Object { $_.wellknownListName -eq 'defaultList' } | Select-Object -First 1
            if (-not $default) { $default = $lists.value | Select-Object -First 1 }
            if (-not $default) { throw 'No To Do lists found.' }
            return "/me/todo/lists/$($default.id)/tasks?`$top=15&`$select=title,status,importance,dueDateTime"
        }
        default {
            if ($Uri.StartsWith('/')) { return $Uri }
            return "/$Uri"
        }
    }
}

function Invoke-GraphMenuCommand {
    param([string]$Label, [string]$Uri)

    Write-Title $Label
    $resolved = Resolve-GraphUri -Uri $Uri
    $fullUri = "$script:GraphBaseUrl$resolved"
    Write-Info "GET $resolved"
    Write-Host ''

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $result = Invoke-GraphApi -Uri $fullUri
        Format-GraphOutput $result | Write-Host
    }
    catch {
        Write-GraphError $_ -Uri $resolved
    }
    finally { $ErrorActionPreference = $prevEap }

    Wait-Continue
}

# -- Menus --------------------------------------------------------------------

function Show-CategoryMenu {
    param([string]$CategoryKey)

    $cat = $CommandCatalog[$CategoryKey]
    if (-not $cat) { return }

    while ($true) {
        Write-Banner
        $ctx = Get-GraphAccountContext
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
        if ([string]::IsNullOrWhiteSpace($choice)) { continue }

        $selected = $null
        foreach ($cmd in $cat.Commands) {
            if ((Get-ItemProperty $cmd 'Key') -eq $choice) {
                $selected = $cmd
                break
            }
        }

        if (-not $selected) {
            Write-Err 'Invalid choice.'
            Start-Sleep -Seconds 1
            continue
        }

        $action = Get-ItemProperty $selected 'Action'
        $uri    = Get-ItemProperty $selected 'Uri'
        $label  = Get-ItemProperty $selected 'Label'

        if ($action -eq '__SEND_INTERACTIVE__') { Invoke-SendInteractive; continue }
        if ($action -eq '__QUICK_TEST__')       { Invoke-QuickTestEmail; continue }

        if ([string]::IsNullOrWhiteSpace($uri)) {
            Write-Err 'Command is not configured.'
            Start-Sleep -Seconds 1
            continue
        }

        Invoke-GraphMenuCommand -Label $label -Uri $uri
    }
}

function Invoke-FullDiscovery {
    Write-Banner
    Write-Title 'Full Discovery Scan'
    Write-Host ''
    Write-Host '  Running read-only Graph commands across all categories.' -ForegroundColor White
    Write-Host ''

    $confirm = (Read-Host '  Continue? [Y/n]').Trim().ToUpper()
    if ($confirm -eq 'N') { return }

    $i = 0
    $total = $DiscoveryCommands.Count

    foreach ($item in $DiscoveryCommands) {
        $i++
        Write-Host ''
        Write-Host ("  -- [{0}/{1}] {2}" -f $i, $total, $item.Label) -ForegroundColor Magenta
        Write-Host ("  >> GET {0}" -f $item.Uri) -ForegroundColor DarkGray
        Write-Host ''

        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $uri = Resolve-GraphUri -Uri $item.Uri
            $result = Invoke-GraphApi -Uri "$script:GraphBaseUrl$uri"
            Format-GraphOutput $result | Write-Host
        }
        catch {
            Write-Err $_.Exception.Message
        }
        finally { $ErrorActionPreference = $prevEap }
    }

    Write-Host ''
    Write-Ok "Discovery complete ($total sections)."
    Wait-Continue
}

function Invoke-CustomGraphCommand {
    Write-Banner
    Write-Title 'Custom Graph Request'
    Write-Host ''
    Write-Host '  Example: me/messages?$top=5' -ForegroundColor DarkGray
    Write-Host '  Example: me/drive/root/children' -ForegroundColor DarkGray
    Write-Host ''

    $path = (Read-Host '  GET /v1.0').Trim()
    if ([string]::IsNullOrWhiteSpace($path)) { Write-Info 'Cancelled.'; Wait-Continue; return }

    Invoke-GraphMenuCommand -Label 'Custom request' -Uri "/$path"
}

function Show-MainMenu {
    while ($true) {
        Write-Banner
        $ctx = Get-GraphAccountContext
        if ($ctx) { Show-AccountSummary -Context $ctx }

        Write-Title 'Main Menu'
        Write-Host ''
        Write-Host '  CATEGORIES' -ForegroundColor DarkMagenta
        Write-Host ''

        foreach ($key in $CommandCatalog.Keys) {
            Write-Host ("    [{0}]  {1}" -f $key, $CommandCatalog[$key].Title) -ForegroundColor White
        }

        Write-Host ''
        Write-Host '  QUICK ACTIONS' -ForegroundColor DarkMagenta
        Write-Host ''
        Write-Host '    [S]   Send email (interactive)' -ForegroundColor Yellow
        Write-Host '    [T]   Quick test email' -ForegroundColor White
        Write-Host '    [A]   Full discovery scan' -ForegroundColor White
        Write-Host '    [C]   Custom Graph GET request' -ForegroundColor White
        Write-Host '    [R]   Refresh account info' -ForegroundColor White
        Write-Host '    [L]   Re-login to Graph' -ForegroundColor White
        Write-Host '    [Q]   Quit' -ForegroundColor DarkGray
        Write-Host ''

        $choice = (Read-Host '  Select option').Trim().ToUpper()

        switch ($choice) {
            'S' { Invoke-SendInteractive }
            'T' { Invoke-QuickTestEmail }
            'A' { Invoke-FullDiscovery }
            'C' { Invoke-CustomGraphCommand }
            'R' { continue }
            'L' {
                if (-not (Start-GraphLogin -Force)) { Wait-Continue }
            }
            'Q' { return }
            default {
                if ($CommandCatalog.Contains($choice)) {
                    Show-CategoryMenu -CategoryKey $choice
                }
                else {
                    Write-Err 'Invalid choice. Enter 1-7, S, T, A, C, R, L, or Q.'
                    Start-Sleep -Seconds 1
                }
            }
        }
    }
}

# -- Entry point --------------------------------------------------------------

if (-not (Start-GraphLogin)) { exit 1 }

$account = Get-GraphAccountContext
if ($account) {
    Show-AccountSummary -Context $account
    Write-Host '  Loading command center...' -ForegroundColor DarkGray
    Start-Sleep -Milliseconds 800
}

Show-MainMenu

Write-Banner
Write-Ok 'Session ended. Run send.ps1 again to reconnect.'
Write-Host ''
