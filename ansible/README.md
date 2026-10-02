# Ansible (on hold)

Ansible work (checks across many servers from one control node, guarded
actions such as rolling reboots) is on hold. Scripts reach servers only by
being typed by hand, and no approved path exists to move files onto a
control node. See [AMENDMENT 01](../docs/decisions/AMENDMENT-01.md), D5.

If a transfer path is ever approved, this folder will first get reference
documentation only, no playbooks, under the same safety rules as the bash
scripts ([CLAUDE.md](../CLAUDE.md)).
