# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository State

This repo is the **public framework half** of a public/private split: it holds the shared modules, specs, and example host layout, and exports `nixosModules.cluster`. The **private** ops repo (github.com/SEBK4C/NixOS-Ops) composes that module with the real inventory (actual cluster-settings, hardware configs, per-node `extra.nix`, workload stacks, agent issue bridge) — nodes build from the ops repo via the `cluster-rebuild` helper, which injects a read-only GitHub PAT from 1Password per invocation. Never put operational data (logs, IPs, incident details, real settings) in this public repo. `prompt.md` is the methodological specification (Draft v0.1) the code implements — read it before making changes; it defines the architecture, phases, and acceptance criteria.

Layout: `flake.nix` declares `node01`–`node10` (01–03 managers, 04–10 workers) by mapping names to a shared module set. `cluster-settings.nix` is the single user-editable tunables file (SSH keys, Ceph MONs, manager address). `modules/` holds one module per layer — `cluster.nix` (option declarations), `common.nix` (baseline), `onepassword.nix` (Phase 0, defines the `op-cluster` wrapper all other units depend on via the `op-bootstrap` gate service), `tailscale.nix`, `ceph.nix` (no-op until `cluster.ceph.monHosts` is set), `swarm.nix`, `portainer.nix`, `logging.nix` (Vector ships the journal to `cluster.logging.endpoint` — Better Stack today, chosen for ease of setup; the sink is generic HTTP so the backend is swappable; no-op until the endpoint is set). `hosts/nodeXX/hardware-configuration.nix` are `throw` placeholders until each real machine's generated config is committed — so `nix flake check` fails by design until then. `hosts/<node>/extra.nix` is auto-imported when present: it's the per-node escape hatch for host-specific software, written mainly by the Nix-Support-Agent (github.com/SEBK4C/Nix-Support-Agent, spec in its prompt.md) via PRs labeled `node/<hostname>`.

## Architecture (from prompt.md)

The system is a 10-node NixOS cluster layered as:

`NixOS Config -> 1Password Identity -> Tailnet Identity -> Ceph Mount -> Swarm Role -> Portainer Inventory`

- **Nodes 01–03** are Docker Swarm managers (keep the count odd, preserve quorum); **nodes 04–10** are workers. All nodes share one baseline: tailscaled, dockerd, Ceph client, Portainer agent. Hosts differ only by role, labels, and capacity — model by pools and paths, not per-node wiring.
- **Networking** is a private Tailscale mesh (100.64.0.0/10); all admin, Swarm control, and agent traffic flows over the tailnet, with DERP as relay fallback only.
- **Storage** is Ceph (CephFS or RBD) mounted via systemd and consumed by Swarm workloads as persistent volumes.
- **Node onboarding** follows the phased method in §4: bootstrap 1Password identity → declare host → join tailnet → attach Ceph → join Swarm → register Portainer → validate against the acceptance criteria in §8.

## Secrets Model (critical)

**This repo is public and must remain secret-free.** The only bootstrap credential is a scoped 1Password Service Account token (`ops_…` format, delivered via `OP_SERVICE_ACCOUNT_TOKEN` or kernel cmdline, never committed). All downstream secrets — Tailscale auth keys, Ceph keyrings, Swarm join tokens — are fetched at runtime with the 1Password CLI (`op`) using `op://Infrastructure/<item>/<field>` references (e.g. `op://Infrastructure/Tailscale/credential`).

Never commit: raw Tailscale keys, Ceph keyrings or `ceph.conf` credentials, Swarm join tokens, or any 1Password token. Configuration should reference secrets by `op://` URI only.

## Operational Rules

- Manual fixes on hosts must be backported into this configuration repo; the repo is the source of truth, Portainer is for visibility/operations only.
- Avoid spaces in 1Password item names; use default credential fields.
- Every new or rebuilt node must pass the §8 acceptance checks (`nixos-rebuild switch`, `op vault list`/`op read`, tailnet visibility, Ceph mount read/write, `docker node ls` Ready, Portainer agent connected, test workload scheduled) before production scheduling.

## Commands

No flake exists yet, so there are no working build commands. Once the flake is added, the expected workflow is standard NixOS flake usage (`nix build`, `nixos-rebuild switch --flake .#<host>`); update this section when the flake lands.
