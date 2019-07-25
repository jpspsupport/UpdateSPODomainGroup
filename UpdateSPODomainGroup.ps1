param(
    [Parameter(Mandatory=$true)]
    $adminurl,
    [Parameter(Mandatory=$true)]
    $GroupName,
    $Force = $false
)

##the first two lines of the script load the CSOM model:
$loadInfo1 = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client")
$loadInfo2 = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client.Runtime")

$cred = Get-Credential
$loadInfo3 = Connect-AzureAD -Credential $cred
$azureadgroup = Get-AzureADGroup -SearchString $GroupName | where DisplayName -eq $GroupName
if ($azureadgroup -eq $null)
{
    Write-Host "Invalid Group Specified."
    exit;
}
function ExecuteQueryWithIncrementalRetry {
    param (
        [parameter(Mandatory = $true)]
        [int]$retryCount
    );

    $DefaultRetryAfterInMs = 120000;
    $RetryAfterHeaderName = "Retry-After";
    $retryAttempts = 0;

    if ($retryCount -le 0) {
        throw "Provide a retry count greater than zero."
    }

    while ($retryAttempts -lt $retryCount) {
        try {
            $script:context.ExecuteQuery();
            return;
        }
        catch [System.Net.WebException] {
            $response = $_.Exception.Response

            if (($null -ne $response) -and (($response.StatusCode -eq 429) -or ($response.StatusCode -eq 503))) {
                $retryAfterHeader = $response.GetResponseHeader($RetryAfterHeaderName);
                $retryAfterInMs = $DefaultRetryAfterInMs;

                if (-not [string]::IsNullOrEmpty($retryAfterHeader)) {
                    if (-not [int]::TryParse($retryAfterHeader, [ref]$retryAfterInMs)) {
                        $retryAfterInMs = $DefaultRetryAfterInMs;
                    }
                    else {
                        $retryAfterInMs *= 1000;
                    }
                }

                Write-Output ("CSOM request exceeded usage limits. Sleeping for {0} seconds before retrying." -F ($retryAfterInMs / 1000))
                #Add delay.
                Start-Sleep -m $retryAfterInMs
                #Add to retry count.
                $retryAttempts++;
            }
            else {
                throw;
            }
        }
    }

    throw "Maximum retry attempts {0}, have been attempted." -F $retryCount;
}

Connect-SPOService -Url $adminurl -Credential $cred
$siteurls = Get-SPOSite | select Url

foreach ($siteurl in $siteurls)
{
    if ($Force)
    {
        try
        {
            $PrevIsAdmin = (Get-SPOUser -Site $siteurl.Url -LoginName $cred.username).IsSiteAdmin
        }
        catch
        {
            $PrevIsAdmin = ($_.Exception.GetType().Name -ne "ServerUnauthorizedAccessException")
        }

        if (!$PrevIsAdmin)
        {
            $tmpuser = Set-SPOUser -Site $siteurl.Url -LoginName $cred.username -IsSiteCollectionAdmin $true
        }
    }

    try
    {
        try
        {
            $script:context = New-Object Microsoft.SharePoint.Client.ClientContext($siteurl.Url)
            $spocred = New-Object Microsoft.SharePoint.Client.SharePointOnlineCredentials($cred.UserName, $cred.Password)
            $script:context.Credentials = $spocred

            $script:context.add_ExecutingWebRequest({
                param ($source, $eventArgs);
                $request = $eventArgs.WebRequestExecutor.WebRequest;
                $request.UserAgent = "NONISV|Contoso|Application/1.0";
            })


            $siteuser = $script:context.web.SiteUsers.GetByLoginName(("c:0t.c|tenant|" + $azureadgroup.ObjectId))
            if ($siteuser -ne $null)
            {
                $siteuser.Title = $azureadgroup.DisplayName
                if ($azureadgroup.MailEnabled)
                {
                    $siteuser.Email = $azureadgroup.Mail
                }
                $siteuser.Update()
                ExecuteQueryWithIncrementalRetry -retryCount 5
                Write-Output ($siteurl.Url + ",Updated")
            }
        }
        catch [System.Net.WebException]
        {
            Write-Output ($siteurl.Url + ",Error," + $_)
        }
        catch [System.Exception]
        {
            #Write-Output ($siteurl.Url + ",Error," + $_)
        }
    }
    finally
    {
        if ($Force -and (!$PrevIsAdmin))
        {
            $tmpuser = Set-SPOUser -Site $siteurl.Url -LoginName $cred.username -IsSiteCollectionAdmin $false
        }
    }
}
