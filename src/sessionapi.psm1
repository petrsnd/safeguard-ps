# Helpers
function Connect-Sps
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [string]$SessionMaster,
        [Parameter(Mandatory=$true,Position=1)]
        [string]$SessionUsername,
        [Parameter(Mandatory=$true,Position=2)]
        [SecureString]$SessionPassword,
        [Parameter(Mandatory=$false)]
        [switch]$Insecure
    )

    if (-not $PSBoundParameters.ContainsKey("ErrorAction")) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.ContainsKey("Verbose")) { $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference") }

    Import-Module -Name "$PSScriptRoot\sslhandling.psm1" -Scope Local
    Edit-SslVersionSupport
    if ($Insecure)
    {
        Disable-SslVerification
        if ($global:PSDefaultParameterValues) { $PSDefaultParameterValues = $global:PSDefaultParameterValues.Clone() }
    }

    $local:PasswordPlainText = [System.Net.NetworkCredential]::new("", $SessionPassword).Password

    $local:BasicAuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $SessionUsername, $local:PasswordPlainText)))
    Remove-Variable -Scope local PasswordPlainText

    Invoke-RestMethod -Uri "https://$SessionMaster/api/authentication" -SessionVariable HttpSession `
        -Headers @{ Authorization = ("Basic {0}" -f $local:BasicAuthInfo) } | Write-Verbose
    Remove-Variable -Scope local BasicAuthInfo

    $HttpSession
}
function New-SpsUrl
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [string]$RelativeUrl,
        [Parameter(Mandatory=$false)]
        [object]$Parameters
    )

    if (-not $PSBoundParameters.ContainsKey("ErrorAction")) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.ContainsKey("Verbose")) { $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference") }

    $local:Url = "https://$($SafeguardSpsSession.Appliance)/api/$RelativeUrl"
    if ($Parameters -and $Parameters.Length -gt 0)
    {
        $local:Url += "?"
        $Parameters.Keys | ForEach-Object {
            $local:Url += ($_ + "=" + [uri]::EscapeDataString($Parameters.Item($_)) + "&")
        }
        $local:Url = $local:Url -replace ".$"
    }
    $local:Url
}
function Invoke-SpsWithBody
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [string]$Method,
        [Parameter(Mandatory=$true,Position=1)]
        [string]$RelativeUrl,
        [Parameter(Mandatory=$true,Position=2)]
        [object]$Headers,
        [Parameter(Mandatory=$false)]
        [object]$Body,
        [Parameter(Mandatory=$false)]
        [object]$JsonBody,
        [Parameter(Mandatory=$false)]
        [object]$Parameters
    )

    if (-not $PSBoundParameters.ContainsKey("ErrorAction")) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.ContainsKey("Verbose")) { $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference") }

    $local:BodyInternal = $JsonBody
    if ($Body)
    {
        $local:BodyInternal = (ConvertTo-Json -Depth 100 -InputObject $Body)
    }
    $local:Url = (New-SpsUrl $RelativeUrl -Parameters $Parameters)
    Write-Verbose "Url=$($local:Url)"
    Write-Verbose "Parameters=$(ConvertTo-Json -InputObject $Parameters)"
    Write-Verbose "---Request Body---"
    Write-Verbose "$($local:BodyInternal)"
    Invoke-RestMethod -WebSession $SafeguardSpsSession.Session -Method $Method -Headers $Headers -Uri $local:Url `
                      -Body ([System.Text.Encoding]::UTF8.GetBytes($local:BodyInternal)) `
}
function Invoke-SpsWithoutBody
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [string]$Method,
        [Parameter(Mandatory=$true,Position=1)]
        [string]$RelativeUrl,
        [Parameter(Mandatory=$true,Position=2)]
        [object]$Headers,
        [Parameter(Mandatory=$false)]
        [object]$Parameters
    )

    if (-not $PSBoundParameters.ContainsKey("ErrorAction")) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.ContainsKey("Verbose")) { $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference") }

    $local:Url = (New-SpsUrl $RelativeUrl -Parameters $Parameters)
    Write-Verbose "Url=$($local:Url)"
    Write-Verbose "Parameters=$(ConvertTo-Json -InputObject $Parameters)"
    Invoke-RestMethod -WebSession $SafeguardSpsSession.Session -Method $Method -Headers $Headers -Uri $local:Url
}
function Invoke-SpsInternal
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [string]$Method,
        [Parameter(Mandatory=$true,Position=1)]
        [string]$RelativeUrl,
        [Parameter(Mandatory=$true,Position=2)]
        [object]$Headers,
        [Parameter(Mandatory=$false)]
        [object]$Body,
        [Parameter(Mandatory=$false)]
        [string]$JsonBody,
        [Parameter(Mandatory=$false)]
        [HashTable]$Parameters
    )

    if (-not $PSBoundParameters.ContainsKey("ErrorAction")) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.ContainsKey("Verbose")) { $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference") }

    try
    {
        switch ($Method.ToLower())
        {
            {$_ -in "get","delete"} {
                Invoke-SpsWithoutBody $Method $RelativeUrl $Headers -Parameters $Parameters
                break
            }
            {$_ -in "put","post"} {
                Invoke-SpsWithBody $Method $RelativeUrl $Headers `
                    -Body $Body -JsonBody $JsonBody -Parameters $Parameters
                break
            }
        }
    }
    catch
    {
        Write-Host -ForegroundColor Yellow "TODO: Interpret SPS API errors"
        throw
    }
}



