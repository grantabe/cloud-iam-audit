# Azure: Group Resource Access Audit

PowerShell script that reports which Azure resources the members of one or more
Entra ID groups have been working with, across every enabled subscription in the
tenant, over a configurable lookback window.

Useful for access reviews and least-privilege cleanup: it shows whether a group's
members actually use the access they've been granted, and where.

## How it works

1. **Resolves group members:** looks up each group by Object ID and collects members
   that have a UPN.
2. **Scans subscriptions:** queries the Azure Activity Log in every enabled
   subscription and keeps entries where the caller is one of those members.
3. **Generates reports:** deduplicates activity by user and resource, classifies
   operations by HTTP method (Write, Action, Delete, Read), and exports two CSVs.

## Prerequisites

- **Azure Cloud Shell (PowerShell)**. The required Az modules (`Az.Accounts`,
  `Az.Resources`, `Az.Monitor`) are preinstalled, and you're already authenticated.
- **Permissions:**
  - **Reader** (or any role that can read the Activity Log) on each subscription
    you want included. Subscriptions you can't read are skipped with a warning.
  - Permission to read groups and group members in Entra ID. Most tenants allow
    this by default; otherwise, the **Directory Readers** role is sufficient.

## Usage

1. Open [Azure Cloud Shell](https://shell.azure.com) and select **PowerShell**.
2. Upload the script (**Manage files → Upload**) or clone this repo.
3. Open the script and add your group Object IDs:

   ```powershell
   code ./Audit-GroupResourceAccess.ps1
   ```

   ```powershell
   $groupIds = @(
       "00000000-0000-0000-0000-000000000000",
       "11111111-1111-1111-1111-111111111111"
   )
   ```

   Find a group's Object ID in the Entra admin center under **Groups → Overview**,
   or run `Get-AzADGroup -DisplayName "Group Name"`.
4. Optionally, change the lookback window (default 60 days, maximum 90):

   ```powershell
   $daysBack = 60
   ```
5. Run it:

   ```powershell
   ./Audit-GroupResourceAccess.ps1
   ```
6. Download the reports from the output folder via **Manage files → Download**.

## Output

Reports are saved to `./ResourceAccess_Audit_YYYYMMDD/`.

**`Resource_Access_Summary.csv`:** one row per user and resource.

| User | GroupName | SubscriptionName | ResourceType | ResourceName | OperationTypes | AccessCount |
|---|---|---|---|---|---|---|
| jdoe@contoso.com | Cloud-Engineers | Prod-Sub | Microsoft.Compute/virtualMachines | vm-web-01 | Action, Write | 14 |
| asmith@contoso.com | Cloud-Engineers | Dev-Sub | Microsoft.Storage/storageAccounts | stdevlogs | Write | 3 |

**`Per_User_Summary.csv`:** one row per user.

| User | GroupName | UniqueResources | TotalAccessCount | Subscriptions |
|---|---|---|---|---|
| jdoe@contoso.com | Cloud-Engineers | 12 | 87 | Dev-Sub, Prod-Sub |
| asmith@contoso.com | Cloud-Engineers | 2 | 5 | Dev-Sub |

Users with no recorded activity don't appear in either report. Compare against the
group membership to find members who may no longer need the access.

## Limitations

- **Management-plane activity only.** The Activity Log records control-plane
  operations, like creating, modifying, or deleting resources. Data-plane activity,
  like reading blobs, querying databases, or signing in to VMs, isn't captured.
  Read operations rarely appear for the same reason.
- **90-day maximum.** The Activity Log retains 90 days of history, so a larger
  `$daysBack` returns nothing extra.
- **5,000 records per subscription.** Very busy subscriptions may be truncated.
- **Direct members only.** Nested groups aren't expanded, and members without a UPN,
  such as service principals, are excluded.
- **Current membership.** Groups are resolved as they are today, so activity from
  someone who has since left the group isn't attributed to it.

