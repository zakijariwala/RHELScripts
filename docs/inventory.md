# Inventory

All servers available to me. The sheet gives the last IP octet only;
full addresses that are known are listed below. Reference only; scripts
do not read this file.

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

## Known full addresses (PROD)

From the DR drill SOP and runs on app05. The sheet's last octets sit on
more than one subnet.

| Inventory | Full IP | Name in /etc/hosts | Note |
|---|---|---|---|
| PRA1-4 | 10.191.146.173-176 | vps.ra1-4 | front end servers must list these |
| PRA5 | 10.191.146.177 | - | app05 (ens160); also 10.189.72.163 on ens192 |
| PRA6-9 | 10.191.145.21-24 | vps.app1-4 | back end servers must list these |
| PRA10 | 10.191.145.25 (probably) | - | to confirm |

## Infrastructure

| What | PR | DR |
|---|---|---|
| DNS (resolv.conf order on app05) | 10.189.53.150, 10.189.37.136 | 10.176.126.200, 10.176.53.145, 10.176.54.30-32 |
| NTP (chrony source on app05) | 10.191.174.52 | ? |
| DS agent managers (4118 in, 4120/4122 out) | 10.191.146.220, .221 | 10.176.53.122, .123 |
| Default gateway (app05) | 10.191.144.1 | ? |

Site from a server's own address: 10.191.x = PR, 10.176.x = DR.

## Points to check in the source sheet

- DRBKP IP is `79B`, not a number; `.79` is DRA10.
- Same last octet in two environments: only a clash if the subnets are
  the same. PROD app servers alone use two subnets (.146 and .145), so
  most of these are likely fine: .173-177 DEV/PROD, .21-23
  ST/PRE-PROD/PROD, .74-75 PROD/DR, .213 PA10/BKP.
- No DR copy of DWH.
