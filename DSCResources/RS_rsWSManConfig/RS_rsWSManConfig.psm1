function Get-TargetResource
{
    param (
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Name,
        [Parameter(Mandatory)][String]$CertThumbprint,
        [Parameter(Mandatory)][String]$Username,
        [Parameter(Mandatory)][String]$Ensure
    )
    @{
        Name = $Name
        CertThumbprint = $CertThumbprint
        Username = $Username
        Ensure = $Ensure
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
        Throw "Incorrect Cert: Needs Certificate with Server and Client Authentication"
    }
    $Listeners = (Get-ChildItem WSMan:\localhost\Listener | ? Keys -eq "Transport=HTTPS").Name
    foreach ( $listener in $Listeners )
    {
        if( (Get-ChildItem WSMan:\localhost\Listener\$listener | ? Name -eq "CertificateThumbprint").value -eq $cert.Thumbprint)
        {
            $currentListener = $listener
        }
    }
    if( !$currentListener -and ($Listeners.count -gt 0) )
    {
        $Listeners | % { Remove-Item WSMan:\localhost\Listener\$_ -Force -Recurse }
    }
    $clientCertificates = (Get-ChildItem WSMan:\localhost\ClientCertificate).Name
    foreach ( $clientCertificate in $clientCertificates )
    {
        if ( ((Get-ChildItem WSMan:\localhost\ClientCertificate\$clientCertificate).Value -contains $Username) -and ((Get-ChildItem WSMan:\localhost\ClientCertificate\$clientCertificate).Value -contains $CertThumbprint) ) 
        {
            $currentcert = $clientCertificate
        }
    }
    if( $Ensure -eq "Present" )
    {
        # Create a WinRM Listener for HTTPS bound to a SSL Cert
        if ( !$currentListener )
        {
            try{
                New-WSManInstance -ResourceURI winrm/config/Listener -SelectorSet @{Address="*";Transport="https"} -ValueSet @{Hostname=$($cert.Subject.Replace('CN=',''));CertificateThumbprint=$cert.Thumbprint}
            }
            catch
            {
                Throw $_.Exception.Message
            }
        }
        # Set WinRM Certificate Auth to $True
        Set-Item WSMan:\localhost\Service\Auth\Certificate -Value "true"
        # Creating a Certificate Admin user to bind to SSL Certificate
        $randompassword = ([char[]]([char]'!'..[char]'z') + 0..9 | sort {get-random})[0..13] -join ''
        $newuser = $false
        if( (gwmi Win32_UserAccount -Filter "LocalAccount='$True'").Name -notcontains $Username )
        {
            net user $Username /add $randompassword
            net localgroup administrators $Username /add
            $newuser = $true
        }
        else
        {
            #$LocalAccount = Get-WmiObject -class "Win32_UserAccount" -namespace "root\CIMV2" -filter "LocalAccount = True" | ? Name -eq $Username
            #$user = [adsi]"WinNT://$env:COMPUTERNAME/$($LocalAccount.Name),user"
            #$passexpiry = (Get-Date).AddSeconds($user.MaxPasswordAge.Value - $user.PasswordAge.Value)
            #if( $passexpiry -gt (Get-Date).AddDays(-12) )
            #{
                Write-Verbose "Delete"
                net user $Username /delete
                net user $Username /add $randompassword
                (Get-ChildItem WSMan:\localhost\ClientCertificate | ? Keys -match $cert.Thumbprint) | Remove-Item -Recurse -force
                $newuser = $true
            #}
        }
        #if ( $newuser )
        #{
            $password = ConvertTo-SecureString $randompassword -AsPlainText –Force
            $adminuser = New-Object System.Management.Automation.PSCredential $Username,$password
        #}
        if( !$currentcert )
        {
            try {
                New-Item -Path WSMan:\localhost\ClientCertificate -URI * -Subject $($cert.Subject.Replace('CN=','')) -Issuer $cert.Thumbprint -Credential $adminuser -force
            }
            catch
            {
                Throw $_.Exception.Message
            }
        }
    }
    else # if $Ensure -eq 'Absent'
    {
        if( $currentListener )
        {
            Remove-Item WSMan:\localhost\Listener\$currentListener -Force -Recurse
        }
        if( $currentcert )
        {
            Remove-Item WSMan:\localhost\ClientCertificate\$currentcert -Force -Recurse
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
    if( !$currentListener -and ($Listeners.count -gt 0) )
    {
        $testresult = $false
    }
    $clientCertificates = (Get-ChildItem WSMan:\localhost\ClientCertificate).Name
    foreach ( $clientCertificate in $clientCertificates )
    {
        if ( ((Get-ChildItem WSMan:\localhost\ClientCertificate\$clientCertificate).Value -contains $Username) -and ((Get-ChildItem WSMan:\localhost\ClientCertificate\$clientCertificate).Value -contains $CertThumbprint) ) 
        {
            $currentcert = $clientCertificate
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
            if( $passexpiry -gt (Get-Date).AddDays(-12) )
            {
                $testresult = $false
            }
        }
        if( !$currentcert )
        {
            $testresult = $false
        }
    }
    else # if $Ensure -eq 'Absent'
    {
        if( $currentListener ){ $testresult = $false }
        if( $currentcert ) { $testresult = $false }
        if( (gwmi Win32_UserAccount -Filter "LocalAccount='$True'").Name -contains $Username ){ $testresult = $false }
    }
    return $testresult
}
Export-ModuleMember -Function *-TargetResource