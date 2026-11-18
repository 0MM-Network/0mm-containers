# Stub: groups as an indirection layer for bot permissions

The full research note is private. This stub only says where it lives and what it covers.

- **Canonical note:** private repo `0mm-mark/ai`: [docs/research/2026-10-31-group-indirection-fact-pack.md](https://github.com/0mm-mark/ai/blob/main/docs/research/2026-10-31-group-indirection-fact-pack.md) (added in 0mm-mark/ai#288).
- **Why private:** it records deployment-specific security details that don't belong in a public repo.
- **Provenance:** compiled 2026-10-31; restored 2026-11-18 after a workspace rollback.

## Generic summary

- **Pattern name.** Granting permissions to role groups and putting accounts in those groups is role-based access control (RBAC); the AD form is AGDLP. The permission checks that enforce it act as the reference monitor (Anderson, 1972).
- **Membership outside config.** The note compares ways to keep role-group membership out of the main configuration (directory services, systemd userdb drop-ins, and others), with trade-offs for each.
- **Gotchas.** New group membership only takes effect in new sessions. Rootless containers drop supplementary groups unless they are explicitly kept. Membership changes need audit and drift detection.
- **Core caveat.** Groups only work as an indirection layer if no role group is equivalent to full admin rights.

Claims in the full note are as checked on 2026-10-31 and are marked UNVERIFIED where unchecked.
