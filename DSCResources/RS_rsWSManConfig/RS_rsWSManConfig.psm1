function Get-TargetResource
{
    param (
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Name,
        [Parameter(Mandatory)][String]$CertThumbprint,
        [Parameter(Mandatory)][String]$Username,
        [Parameter(Mandatory)][String]$Ensure
    )
    @{
    }
}

function Set-TargetResource
{
    param (
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Name,
        [Parameter(Mandatory)][String]$CertThumbprint,
        [Parameter(Mandatory)][String]$Username,
        [Parameter(Mandatory)][String]$Ensure
    )
    $cert = (Get-ChildItem Cert:\LocalMachine\My\ | ? Thumbprint -eq $CertThumbprint)
    if (!$cert)
    {
        Throw "No Cert Exists with the given Certificate Thumbprint"
    }
    if ( $cert.EnhancedKeyUsageList.FriendlyName -notcontains "Server Authentication" -and $cert.EnhancedKeyUsageList.FriendlyName -notcontains "Client Authentication")
    {
        Throw "Incorrect Cert: Needs Certificate with Server and Client Authntication"
    }
    $Listeners = (Get-ChildItem WSMan:\localhost\Listener | ? Keys -eq "Transport=HTTPS").Name
    foreach ( $listener in $Listeners )
    {
        if( (Get-ChildItem WSMan:\localhost\Listener\$listener | ? Name -eq "CertificateThumbprint").value -eq $cert.Thumbprint)
        {
            $currentListener = $listener
        }
    }
    if( $Ensure -eq "Present" )
    {
        # Create a WinRM Listener for HTTPS bound to a SSL Cert
        if ( !$currentListener )
        {
            New-WSManInstance -ResourceURI winrm/config/Listener -SelectorSet @{Address="*";Transport="https"} -ValueSet @{Hostname=$($cert.Subject.Replace('CN=',''));CertificateThumbprint=$cert.Thumbprint}
        }
        # Set WinRM Certificate Auth to $True
        Set-Item WSMan:\localhost\Service\Auth\Certificate -Value "true"
        # Creating a Certificate Admin user to bind to SSL Certificate
        $randompassword = ([char[]]([char]'!'..[char]'z') + 0..9 | sort {get-random})[0..13] -join ''
        if( (gwmi Win32_UserAccount -Filter "LocalAccount='$True'").Name -notcontains $Username )
        {
            net user $Username /add $randompassword
            net localgroup administrators $Username /add
        }
        else
        {
            $LocalAccount = Get-WmiObject -class "Win32_UserAccount" -namespace "root\CIMV2" -filter "LocalAccount = True" | ? Name -eq $Username
            $user = [adsi]"WinNT://$env:COMPUTERNAME/$($LocalAccount.Name),user"
            $passexpiry = (Get-Date).AddSeconds($user.MaxPasswordAge.Value - $user.PasswordAge.Value)
            if( $passexpiry.AddHours(-12) -le (Get-Date) )
            {
                net user $Username /delete
                net user $Username /add $randompassword
                (Get-ChildItem WSMan:\localhost\ClientCertificate | ? Keys -match $cert.Thumbprint) | Remove-Item -Recurse -force
            }
        }
        $password = ConvertTo-SecureString $randompassword -AsPlainText –Force
        $adminuser = New-Object System.Management.Automation.PSCredential $Username,$password
        if( (Get-ChildItem WSMan:\localhost\ClientCertificate | ? Keys -match $cert.Thumbprint).Name.count -eq 0 )
        {
            New-Item -Path WSMan:\localhost\ClientCertificate -URI * -Subject $($cert.Subject.Replace('CN=','')) -Issuer $cert.Thumbprint -Credential $adminuser -force
        }
    }
    else # if $Ensure -eq 'Absent'
    {
        if( $currentListener )
        {
            Remove-Item WSMan:\localhost\Listener\$currentListener -Force -Recurse
        }
        if( (Get-ChildItem WSMan:\localhost\ClientCertificate | ? Keys -match $cert.Thumbprint).Name.count -gt 0 )
        {
            (Get-ChildItem WSMan:\localhost\ClientCertificate | ? Keys -match $cert.Thumbprint) | Remove-Item -Recurse -Force
        }
        if( (gwmi Win32_UserAccount -Filter "LocalAccount='$True'").Name -contains $Username )
        {
            net user $Username /delete
        }
    }
}

function Test-TargetResource
{
    param (
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Name,
        [Parameter(Mandatory)][String]$CertThumbprint,
        [Parameter(Mandatory)][String]$Username,
        [Parameter(Mandatory)][String]$Ensure
    )
    $testresult = $true
    $cert = (Get-ChildItem Cert:\LocalMachine\My\ | ? Thumbprint -eq $CertThumbprint)
    if (!$cert)
    {
        Throw "No Cert Exists with the given Certificate Thumbprint"
    }
    if ( $cert.EnhancedKeyUsageList.FriendlyName -notcontains "Server Authentication" -and $cert.EnhancedKeyUsageList.FriendlyName -notcontains "Client Authentication")
    {
        Throw "Incorrect Cert: Needs Certificate with Server and Client Authntication"
    }
    $Listeners = (Get-ChildItem WSMan:\localhost\Listener | ? Keys -eq "Transport=HTTPS").Name
    foreach ( $listener in $Listeners )
    {
        if( (Get-ChildItem WSMan:\localhost\Listener\$listener | ? Name -eq "CertificateThumbprint").value -eq $cert.Thumbprint)
        {
            $currentListener = $listener
        }
    }
    if( $Ensure -eq "Present" )
    {
        if ( !$currentListener )
        {
            $testresult = $false
        }
        if( (gwmi Win32_UserAccount -Filter "LocalAccount='$True'").Name -notcontains $Username )
        {
            $testresult = $false
        }
        else
        {
            $LocalAccount = Get-WmiObject -class "Win32_UserAccount" -namespace "root\CIMV2" -filter "LocalAccount = True" | ? Name -eq $Username
            $user = [adsi]"WinNT://$env:COMPUTERNAME/$($LocalAccount.Name),user"
            $passexpiry = (Get-Date).AddSeconds($user.MaxPasswordAge.Value - $user.PasswordAge.Value)
            if( $passexpiry.AddHours(-12) -le (Get-Date) )
            {
                $testresult = $false
            }
        }
        if( (Get-ChildItem WSMan:\localhost\ClientCertificate | ? Keys -match $cert.Thumbprint).Name.count -eq 0 )
        {
            $testresult = $false
        }
    }
    else # if $Ensure -eq 'Absent'
    {
        if( $currentListener ){ $testresult = $false }
        if( (Get-ChildItem WSMan:\localhost\ClientCertificate | ? Keys -match $cert.Thumbprint).Name.count -gt 0 ) { $testresult = $false }
        if( (gwmi Win32_UserAccount -Filter "LocalAccount='$True'").Name -contains $Username ){ $testresult = $false }
    }
    return $testresult
}
Export-ModuleMember -Function *-TargetResource