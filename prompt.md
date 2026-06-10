# NixOS Cluster Methodological Specification

Node bootstrap, private networking, storage integration, and workload orchestration

**Status:** Draft v0.1  
**Date:** 2026-06-09  
**Scope:** NixOS nodes, 1Password service account bootstrap, Tailscale mesh, Ceph client storage, Docker Swarm, and Portainer management.  
**Source of truth:** NixOS configuration repository and declared host profiles.

## 1. Purpose

Define a repeatable method for adding and operating NixOS nodes in a private Tailscale-connected Docker Swarm cluster backed by Ceph storage and managed through Portainer.

**Design principle:** Model the system by pools and paths, not by drawing every node-to-service edge. Every node shares the same baseline; only role, labels, and capacity differ.

**Secrets principle:** The NixOS config repo is public and secret-free. A scoped 1Password Service Account token is the only bootstrap credential; all downstream secrets (Tailscale auth keys, Ceph keyrings, Swarm join tokens) are fetched at runtime via the 1Password CLI (`op`).

## 2. System Model

`NixOS Config -> 1Password Identity -> Tailnet Identity -> Ceph Mount -> Swarm Role -> Portainer Inventory`

| Layer | Responsibility | Primary Components |
|---|---|---|
| Configuration | Declare desired host state. | NixOS flake/modules, host profile, bootstrap unit. |
| Secrets | Inject credentials at runtime. | 1Password Service Account token (`ops_…`), `_1password-cli`, `op://` references. |
| Network | Provide private transport. | Tailscale, WireGuard tailnet, 100.64.0.0/10 addresses. |
| Compute | Run the standard node baseline. | tailscaled, dockerd, ceph-client, portainer-agent. |
| Orchestration | Schedule and operate containers. | Docker Swarm managers/workers, Portainer UI. |
| Storage | Provide persistent volumes. | CephFS or RBD, MON/MGR, MDS, OSDs. |

## 3. Node Roles

| Role | Nodes | Function |
|---|---:|---|
| Swarm Managers | 01-03 | Maintain Raft state, expose Swarm API, schedule workloads, preserve manager quorum. |
| Swarm Workers | 04-10 | Execute scheduled containers, mount Ceph-backed storage, report capacity and health. |
| All Nodes | 01-10 | Run NixOS baseline: Tailscale, Docker, Ceph client, and Portainer agent. |

## 4. Method

| Phase | Required Action | Expected Result |
|---|---|---|
| 0. Bootstrap Identity | Deliver a scoped 1Password Service Account token to the host (kernel cmdline or `OP_SERVICE_ACCOUNT_TOKEN`). Bootstrap unit runs `op read` against the Infrastructure vault. | Host authenticates to 1Password non-interactively and resolves downstream secret references. |
| 1. Declare Host | Set hostname, import hardware configuration, assign manager or worker role, enable common services. | A reproducible NixOS generation builds and switches cleanly. |
| 2. Join Tailnet | Fetch the Tailscale auth key from 1Password (`op://Infrastructure/Tailscale/credential`) and join under the approved ACL policy. | Node receives a stable tailnet identity and 100.x.y.z overlay IP. |
| 3. Attach Storage | Fetch Ceph credentials from 1Password, install `ceph.conf` and keyring, then mount CephFS or RBD through systemd. | Persistent storage path is available to the node and containers. |
| 4. Join Swarm | Fetch the correct manager or worker join token from 1Password (or from a manager over tailnet) and join against a manager endpoint. | Node appears as Ready with the correct role and labels. |
| 5. Register Portainer | Allow the global Portainer agent service to start and report. | Portainer sees node CPU, RAM, storage, logs, and task state. |
| 6. Validate | Run network, storage, swarm, and Portainer checks. | Node is accepted for production scheduling. |

## 5. Connectivity Paths

| Path | Flow | Purpose |
|---|---|---|
| Admin | Admin workstation -> Tailscale -> Portainer or Swarm manager | Private management access. |
| Secrets | Bootstrap unit -> 1Password API -> `op read` -> local service config | Runtime credential injection; no secrets in Git. |
| Swarm Control | Manager pool -> worker pool over tailnet | Scheduling, task assignment, and cluster state. |
| Storage | Container -> local mount -> CephFS/RBD -> Ceph cluster | Persistent workload data. |
| DERP Fallback | Node -> Tailscale DERP -> node | Relay only when direct WireGuard connectivity is unavailable. |