function Connect-SafeguardSps
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [string]$Appliance,
        [Parameter(Mandatory=$true,Position=1)]
        [string]$Username,
        [Parameter(Mandatory=$false)]
        [SecureString]$Password,
        [Parameter(Mandatory=$false)]
        [switch]$Insecure
    )

    if (-not $PSBoundParameters.ContainsKey("ErrorAction")) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.ContainsKey("Verbose")) { $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference") }

    if (-not $Password)
    {
        $Password = (Read-Host "Password" -AsSecureString)
    }

    $local:HttpSession = (Connect-Sps -SessionMaster $Appliance -SessionUsername $Username -SessionPassword $Password -Insecure:$Insecure)
    Set-Variable -Name "SafeguardSpsSession" -Scope Global -Value @{
        "Appliance" = $Appliance;
        "Insecure" = $Insecure;
        "Session" = $local:HttpSession
    }
    Write-Host "Login Successful."
}

function Disconnect-SafeguardSps
{
    [CmdletBinding()]
    Param(
    )

    if (-not $PSBoundParameters.ContainsKey("ErrorAction")) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.ContainsKey("Verbose")) { $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference") }

    if (-not $SafeguardSpsSession)
    {
        Write-Host "Not logged in."
    }
    else
    {
        Write-Host "Session variable removed."
        Set-Variable -Name "SafeguardSpsSession" -Scope Global -Value $null
    }
}

function Invoke-SafeguardSpsMethod
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [string]$Method,
        [Parameter(Mandatory=$true,Position=1)]
        [string]$RelativeUrl,
        [Parameter(Mandatory=$false)]
        [string]$Accept = "application/json",
        [Parameter(Mandatory=$false)]
        [string]$ContentType = "application/json",
        [Parameter(Mandatory=$false)]
        [object]$Body,
        [Parameter(Mandatory=$false)]
        [string]$JsonBody,
        [Parameter(Mandatory=$false)]
        [HashTable]$Parameters,
        [Parameter(Mandatory=$false)]
        [HashTable]$ExtraHeaders,
        [Parameter(Mandatory=$false)]
        [switch]$JsonOutput
    )

    if (-not $PSBoundParameters.ContainsKey("ErrorAction")) { $ErrorActionPreference = "Stop" }
    if (-not $PSBoundParameters.ContainsKey("Verbose")) { $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference") }

    if (-not $SafeguardSpsSession)
    {
        throw "This cmdlet requires that you log in with the Connect-SafeguardSps cmdlet"
    }

    $local:Insecure = $SafeguardSpsSession.Insecure
    Write-Verbose "Insecure=$($local:Insecure)"
    Import-Module -Name "$PSScriptRoot\sslhandling.psm1" -Scope Local
    Edit-SslVersionSupport
    if ($local:Insecure)
    {
        Disable-SslVerification
        if ($global:PSDefaultParameterValues) { $PSDefaultParameterValues = $global:PSDefaultParameterValues.Clone() }
    }

    $local:Headers = @{
        "Accept" = $Accept;
        "Content-type" = $ContentType;
    }

    foreach ($key in $ExtraHeaders.Keys)
    {
        $local:Headers[$key] = $ExtraHeaders[$key]
    }

    Write-Verbose "---Request---"
    Write-Verbose "Headers=$(ConvertTo-Json -InputObject $local:Headers)"

    try
    {
        if ($JsonOutput)
        {
            (Invoke-SpsInternal $Method $RelativeUrl $local:Headers `
                                -Body $Body -JsonBody $JsonBody -Parameters $Parameters) | ConvertTo-Json -Depth 100
        }
        else
        {
            Invoke-SpsInternal $Method $RelativeUrl $local:Headers -Body $Body -JsonBody $JsonBody -Parameters $Parameters
        }
    }
    finally
    {
        if ($local:Insecure)
        {
            Enable-SslVerification
            if ($global:PSDefaultParameterValues) { $PSDefaultParameterValues = $global:PSDefaultParameterValues.Clone() }
        }
    }
}
