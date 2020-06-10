# Helpers
function Resolve-SafeguardTagId
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$false)]
        [string]$Appliance,
        [Parameter(Mandatory=$false)]
        [object]$AccessToken,
        [Parameter(Mandatory=$false)]
        [switch]$Insecure,
        [Parameter(Mandatory=$false)]
        [object]$AssetPartition = $null,
        [Parameter(Mandatory=$false)]
        [int]$AssetPartitionId = $null,
        [Parameter(Mandatory=$true,Position=0)]
        [object]$Tag
    )

    if (-not $PSBoundParameters.ContainsKey("ErrorAction")) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.ContainsKey("Verbose")) { $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference") }

    if ($Tag.Id -as [int])
    {
        $Tag = $Tag.Id
    }

    Import-Module -Name "$PSScriptRoot\assetpartitions.psm1" -Scope Local
    $AssetPartitionId = (Resolve-AssetPartitionIdFromSafeguardSession -Appliance $Appliance -AccessToken $AccessToken -Insecure:$Insecure `
                             -AssetPartition $AssetPartition -AssetPartitionId $AssetPartitionId)
    if ($AssetPartitionId)
    {
        $local:RelPath = "AssetPartitions/$AssetPartitionId/Tags"
        $local:ErrMsgSuffix = " in asset partition (Id=$AssetPartitionId)"
    }
    else
    {
        $local:RelPath = "AssetPartitions/Tags"
        $local:ErrMsgSuffix = ""
    }

    if (-not ($Tag -as [int]))
    {
        try
        {
            $local:Tags = (Invoke-SafeguardMethod -AccessToken $AccessToken -Appliance $Appliance -Insecure:$Insecure Core GET "$($local:RelPath)" `
                                -Parameters @{ filter = "Name ieq '$Tag'"; fields = "Id" })
        }
        catch
        {
            Write-Verbose $_
            Write-Verbose "Caught exception with ieq filter, trying with q parameter"
            $local:Tags = (Invoke-SafeguardMethod -AccessToken $AccessToken -Appliance $Appliance -Insecure:$Insecure Core GET "$($local:RelPath)" `
                                -Parameters @{ q = $Tag; fields = "Id" })
        }
        if (-not $local:Tags)
        {
            throw "Unable to find tag matching '$Tag'$($local:ErrMsgSuffix)"
        }
        if ($local:Tags.Count -ne 1)
        {
            throw "Found $($local:Tags.Count) tags matching '$Tag'$($local:ErrMsgSuffix)"
        }
        $local:Tags[0].Id
    }
    else
    {
        if ($AssetPartitionId)
        {
            # Make sure it actually exists
            $local:Tags = (Invoke-SafeguardMethod -AccessToken $AccessToken -Appliance $Appliance -Insecure:$Insecure Core GET "$($local:RelPath)" `
                                -Parameters @{ filter = "Id eq $Tag and AssetPartitionId eq $AssetPartitionId"; fields = "Id" })
            if (-not $local:Tags)
            {
                throw "Unable to find asset matching '$Tag'$($local:ErrMsgSuffix)"
            }
        }
        $Tag
    }
}



#- New-SafeguardTag
#- Edit-SafeguardTag
#- Remove-SafeguardTag
#- Get-SafeguardAssetByTag
#- Get-SafeguardAssetAccountByTag

function Get-SafeguardTag
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$false)]
        [string]$Appliance,
        [Parameter(Mandatory=$false)]
        [object]$AccessToken,
        [Parameter(Mandatory=$false)]
        [switch]$Insecure,
        [Parameter(Mandatory=$false)]
        [object]$AssetPartition,
        [Parameter(Mandatory=$false)]
        [int]$AssetPartitionId = $null,
        [Parameter(Mandatory=$false,Position=0)]
        [object]$TagToGet
    )

    if (-not $PSBoundParameters.ContainsKey("ErrorAction")) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.ContainsKey("Verbose")) { $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference") }

    Import-Module -Name "$PSScriptRoot\assetpartitions.psm1" -Scope Local
    $AssetPartitionId = (Resolve-AssetPartitionIdFromSafeguardSession -Appliance $Appliance -AccessToken $AccessToken -Insecure:$Insecure `
                            -AssetPartition $AssetPartition -AssetPartitionId $AssetPartitionId)
    if ($AssetPartitionId)
    {
        $local:RelPath = "AssetPartitions/$AssetPartitionId/Tags"
    }
    else
    {
        $local:RelPath = "AssetPartitions/Tags"
    }

    if ($PSBoundParameters.ContainsKey("TagToGet"))
    {
        $local:TagId = (Resolve-SafeguardTagId -AccessToken $AccessToken -Appliance $Appliance -Insecure:$Insecure `
                           -AssetPartitionId $AssetPartitionId $TagToGet)
        $local:Tags = (Invoke-SafeguardMethod -AccessToken $AccessToken -Appliance $Appliance -Insecure:$Insecure Core `
                           GET "AssetPartitions/Tags/$($local:TagId)")
    }
    else
    {
        $local:Tags = (Invoke-SafeguardMethod -AccessToken $AccessToken -Appliance $Appliance -Insecure:$Insecure Core `
                           GET "$($local:RelPath)")
    }

    Import-Module -Name "$PSScriptRoot\grouptag-utilities.psm1" -Scope Local
    foreach ($local:Tag in $local:Tags)
    {
        $local:Hash = [ordered]@{
            Id = $local:Tag.Id;
            AssetPartitionId = $local:Tag.AssetPartitionId;
            AssetPartition = $local:Tag.AssetPartitionName;
            Name = $local:Tag.Name;
            Description = $local:Tag.Description;
            AssetTaggingRule = $null;
            AssetAccountTaggingRule = $null;
        }
        if ($local:Tag.AssetTaggingRule) {
            $local:Hash.AssetTaggingRule = (Convert-RuleToString $local:Tag.AssetTaggingRule "asset") }
        if ($local:Tag.AssetAccountTaggingRule) {
            $local:Hash.AssetAccountTaggingRule = (Convert-RuleToString $local:Tag.AssetAccountTaggingRule "account"); }
        New-Object PSObject -Property $local:Hash
    }
}

