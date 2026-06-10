# Phase 3 — attach storage.
#
# Fetches the CephFS secret key from op://<vault>/Ceph/credential, writes
# it to /etc/ceph/secret (root-only), and mounts CephFS at the configured
# mount point. Disabled entirely while cluster.ceph.monHosts is empty.
{ config, pkgs, lib, ... }:

let
  cfg = config.cluster;
  enabled = cfg.ceph.monHosts != [ ];
  monList = lib.concatStringsSep "," cfg.ceph.monHosts;
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = [ pkgs.ceph-client ];

    environment.etc."ceph/ceph.conf".text = ''
      [global]
      mon host = ${monList}
    '';

    systemd.services.ceph-secret = {
      description = "Fetch Ceph client key from 1Password";
      wants = [ "op-bootstrap.service" ];
      after = [ "op-bootstrap.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        umask 077
        mkdir -p /etc/ceph
        printf '%s' "$(/run/current-system/sw/bin/op-cluster read \
          'op://${cfg.vault}/Ceph/credential')" > /etc/ceph/secret
      '';
    };

    systemd.mounts = [{
      description = "CephFS cluster storage";
      what = "${monList}:/";
      where = cfg.ceph.mountPoint;
      type = "ceph";
      options = "name=${cfg.ceph.clientName},secretfile=/etc/ceph/secret,_netdev";
      wantedBy = [ "multi-user.target" ];
      requires = [ "ceph-secret.service" ];
      after = [ "ceph-secret.service" "network-online.target" "tailscale-join.service" ];
    }];
  };
}
