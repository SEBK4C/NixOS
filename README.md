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
