# Option declarations shared by every module. Values are set in
# cluster-settings.nix (cluster-wide) and flake.nix (per host).
{ lib, ... }:

{
  options.cluster = {
    role = lib.mkOption {
      type = lib.types.enum [ "manager" "worker" ];
      description = "Docker Swarm role of this node.";
    };

    firstManager = lib.mkOption {
      type = lib.types.str;
      default = "node01";
      description = "Hostname of the node that runs `docker swarm init`.";
    };

    vault = lib.mkOption {
      type = lib.types.str;
      default = "Infrastructure";
      description = "1Password vault holding all cluster secrets.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/op/token";
      description = "Path of the 1Password service account token on the host.";
    };

    adminSSHKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH public keys allowed to log in as root.";
    };

    ceph = {
      monHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Ceph monitor host:port list. Empty disables Ceph.";
      };
      mountPoint = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/cephfs";
        description = "Where CephFS is mounted on every node.";
      };
      clientName = lib.mkOption {
        type = lib.types.str;
        default = "swarm";
        description = "Ceph client name (client.<name>).";
      };
    };

    swarm.managerAddress = lib.mkOption {
      type = lib.types.str;
      default = "node01";
      description = "Tailnet address nodes use to join the Swarm.";
    };

    logging.endpoint = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        HTTP(S) ingest endpoint logs are shipped to (Better Stack by
        default; any Vector-compatible backend works). Empty disables
        log shipping entirely.
      '';
    };
  };
}
