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

    # Log shipping endpoint. We chose Better Stack purely for ease of
    # setup: hosted OTel-native logs with alerting, webhooks, and an MCP
    # server agents can query — zero ops today. Shipping goes through
    # Vector, so migrating later (self-hosted Loki, ClickStack, any
    # OTLP backend) is just changing this line. Empty = no shipping.
    # Replace with the ingest URL shown on your Better Stack source.
    logging.endpoint = "";
    # logging.endpoint = "https://in.logs.betterstack.com";   # EDIT ME
  };
}
