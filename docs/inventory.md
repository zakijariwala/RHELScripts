# Inventory

All servers available to me (sanitised: last IP octet only). Reference
only; scripts do not read this file.

| Env | Web | App | DB |
|---|---|---|---|
| DEV | DW1-2 (.170-171) | DA1-6 (.172-177) | DDB1-2 (.52-53) |
| ST | SW1-2 (.106-107) | SA1-6 (.108-113) | SDB1-2 (.22-23) |
| UAT | UW1-2 (.162-163) | UA1-6 (.164-169) | UDB1-2 (.50-51) |
| PRE-PROD | PW1-4 (.15-18) | PA1-5 (.19-23), PA6-10 (.209-213) | PDB1-2 (.63-64) |
| PROD | PRW1-4 (.117-120) | PRA1-5 (.173-177), PRA6-10 (.21-25) | PRDB1-2 (.74-75) |
| DR | DRW1-4 (.81-84) | DRA1-10 (.70-79) | DRDB1-2 (.55-56) |

| Other | Env | IP | Host |
|---|---|---|---|
| PR Backup Server | PROD | .213 | BKP |
| DR Backup Server | DR | .79B | DRBKP |
| Data Warehouse PR | PROD | .116 | DWH |

Points to check in the source sheet:

- DRBKP IP is `79B`, not a number; `.79` is DRA10.
- Same last octet in two places (fine only if the subnets differ):
  .173-177 DEV/PROD, .21-23 ST/PRE-PROD/PROD, .74-75 PROD/DR,
  .213 PA10/BKP.
- No DR copy of DWH.
