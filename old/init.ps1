az login --allow-no-subscriptions --use-device-code

if ($LASTEXITCODE -eq 0) {
    Write-Host "Login successful"
    
    az account show
}
else {
    Write-Host "Login failed or timed out"
}