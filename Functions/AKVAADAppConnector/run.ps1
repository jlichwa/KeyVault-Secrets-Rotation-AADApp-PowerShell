param($eventGridEvent, $TriggerMetadata)

function GetCredential($credentialId, $providerAddress,$vaultName, $validityPeriodDays){
    if(-Not($providerAddress)){
       throw "Provider Address is missing"
    }

    Write-Host "Retrieving new client secret for App: $providerAddress"
    
    #Retrieve credential
    $endDate =(Get-Date).AddDays([int]$validityPeriodDays)
    $passwordCredentials = @{
        StartDateTime = Get-Date
        EndDateTime = $endDate
        DisplayName = "Managed by Key Vault $vaultName"
    }
    $clientSecret = New-AzADAppCredential  -PasswordCredentials $passwordCredentials -ObjectId $providerAddress
    
    return $clientSecret
}

function RegenerateCredential($credentialId, $providerAddress, $vaultName, $validityPeriodDays){
    Write-Host "Regenerating client secret for App Id: $providerAddress"
    
    $endDate =(Get-Date).AddDays([int]$validityPeriodDays)
    $passwordCredentials = @{
        StartDateTime = Get-Date
        EndDateTime = $endDate
        DisplayName = "Managed by Key Vault $vaultName"
    }
    $clientSecret = New-AzADAppCredential  -PasswordCredentials $passwordCredentials -ObjectId $providerAddress
    
    return $clientSecret
}

function ImportSecret($keyVaultName,$secretName,$secretVersion){
    #Retrieve Secret
    $token = (Get-AzAccessToken -ResourceUrl "https://vault.azure.net").Token
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }

    $currentSecret = (Invoke-WebRequest -Uri "https://$keyVaultName.vault.azure.net/secrets/${secretName}?api-version=7.6-preview.1" -Headers $headers -Method GET).Content | ConvertFrom-Json
    $currentSecretVersion = $currentSecret.id.Split("/")[-1]

    Write-Host "Secret Retrieved"
    
    If($currentSecretVersion -ne $secretVersion){
        #if current version is different than one retrived in event
        Write-Host "The secret version is already imported"
        return 
    }

    #Retrieve Secret Info
    $validityPeriodDays = $currentSecret.rotationPolicy.validityPeriod
    $credentialId =  $currentSecret.providerConfig.ActiveCredentialId
    $providerAddress = $currentSecret.providerConfig.providerAddress
    
    Write-Host "Secret Info Retrieved"
    Write-Host "Validity Period: $validityPeriodDays"
    Write-Host "Credential Id: $credentialId"
    Write-Host "Provider Address: $providerAddress"

    #Get credential in provider
    $newCredentialValue = (GetCredential $credentialId $providerAddress $vaultName $validityPeriodDays)
    Write-Host "Credential retrieved. Credential Id: $($newCredentialValue.KeyId) Resource Id: $providerAddress"

    #Add new credential to Key Vault
    $setSecretBody = @{
        id = $currentSecret.id
        value = $newCredentialValue.SecretText
        providerConfig = @{
            activeCredentialId = $newCredentialValue.KeyId
        }
    } | ConvertTo-Json -Depth 10

    Invoke-WebRequest -Uri "https://$keyVaultName.vault.azure.net/secrets/${secretName}/pending?api-version=7.6-preview.1" -Headers $headers -Body $setSecretBody -Method PUT

    Write-Host "New credential added to Key Vault. Secret Name: $secretName"
}


function RoatateSecret($keyVaultName,$secretName,$secretVersion){
    #Retrieve Secret
    $token = (Get-AzAccessToken -ResourceUrl "https://vault.azure.net").Token
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }

    $currentSecret = (Invoke-WebRequest -Uri "https://$keyVaultName.vault.azure.net/secrets/${secretName}?api-version=7.6-preview.1" -Headers $headers -Method GET).Content | ConvertFrom-Json
    $currentSecretVersion = $currentSecret.id.Split("/")[-1]
    Write-Host "Secret Retrieved"
    
    If($currentSecretVersion -ne $secretVersion){
        #if current version is different than one retrived in event
        Write-Host "Secret version is already rotated"
        return 
    }

    #Retrieve Secret Info
    $validityPeriodDays = $currentSecret.rotationPolicy.validityPeriod
    $credentialId =  $currentSecret.providerConfig.ActiveCredentialId
    $providerAddress = $currentSecret.providerConfig.providerAddress
    
    Write-Host "Secret Info Retrieved"
    Write-Host "Validity Period: $validityPeriodDays"
    Write-Host "Credential Id: $credentialId"
    Write-Host "Provider Address: $providerAddress"

    #Regenerate Credential
    $newCredentialValue = (RegenerateCredential "" $providerAddress $keyVAultName $validityPeriodDays)
    Write-Host "Credential regenerated. Credential Id: $($newCredentialValue.KeyId) Resource Id: $providerAddress"

    #Add new credential to Key Vault
    $setSecretBody = @{
        id = $currentSecret.id
        value = $newCredentialValue.SecretText
        providerConfig = @{
            activeCredentialId = $newCredentialValue.KeyId
        }
    } | ConvertTo-Json -Depth 10

    Invoke-WebRequest -Uri "https://$keyVaultName.vault.azure.net/secrets/${secretName}/pending?api-version=7.6-preview.1" -Headers $headers -Body $setSecretBody -Method PUT

    Write-Host "New credential added to Key Vault. Secret Name: $secretName"
}
$ErrorActionPreference = "Stop"
# Make sure to pass hashtables to Out-String so they're logged correctly
if(-not($eventGridEvent.eventType -eq "Microsoft.KeyVault.SecretImportPending" -or $eventGridEvent.eventType -eq "Microsoft.KeyVault.SecretRotationPending" ))
{
    throw "Invalid event grid event. Microsoft.KeyVault.SecretImportPending or Microsoft.KeyVault.SecretRotationPending is required."
}

$secretName = $eventGridEvent.subject
$secretVersion = $eventGridEvent.data.Version
$keyVaultName = $eventGridEvent.data.VaultName

Write-Host "Key Vault Name: $keyVAultName"
Write-Host "Secret Name: $secretName"
Write-Host "Secret Version: $secretVersion"


If($eventGridEvent.eventType -eq "Microsoft.KeyVault.SecretImportPending")
{
    #Import secret
    Write-Host "Import started."
    ImportSecret $keyVAultName $secretName $secretVersion
    Write-Host "Secret Imported Successfully"
}
elseif($eventGridEvent.eventType -eq "Microsoft.KeyVault.SecretRotationPending")
{
    #Rotate secret
    Write-Host "Rotation started."
    RoatateSecret $keyVAultName $secretName $secretVersion
    Write-Host "Secret Rotated Successfully"
}