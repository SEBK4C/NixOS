# NixOS Swarm Cluster

Point a NixOS machine at this flake and it sets itself up automatically:

1. Authenticates to **1Password** with a service account token (the only secret you ever place on a node).
2. Joins the **Tailscale** mesh.
3. Mounts **CephFS** storage (optional, skipped until configured).
4. Initializes or joins the **Docker Swarm** (nodes 01–03 managers, 04–10 workers).
5. Is managed through **Portainer**.

This repo is **public and secret-free**. Every secret is fetched at runtime from 1Password via `op://Infrastructure/...` references. Never commit a key, keyring, or token. The full design is in [prompt.md](prompt.md).

## Setup Steps

### 1. Create the 1Password service account and vault items

1. In 1Password, create a vault named **Infrastructure**.
2. Create a **service account** ([1password.com → Developer → Service Accounts](https://developer.1password.com/docs/service-accounts/)) with **Read** access to the Infrastructure vault. The token starts with `ops_` — it is shown once, save it somewhere safe.
3. Add these items to the Infrastructure vault (no spaces in item names):

| Item | Field | Value |
|---|---|---|
| `Tailscale` | `credential` | A reusable Tailscale auth key (Admin console → Settings → Keys) |
| `Ceph` | `credential` | The CephFS client secret key (base64 string, not the full keyring) |
| `Swarm` | `manager-token` | Filled in at step 6, after the first manager is up |
| `Swarm` | `worker-token` | Filled in at step 6, after the first manager is up |
| `BetterStack` | `credential` | Source token for log shipping (optional — see [Logging](#logging)) |

### 2. Fork this repo and set your cluster settings

Edit [`cluster-settings.nix`](cluster-settings.nix) — it's the only file you need to touch:

- `adminSSHKeys` — your SSH public key, so you can log in as root.
- `ceph.monHosts` — your Ceph monitor addresses, or leave empty to skip Ceph for now.

Commit and push.

### 3. Install NixOS and capture the hardware config

Install minimal NixOS on the node as usual. Then on the node:

```sh
nixos-generate-config --show-hardware-config > hardware-configuration.nix
```

Copy that file into this repo at `hosts/node01/hardware-configuration.nix` (matching the node's name), commit, push. Repeat per node — this is the only per-node file.

### 4. Place the 1Password token on the node

This is the single manual secret per node (never committed):

```sh
mkdir -p /etc/op
echo 'ops_YOUR_TOKEN_HERE' > /etc/op/token
chmod 600 /etc/op/token
```

(Alternatively, pass `op_token=ops_...` on the kernel command line for one-shot provisioning — see prompt.md §6.)

### 5. Build the node

On the node, as root:

```sh
export NIX_CONFIG="experimental-features = nix-command flakes"
nixos-rebuild switch --flake github:YOUR_GITHUB_USER/NixOS#node01
```

Use the matching host name (`#node02`, `#node03`, …) on each node. On boot/switch the node validates 1Password, joins the tailnet, mounts Ceph, and joins the swarm — automatically.

### 6. First manager only: store the swarm join tokens

`node01` runs `docker swarm init` on first boot and prints the join tokens:

```sh
journalctl -u swarm-join         # shows both tokens
```

Copy the `SWMTKN-...` values into the 1Password `Swarm` item (`manager-token` and `worker-token` fields). Every later node joins on its own.

### 7. Bring up the remaining nodes

Repeat steps 3–5 for `node02` … `node10`. Managers (01–03) and workers (04–10) pick the right token and role automatically.

### 8. Deploy Portainer

On any manager (e.g. node01):

```sh
cluster-deploy-portainer
```

Then from your admin workstation (on the tailnet) open `https://node01:9443` and create the admin account. All nodes report in via the global agent service.

### 9. Validate

On each new node, before giving it production workloads:

```sh
op-cluster vault list                          # 1Password bootstrap OK
tailscale status                               # on the tailnet
mountpoint /mnt/cephfs                         # storage mounted (if configured)
docker node ls                                 # (managers) node Ready, right role
```

In Portainer, confirm the node shows CPU/RAM/tasks. Full acceptance criteria: prompt.md §8.

## Logging

**Why Better Stack:** ease of setup — hosted OpenTelemetry-native logs with built-in alerting, webhooks, and an MCP server that AI agents can query directly, for zero ops today.

Every node runs [Vector](https://vector.dev) shipping the full systemd journal (Docker containers log to the journal too, so Swarm workloads are included) to the endpoint in `cluster-settings.nix`. Shipping happens over the public internet to Better Stack's ingest — node-to-node traffic stays on the tailnet as before.

To enable:

1. In Better Stack, create a **Source** (platform: Vector / HTTP). Copy its token and ingest URL.
2. Store the token in 1Password: vault `Infrastructure`, item `BetterStack`, field `credential`.
3. Set `logging.endpoint` in `cluster-settings.nix` to the ingest URL, commit, rebuild nodes.

For the agent/triggering loop: point alerts (including anomaly detection) at a **webhook** to wake your automation, and connect agents to the [Better Stack MCP server](https://betterstack.com/docs/getting-started/integrations/mcp/) to query logs with SQL, check incidents, and acknowledge them.

**Migration path if we outgrow them:** Vector is the vendor-neutral layer, so the nodes never need re-plumbing. To move to self-hosted [Loki](https://grafana.com/oss/loki/) or [ClickStack](https://clickhouse.com/clickstack) (the open-source equivalent of Better Stack's architecture) — or any other platform Vector/OTLP can speak to:

1. Stand up the new backend on the tailnet (or anywhere).
2. Change `logging.endpoint` (and, if the backend isn't HTTP-bearer, the sink type in `modules/logging.nix` — e.g. `type = "loki"`).
3. Swap the 1Password `BetterStack` credential for the new backend's token, rebuild.

What migrates: the entire log pipeline. What doesn't: dashboards, alert rules, and retained history — recreate alerts on the new backend and let history age out of Better Stack.

## How it fits together

```
/etc/op/token  ──▶  op-bootstrap  ──▶  tailscale-join  ──▶  swarm-join
 (only manual          │                                        │
  secret)              └──▶  ceph-secret ──▶  cephfs mount      └──▶  Portainer
```

- `op-cluster` is a wrapper around the 1Password CLI that loads the token and resolves `op://` references; every systemd unit uses it.
- All swarm/Portainer traffic flows over the tailnet (`tailscale0` is a trusted firewall interface; everything else is closed except SSH).
- Roles and node names are declared once in [`flake.nix`](flake.nix); shared behavior lives in [`modules/`](modules/); tunables live in [`cluster-settings.nix`](cluster-settings.nix).

## Troubleshooting

| Symptom | Look at |
|---|---|
| 1Password auth fails | `journalctl -u op-bootstrap` — token validity/expiry, vault scope, clock (`chronyc tracking`) |
| Tailnet join fails | `journalctl -u tailscale-join` — auth key validity, ACLs, device approval |
| Ceph mount fails | `journalctl -u mnt-cephfs.mount` — MON reachability, `/etc/ceph/secret` |
| Swarm join fails | `journalctl -u swarm-join` — token fields in 1Password, manager reachable over tailnet |
| Node missing in Portainer | agent service running (`docker service ps portainer_agent`), Docker socket access |
