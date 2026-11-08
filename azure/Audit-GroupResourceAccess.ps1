#Requires -Modules Az.Accounts, Az.Resources, Az.Monitor

<#
.SYNOPSIS
    Audits which Azure resources members of two Entra ID groups are accessing.
    Scans all subscriptions, 60 days, outputs deduplicated resource access reports.

.NOTES
    Run from CloudShell or run Connect-AzAccount before executing.
#>

# --- INSERT GROUP OBJECT IDs HERE ---
$groupIds = @(
    "ExampleGroup1"
)

# --- Config ---
$daysBack = 60
$startDate = (Get-Date).AddDays(-$daysBack)
$endDate = Get-Date
$outputPath = ".\ResourceAccess_Audit_$(Get-Date -Format 'yyyyMMdd')"

if (!(Test-Path $outputPath)) {
    New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Resource Access Audit - Last $daysBack Days" -ForegroundColor Cyan
Write-Host " $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# --- Step 1: Resolve group members ---
Write-Host "`n[1/3] Resolving group memberships..." -ForegroundColor Yellow

$allMembers = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($groupId in $groupIds) {
    try {
        $group = Get-AzADGroup -ObjectId $groupId
        $members = Get-AzADGroupMember -ObjectId $groupId

        Write-Host "  Group: $($group.DisplayName) - $($members.Count) members" -ForegroundColor Green

        foreach ($member in $members) {
            if ($member.UserPrincipalName) {
                $allMembers.Add([PSCustomObject]@{
                    GroupName   = $group.DisplayName
                    DisplayName = $member.DisplayName
                    UPN         = $member.UserPrincipalName
                })
            }
        }
    } catch {
        Write-Host "  ERROR: Could not resolve group $groupId - $_" -ForegroundColor Red
    }
}

$upnList = $allMembers | Select-Object -ExpandProperty UPN -Unique
Write-Host "Total unique UPNs: $($upnList.Count)"

# --- Step 2: Scan all subscriptions ---
Write-Host "`n[2/3] Scanning subscriptions..." -ForegroundColor Yellow

$subscriptions = Get-AzSubscription -TenantId (Get-AzContext).Tenant.Id | Where-Object { $_.State -eq "Enabled" }
$rawActivity = [System.Collections.Generic.List[PSCustomObject]]::new()
$subCount = 0
$matchedSubs = 0

foreach ($sub in $subscriptions) {
    $subCount++
    Write-Host "  [$subCount/$($subscriptions.Count)] $($sub.Name)..." -ForegroundColor Gray

    try {
        Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null

        $logs = Get-AzActivityLog -StartTime $startDate -EndTime $endDate -MaxRecord 5000 -WarningAction SilentlyContinue | Where-Object {
            $_.Caller -in $upnList -and $_.ResourceId
        }

        if ($logs) {
            $matchedSubs++
            Write-Host "    MATCH: $($logs.Count) records found" -ForegroundColor Green
        }

        foreach ($log in $logs) {
            $matchedMember = $allMembers | Where-Object { $_.UPN -eq $log.Caller } | Select-Object -First 1

            $resourceName = ($log.ResourceId -split '/')[-1]
            $resourceType = ""
            if ($log.ResourceId -match 'providers/([^/]+/[^/]+)') {
                $resourceType = $Matches[1]
            }

            $opType = "Other"
            if ($log.HttpRequest -and $log.HttpRequest.Method) {
                switch ($log.HttpRequest.Method) {
                    "PUT"    { $opType = "Write" }
                    "PATCH"  { $opType = "Write" }
                    "POST"   { $opType = "Action" }
                    "DELETE" { $opType = "Delete" }
                    "GET"    { $opType = "Read" }
                }
            }

            $rawActivity.Add([PSCustomObject]@{
                User             = $log.Caller
                DisplayName      = $matchedMember.DisplayName
                GroupName        = $matchedMember.GroupName
                SubscriptionName = $sub.Name
                ResourceType     = $resourceType
                ResourceName     = $resourceName
                ResourceId       = $log.ResourceId
                OperationType    = $opType
            })
        }
    } catch {
        Write-Host "    WARNING: Could not query $($sub.Name)" -ForegroundColor DarkYellow
    }
}

Write-Host "`nRaw activity records: $($rawActivity.Count)" -ForegroundColor Green
Write-Host "Subscriptions with activity: $matchedSubs" -ForegroundColor Green

# --- Step 3: Summarize and export ---
Write-Host "`n[3/3] Generating reports..." -ForegroundColor Yellow

# Resource Access Summary - deduplicated by user + resource
$summary = $rawActivity | Group-Object -Property User, DisplayName, GroupName, SubscriptionName, ResourceType, ResourceName, ResourceId | ForEach-Object {
    $first = $_.Group[0]
    $opTypes = ($_.Group | Select-Object -ExpandProperty OperationType -Unique | Sort-Object) -join ", "

    [PSCustomObject]@{
        User             = $first.User
        DisplayName      = $first.DisplayName
        GroupName        = $first.GroupName
        SubscriptionName = $first.SubscriptionName
        ResourceType     = $first.ResourceType
        ResourceName     = $first.ResourceName
        ResourceId       = $first.ResourceId
        OperationTypes   = $opTypes
        AccessCount      = $_.Count
    }
}

$summary = $summary | Sort-Object User, AccessCount -Descending
$summaryCSV = Join-Path $outputPath "Resource_Access_Summary.csv"
$summary | Export-Csv -Path $summaryCSV -NoTypeInformation

# Per User Summary - rollup per user
$perUserSummary = $summary | Group-Object User, DisplayName, GroupName | ForEach-Object {
    $first = $_.Group[0]
    [PSCustomObject]@{
        User              = $first.User
        DisplayName       = $first.DisplayName
        GroupName         = $first.GroupName
        UniqueResources   = $_.Count
        TotalAccessCount  = ($_.Group | Measure-Object -Property AccessCount -Sum).Sum
        Subscriptions     = ($_.Group | Select-Object -ExpandProperty SubscriptionName -Unique | Sort-Object) -join ", "
    }
}

$perUserCSV = Join-Path $outputPath "Per_User_Summary.csv"
$perUserSummary | Sort-Object UniqueResources -Descending | Export-Csv -Path $perUserCSV -NoTypeInformation

# --- Summary ---
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host " AUDIT COMPLETE" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Groups scanned:              $($groupIds.Count)"
Write-Host " Total members (UPN):         $($upnList.Count)"
Write-Host " Subscriptions scanned:       $($subscriptions.Count)"
Write-Host " Subscriptions with activity: $matchedSubs"
Write-Host " Raw activity records:        $($rawActivity.Count)"
Write-Host " Unique user-resource pairs:  $($summary.Count)"
Write-Host " Users with activity:         $(($summary | Select-Object User -Unique).Count)"
Write-Host ""
Write-Host " Output: $outputPath" -ForegroundColor Green
Write-Host "   - Resource_Access_Summary.csv (user > resource > access detail)" -ForegroundColor Gray
Write-Host "   - Per_User_Summary.csv        (resources per user overview)" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan