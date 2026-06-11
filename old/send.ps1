# D:\ps\send.ps1
# Safe: sends email from YOUR signed-in account only

$ToEmail = "Ashini.Thirimavithana@softlogiclife.lk"
$Subject = "Test Email from PowerShell"
$BodyText = "This is a test email sent from my signed-in Microsoft 365 account."

Write-Host "Step 1: Azure CLI device-code login..." -ForegroundColor Cyan
az login --allow-no-subscriptions --use-device-code

if ($LASTEXITCODE -ne 0) {
    Write-Host "Azure login failed or cancelled." -ForegroundColor Red
    exit
}

Write-Host "Step 2: Installing required Graph modules..." -ForegroundColor Cyan

if (-not (Get-Module -ListAvailable Microsoft.Graph.Authentication)) {
    Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
}

Import-Module Microsoft.Graph.Authentication -Force

Write-Host "Step 3: Connecting to Microsoft Graph..." -ForegroundColor Cyan

Connect-MgGraph -Scopes "User.Read","Mail.Send" -NoWelcome

$ctx = Get-MgContext
Write-Host "Logged in as: $($ctx.Account)" -ForegroundColor Green

Write-Host "Step 4: Sending email..." -ForegroundColor Cyan

$mailBody = @{
    message = @{
        subject = $Subject
        body = @{
            contentType = "Text"
            content = $BodyText
        }
        toRecipients = @(
            @{
                emailAddress = @{
                    address = $ToEmail
                }
            }
        )
    }
    saveToSentItems = $true
} | ConvertTo-Json -Depth 10

try {
    Invoke-MgGraphRequest `
        -Method POST `
        -Uri "https://graph.microsoft.com/v1.0/me/sendMail" `
        -Body $mailBody `
        -ContentType "application/json"

    Write-Host "SUCCESS: Email sent from $($ctx.Account)" -ForegroundColor Green
}
catch {
    Write-Host "FAILED: Email not sent." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Disconnect-MgGraph