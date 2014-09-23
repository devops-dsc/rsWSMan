rsWSMan
=====
This module is created to create a WSMan tunnel using SSL Certificate based authentication.<br>
In order to get this work you must have a work SSL Certificate with EKU (Enhanced Key Usage) <br>
of Server Authentication and Client Authentication. <br>

Example:
```PoSh
Start -wait $("C:", "makecert.exe" -join '\') -ArgumentList "-r -pe -n ""CN=WSMAN"" -ss my C:\WSMAN.crt -sr localmachine -a sha1 -len 2048 -eku 1.3.6.1.5.5.7.3.1,1.3.6.1.5.5.7.3.2"
```

Once configured you must have the Public/Private Key Pair on both the Client and Server nodes in Cert:\LocalMachine\My.<br>
You should also have the Public Key on the Server node in Cert:\LocalMachine\Root\.
<br>
To Configure node with DSC after SSL Cert is in correct Stores.

```PoSh
rsWSManConfig WSMan
{
  Name = "WSMan"
  CertThumbprint = $((Get-ChildItem Cert:\LocalMachine\My | ? {$_.Subject -eq 'CN=WSMan'}).Thumbprint)
  Ensure = "Present"
  Username = "WSManCertAdmin"
}
```

From a Client node you should be able to connect using:
```PoSh
$thumb = (Get-ChildItem Cert:\LocalMachine\My | ? Subject -eq "CN=WSMAN").Thumbprint
Enter-PSSession -ConnectionUri https://SERVERIP:5986 -CertificateThumbprint $thumb -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)
```