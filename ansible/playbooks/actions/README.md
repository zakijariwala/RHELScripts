# Action playbooks (guarded)

Empty. Each playbook added here changes state and must follow every guard
in [ansible/README.md](../../README.md): `-e confirm=yes`, `--check`
support, `serial: 1`, pre-check and post-check, and a README section
"Before you run this on production".