## 6. 1Password Service Account Token

The service account token is the cluster's bootstrap identity. It replaces interactive sign-in and must never appear in the Git repository.

| Property | Requirement |
|---|---|
| Token format | Must begin with `ops_` (not `ov_`). Shown once at creation; store immediately in a secure admin vault. |
| Environment variable | `OP_SERVICE_ACCOUNT_TOKEN` — exported by the bootstrap unit or deploy script before any `op` command. |
| Cmdline delivery | Optional kernel parameter, e.g. `op_token=ops_…`, read from `/proc/cmdline` at boot. Treat as short-lived; prefer `--expires-in` of hours, not months. |
| Vault scope | Grant **Read** on the Infrastructure vault only at bootstrap tier. Mint narrower, time-limited tokens per environment (Dev, Staging, Production). |
| Secret references | `op://<vault>/<item>/<field>` — e.g. `op://Infrastructure/Tailscale/credential`, `op://Infrastructure/Ceph/keyring`. Use default credential fields; avoid spaces in item names. |

### 6.1 Infrastructure vault items

| Item | Field | Used in phase |
|---|---|---|
| Tailscale | credential | Phase 2 — tailnet join |
| Ceph | keyring (or credential) | Phase 3 — storage mount |
| Swarm | credential (manager/worker tokens) | Phase 4 — cluster join |
| Environment | notes | Host-specific non-secret config overrides |

### 6.2 Token security rules

- Never commit the token or any secret value to the NixOS config repo.
- Scope each token to the minimum vault set required for that host tier.
- Rotate or revoke immediately when a node is decommissioned or suspected compromised.
- Remember `/proc/cmdline` is world-readable on a booted host; cmdline tokens are bootstrap credentials, not long-term secrets.

## 7. Operational Rules

- Treat the NixOS config repo as the source of truth. Manual fixes must be backported into configuration.
- Keep Swarm manager count odd and preserve quorum before maintenance.
- Never commit raw Tailscale keys, Ceph keyrings, Swarm tokens, or 1Password service account tokens to the repository.
- Use Portainer for visibility and controlled operations, not as the permanent configuration source.
- Every new or rebuilt node must pass the acceptance checks before receiving production workloads.

## 8. Acceptance Criteria

| Check | Pass Condition |
|---|---|
| NixOS | `nixos-rebuild switch` completes and the expected services are enabled. |
| 1Password | `op vault list` succeeds with the service account token; `op read` returns expected Infrastructure items. |
| Tailscale | Node is visible in the tailnet with the expected hostname, IP, and ACL access. |
| Ceph | Mount exists, health is reachable, and test read/write succeeds. |
| Docker Swarm | `docker node ls` shows Ready with correct role and labels. |
| Portainer | Agent is connected and node resources are visible. |
| Workload | A test service can schedule, start, and access its persistent volume. |

## 9. Failure Handling

| Failure | First Checks |
|---|---|
| 1Password auth fails | Token validity and expiry, `OP_SERVICE_ACCOUNT_TOKEN` export, vault grant scope, `op vault list`, system clock (`chrony`). |
| Secret reference not found | Vault name, item name (no spaces), field name matches default credential field, URI syntax. |
| Tailnet join fails | Auth key validity in 1Password item, ACL policy, device approval, local `tailscaled` status. |
| Ceph mount fails | Keyring fetched from 1Password, `ceph.conf`, keyring path and permissions, MON reachability, systemd mount logs. |
| Swarm join fails | Correct token, manager endpoint, tailnet reachability, Docker daemon status. |
| Portainer missing node | Agent service, Docker socket access, manager connectivity, Portainer endpoint status. |

## 10. Minimal Onboarding Checklist

- [ ] 1Password service account created with Infrastructure vault read scope.
- [ ] Infrastructure vault items populated (Tailscale, Ceph, Swarm, Environment).
- [ ] Host profile committed and reviewed (no secrets in repo).
- [ ] NixOS rebuild completed.
- [ ] 1Password bootstrap verified (`op vault list`, `op read` for required items).
- [ ] Tailscale identity active.
- [ ] Ceph mount validated.
- [ ] Swarm role joined and labeled.
- [ ] Portainer agent connected.
- [ ] Test workload scheduled successfully.

