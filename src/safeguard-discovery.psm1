# Helper
function Test-SafeguardSession
{
    [CmdletBinding()]
    param (
    )

    if (-not $PSBoundParameters.ContainsKey("ErrorAction")) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.ContainsKey("Verbose")) { $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference") }

    if (-not (Get-Module safeguard-ps)) { Import-Module safeguard-ps }
    if (Get-Module safeguard-ps)
    {
        if ($SafeguardSession)
        {
            $true
        }
        else
        {
            Write-Verbose "safeguard-ps is installed, but it is not connected to Safeguard"
            $false
        }
    }
    else
    {
        Write-Verbose "safeguard-ps is not installed"
        $false
    }
}


function Get-SgDiscConnectionCredential
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [string]$NetworkAddress,
        [Parameter(Mandatory=$false)]
        [string]$AccountName
    )

    if (-not $PSBoundParameters.ContainsKey("ErrorAction")) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.ContainsKey("Verbose")) { $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference") }

    $local:Credential = $null
    if (Test-SafeguardSession)
    {
        if ($AccountName)
        {
            $local:Requests = (Get-SafeguardMyRequest | Where-Object {
                ($_.AssetNetworkAddress -eq $NetworkAddress -or $_.AssetName -eq $NetworkAddress) -and $_.AccountName -eq $AccountName })
        }
        else
        {
            $local:Requests = (Get-SafeguardMyRequest | Where-Object {
                $_.AssetNetworkAddress -eq $NetworkAddress -or $_.AssetName -eq $NetworkAddress })
        }
        if ($local:Requests.Count -lt 1)
        {
            Write-Verbose "Unable to find an open access request with name or network address equal to '$NetworkAddress'"
            if ($AccountName) { Write-Verbose "Where account name also equals '$AccountName" }
        }
        elseif ($local:Requests.Count -gt 1)
        {
            Write-Verbose "Found $($local:Requests.Count) open access requests with name or network address equal to '$NetworkAddress'"
            if ($AccountName) { Write-Verbose "Where account name also equals '$AccountName" }
        }
        else
        {
            if ($local:Requests[0].State -ne "RequestAvailable" -and $local:Requests[0].State -ne "PasswordCheckedOut")
            {
                Write-Verbose "Access request state is '$($local:Requests[0].State)', not 'RequestAvailable' or 'PasswordCheckedOut'"
            }
            else
            {
                $local:Credential = (New-Object PSCredential -ArgumentList $local:Requests[0].AccountName,(ConvertTo-SecureString -AsPlainText -Force `
                                        (Get-SafeguardAccessRequestPassword $local:Requests[0].Id)))
            }
        }
    }
    else
    {
        Write-Verbose "No safeguard-ps connection, cannot use it for credentials"
    }

    if (-not $local:Credential)
    {
        Write-Host "Credentials for ${NetworkAddress}"
        if (-not $AccountName)
        {
            $AccountName = (Read-Host "AccountName")
        }
        $local:Password = (Read-Host "Password" -AsSecureString)
        $local:Credential = (New-Object PSCredential -ArgumentList $AccountName,$local:Password)
    }

    $local:Credential
}

function Import-SgDiscDiscoveredAccount
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [string]$NetworkAddress,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [PSObject[]]$DiscoveredAccounts
    )

    begin {
        if (-not $PSBoundParameters.ContainsKey("ErrorAction")) { $ErrorActionPreference = "Stop" }
        if (-not $PSBoundParameters.ContainsKey("Verbose")) { $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference") }

        if (Test-SafeguardSession)
        {
            $local:Assets = @(Get-SafeguardAsset $NetworkAddress -Fields AssetPartitionName,Id,Name,NetworkAddress)
            if ($local:Assets.Count -lt 1)
            {
                throw "Unable to find an asset matching '$NetworkAddress'"
            }
            elseif ($local:Assets.Count -gt 1)
            {
                throw "Found $($local:Assets.Count) assets matching '$NetworkAddress"
            }
        }
        else
        {
            throw "You must connect to Safeguard using safeguard-ps to use this cmdlet, run Connect-Safeguard"
        }
    }
    process {
        $DiscoveredAccounts | ForEach-Object {
            if (-not $_.AccountName)
            {
                Write-Host -ForegroundColor Yellow ($_ | Out-String)
                throw "Discovered account has no AccountName field"
            }
            try
            {
                Write-Verbose "Checking for existence of '$($_.AccountName)' on '$NetworkAddress'"
                $local:Account = (Get-SafeguardAssetAccount $NetworkAddress $_.AccountName)
            }
            catch {}
            if ($local:Account)
            {
                Write-Host -ForegroundColor Green "Discovered account '$($_.AccountName)' already exists"
            }
            else
            {
                if ($_.DomainName)
                {
                    $local:Account = (New-SafeguardAssetAccount $local:Assets[0].Id -NewAccountName $_.AccountName -DomainName $_.DomainName `
                                        -Description "Account discovered by safeguard-discovery PowerShell module")
                }
                elseif ($_.DistinguishedName)
                {
                    $local:Account = (New-SafeguardAssetAccount $local:Assets[0].Id -NewAccountName $_.AccountName -DistinguishedName $_.DistinguishedName `
                                        -Description "Account discovered by safeguard-discovery PowerShell module")
                }
                else
                {
                    $local:Account = (New-SafeguardAssetAccount $local:Assets[0].Id -NewAccountName $_.AccountName `
                                        -Description "Account discovered by safeguard-discovery PowerShell module")
                }
                New-Object PSObject -Property ([ordered]@{
                    AssetId = $local:Account.AssetId;
                    AssetName = $local:Account.AssetName;
                    Id = $local:Account.Id
                    Name = $local:Account.Name;
                    DomainName = $local:Account.DomainName;
                    DistinguishedName = $local:Account.DistinguishedName;
                    PlatformDisplayName = $local:Account.PlatformDisplayName;
                })
            }
            $local:Account = $null
        }
    }
    end {}
}