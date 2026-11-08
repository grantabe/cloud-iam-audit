"""
Audits IAM Identity Center access across every active account in an AWS Organization.
Outputs a CSV of which users and groups hold which permission sets in each account.

Run in AWS CloudShell from the management account (or a delegated admin account),
in the region where IAM Identity Center is enabled. Read-only.

"""

import boto3
import csv
from botocore.exceptions import ClientError

# sso-admin: Identity Center config (permission sets, assignments)
# identitystore: the users and groups themselves
# organizations: the list of accounts

sso_client = boto3.client('sso-admin')
identitystore = boto3.client('identitystore')
orgs_client = boto3.client('organizations')

# An organization normally has one Identity Center instance, so we use the first.
print("Getting IAM Identity Center instance...")
instances = sso_client.list_instances()
instance_arn = instances['Instances'][0]['InstanceArn']
identity_store_id = instances['Instances'][0]['IdentityStoreId']

print(f"Instance ARN: {instance_arn}")
print(f"Identity Store ID: {identity_store_id}\n")

# Assignments only return opaque IDs. These helpers resolve them to readable names,
# falling back to the raw ID if a lookup fails so one bad entry doesn't stop the run.
def get_user_name(user_id):
    try:
        response = identitystore.describe_user(
            IdentityStoreId=identity_store_id,
            UserId=user_id
        )
        return response.get('UserName', user_id)
    except ClientError:
        return user_id

def get_group_name(group_id):
    try:
        response = identitystore.describe_group(
            IdentityStoreId=identity_store_id,
            GroupId=group_id
        )
        return response.get('DisplayName', group_id)
    except ClientError:
        return group_id

def get_permission_set_name(permission_set_arn):
    try:
        response = sso_client.describe_permission_set(
            InstanceArn=instance_arn,
            PermissionSetArn=permission_set_arn
        )
        return response['PermissionSet']['Name']
    except ClientError:
        return permission_set_arn

# Get ALL accounts using pagination
print("Fetching all accounts (with pagination)...")
accounts = []
# list_accounts returns results in pages, so the paginator collects every page.
paginator = orgs_client.get_paginator('list_accounts')
for page in paginator.paginate():
    accounts.extend(page['Accounts'])

print(f"Found {len(accounts)} total accounts\n")

# Get all permission sets using pagination
print("Fetching permission sets...")
ps_paginator = sso_client.get_paginator('list_permission_sets')
permission_sets = []
for page in ps_paginator.paginate(InstanceArn=instance_arn):
    permission_sets.extend(page['PermissionSets'])
print(f"Found {len(permission_sets)} permission sets\n")

# Process all accounts
report = []
total_assignments = 0
accounts_processed = 0

for account in accounts:
    account_id = account['Id']
    account_name = account['Name']
    account_status = account['Status']
    
    # Skip suspended accounts
    if account_status != 'ACTIVE':
        print(f"⊘ Skipping {account_name} ({account_id}) - Status: {account_status}")
        continue
    
    accounts_processed += 1
    print(f"[{accounts_processed}/{len(accounts)}] Processing: {account_name} ({account_id})")
    
    account_assignments = 0
    
    # For each permission set, check assignments in this account
    for ps_arn in permission_sets:
        try:
            paginator = sso_client.get_paginator('list_account_assignments')
            for page in paginator.paginate(
                InstanceArn=instance_arn,
                AccountId=account_id,
                PermissionSetArn=ps_arn
            ):
                for assignment in page.get('AccountAssignments', []):
                    principal_type = assignment['PrincipalType']
                    principal_id = assignment['PrincipalId']
                    
                    if principal_type == 'USER':
                        principal_name = get_user_name(principal_id)
                    else:
                        principal_name = get_group_name(principal_id)
                    
                    permission_set_name = get_permission_set_name(ps_arn)
                    
                    report.append({
                        'Account': account_name,
                        'AccountId': account_id,
                        'Type': principal_type,
                        'User/Group': principal_name,
                        'PermissionSet': permission_set_name
                    })
                    account_assignments += 1
                    total_assignments += 1
        except ClientError as e:
            print(f"  ⚠ Error processing permission set: {e}")
            continue
    
    print(f"  → Found {account_assignments} assignments\n")

print(f"{'='*70}")
print(f"Summary:")
print(f"  Total accounts found: {len(accounts)}")
print(f"  Active accounts processed: {accounts_processed}")
print(f"  Total assignments found: {total_assignments}")
print(f"{'='*70}\n")

# Write to CSV
output_file = 'iam_identity_center_all_accounts.csv'
with open(output_file, 'w', newline='') as f:
    fieldnames = ['Account', 'AccountId', 'Type', 'User/Group', 'PermissionSet']
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(report)

print(f"✓ Report saved to {output_file}")
print(f"\nTo download:")
print(f"1. Click 'Actions' → 'Download file'")
print(f"2. Enter path: /home/cloudshell-user/{output_file}")