# Cluster-wide settings. This is the ONLY file you should need to edit
# before deploying. Never put secret values here — this repo is public.
{
  cluster = {
    # SSH public keys that may log in as root on every node.
    adminSSHKeys = [
      # "ssh-ed25519 AAAA... you@workstation"   # EDIT ME
    ];

    # Ceph monitor addresses (host:port). Leave empty to skip Ceph entirely
    # until your Ceph cluster exists — everything else still works.
    ceph.monHosts = [
      # "100.64.0.20:6789"   # EDIT ME (tailnet IPs of your Ceph MONs)
    ];

    # Tailnet name of the first Swarm manager. With MagicDNS enabled
    # (the Tailscale default) the plain hostname resolves on every node.
    swarm.managerAddress = "node01";
  };
}
