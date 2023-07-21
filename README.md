# KeyVault-Secrets-Rotation-AADApp-PowerShell

Functions regenerate AAD App client secret and add regenerated client secret to Key Vault as new version of the same secret.

## Features

This project framework provides the following features:

* Azure function (AKVAADAppConnector) to manage AAD App client secret. It is triggered by Event Grid 

* ARM template for function deployment 

## Functions

* AKVAADAppConnector - event triggered function, performs AAD App client secret rotation

### Installation

1. Install function with template for AAD App client secret
1. Add permissions using Graph API to Azure Function to generate client secrets in AAD App

ARM templates available:

* [Secrets rotation Azure Function and configuration deployment template](https://github.com/jlichwa/KeyVault-Secrets-Rotation-AADApp-PowerShell/blob/main/ARM-Templates/Readme.md) - it creates and deploys function app and function code, creates necessary permissions, Key Vault event subscription for Near Expiry Event for individual secret (secret name can be provided as parameter)

Steps to add Graph API permissions to Azure Function:

> [!IMPORTANT]
> To provide Graph API Permission you need to be Global Administrator in Azure Active Directory

```powershell
$TenantID = '<Directory Tenant Id>'
Connect-MgGraph -TenantId $TenantID
$functionIdentityObjectId ='<Azure Function Identity Object Id>'
$graphAppId = '00000003-0000-0000-c000-000000000000' # This is a well-known Microsoft Graph application ID.
$graphApiAppRoleName = 'Application.ReadWrite.All'
$graphServicePrincipal =  Get-MgServicePrincipal -Filter "appId eq '$graphAppId'"
$graphApiAppRole = $graphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $graphApiAppRoleName -and $_.AllowedMemberTypes -contains "Application"}

# Assign the role to the managed identity.
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $functionIdentityObjectId -PrincipalId $functionIdentityObjectId -ResourceId $graphServicePrincipal.ObjectId -Id $graphApiAppRole.Id

```
