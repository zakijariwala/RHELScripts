# Ansible (scaffold)

This folder holds the skeleton for running checks across many servers
from one control node, and later guarded actions such as rolling reboots.
It is a **scaffold only**: folders, an example inventory, an example
variables file and a base `ansible.cfg`. No playbook or role exists yet.
Precise configuration (control node, inventory, privilege model, vault)
comes later.

| Path | Holds | State |
|---|---|---|
| `ansible.cfg` | base settings for every run from this folder | skeleton |
| `inventory/<tier>-<site>.example.ini` | one inventory per control node, four in all | example only |
| `group_vars/{all,app,web}.yml.example` | the shape of shared and per-tier variables | example only |
| `playbooks/checks/` | read-only playbooks | empty |
| `playbooks/actions/` | guarded, state-changing playbooks | empty |
| `roles/` | shared roles | empty |

Real inventories, real `group_vars` and vault files are gitignored. The
repo ships `*.example` files only.

## Topology

Two tiers, each with its own control node, mirrored on the DR site.

| Site | Tier | Hosts | Control node | Inventory |
|---|---|---|---|---|
| production | app | app1 to app10 | app5 | `inventory/app-prod.example.ini` |
| production | web | web1 to web4 | web1 | `inventory/web-prod.example.ini` |
| DR | app | dr-app1 to dr-app10 | dr-app5 | `inventory/app-dr.example.ini` |
| DR | web | dr-web1 to dr-web4 | dr-web1 | `inventory/web-dr.example.ini` |

Each control node manages its own tier on its own site and runs against
itself with `ansible_connection=local`. The `dr-` names are placeholders
for the DR host names. Groups in every inventory: `<tier>_control`,
`<tier>_managed`, `<tier>` (both) and `site_prod` or `site_dr`.

The database cluster stays outside Ansible: its scripts are typed by hand
on node 1 (`scripts/oracle-rac/`).

## Rules every playbook will follow

**Checks** (`playbooks/checks/`): read-only. Every task carries
`changed_when: false`. Output uses the same status words as the bash
scripts (OK, WARN, CRIT, INFO) and ends with a combined summary. An
unreachable host is CRIT.

**Actions** (`playbooks/actions/`): each one
- refuses to run without `-e confirm=yes`,
- prints what it will do and to which hosts before doing it,
- supports `--check` (dry run),
- runs one host at a time (`serial: 1`) and stops at the first failure,
- runs a pre-check and a post-check,
- has a README section "Before you run this on production" that points to
  [docs/change-requests.md](../docs/change-requests.md).

**All:** full module names (`ansible.builtin.command`), `ansible-lint`
clean, no `shell` or `command` where a module exists, no real identifiers
and no secrets in the repo.

## Open before the first playbook

- Ansible version on app5, web1, dr-app5 and dr-web1, and how it gets
  installed offline.
- RHEL versions of the managed hosts.
- Whether a DR control node may also reach production hosts (today each
  site is self-contained).
- Privilege model: which user Ansible logs in as, sudo rules, whether
  `become` is allowed.
- How playbooks reach the control node, given scripts reach servers only
  by being typed.
- Where vault passwords live.
