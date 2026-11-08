# AWS: IAM Identity Center Access Audit

Python script that reports which users and groups are assigned which permission
sets in every active account in an AWS Organization, using IAM Identity Center.

Useful for access reviews: it gives one flat view of who can reach each account,
and with what level of access, without clicking through every account in the console.

## How it works

1. **Finds the Identity Center instance:** retrieves the instance and its Identity
   Store.
2. **Lists all accounts:** pulls every account in the Organization (paginated) and
   skips any that aren't active.
3. **Checks assignments:** for each account and permission set, lists the users and
   groups assigned to it, resolving IDs to readable names.
4. **Exports a report:** writes all assignments to a single CSV.

## Prerequisites

- **AWS CloudShell**. Python 3 and `boto3` are preinstalled, and you're already
  authenticated as your console identity.
- **Run from the management account** of the Organization, or from an account
  that is a delegated administrator for both IAM Identity Center and Organizations.
- **Run in the region where IAM Identity Center is enabled.** CloudShell uses the
  console's current region. If it's wrong, the script won't find the instance.
- **Permissions** (read-only). These AWS managed policies cover everything the
  script calls:
  - `AWSSSOReadOnly`
  - `AWSSSODirectoryReadOnly`
  - `AWSOrganizationsReadOnlyAccess`

## Usage

1. Sign in to the management account and switch to the region where IAM Identity
   Center is enabled.
2. Open **CloudShell** from the console toolbar.
3. Upload the script (**Actions → Upload file**) or clone this repo.
4. Run it:

   ```bash
   python3 audit_identity_center_assignments.py
   ```
5. Download the report via **Actions → Download file**, entering:

   ```
   /home/cloudshell-user/iam_identity_center_all_accounts.csv
   ```

## Output

**`iam_identity_center_all_accounts.csv`:** one row per assignment.

| Account | AccountId | Type | User/Group | PermissionSet |
|---|---|---|---|---|
| Production | 123456789012 | GROUP | Cloud-Admins | AdministratorAccess |
| Production | 123456789012 | USER | jdoe@example.com | ReadOnlyAccess |
| Sandbox | 210987654321 | GROUP | Developers | PowerUserAccess |

## Limitations

- **IAM Identity Center only.** IAM users, roles, and policies created directly
  inside individual accounts aren't included.
- **Groups aren't expanded.** A group assignment shows the group name, not its
  individual members.
- **Permission set names only.** The report shows which permission set is assigned,
  not the policies it contains.
