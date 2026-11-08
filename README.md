# Cloud IAM Audit Scripts

Scripts for reviewing who has access to what across Azure and AWS. Built for
access reviews and least-privilege cleanup, where the native consoles make it
slow to see the full picture.

| Cloud | Script | What it answers |
|---|---|---|
| [Azure](./azure) | PowerShell | Which resources have members of a given Entra ID group actually been working with? |
| [AWS](./aws) | Python | Which users and groups have which permission sets in each account? |

The Azure script looks at **actual activity**
(what people did), while the AWS script looks at **assigned access** (what people
are allowed to do).

Both are read-only and are designed to run in each cloud's built-in shell (Azure
Cloud Shell and AWS CloudShell), so there's nothing to install locally. See each
folder's README for permissions, setup, and sample output.

## Disclaimer

Only run these scripts in environments you're authorized to audit.
