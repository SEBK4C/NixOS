# Log shipping — Better Stack today, anything Vector speaks tomorrow.
#
# Why Better Stack: it's the fastest path to a working overview + trigger
# loop — hosted OTel-native logs with alerting, webhooks, and an MCP
# server AI agents can query, for zero ops today.
#
# Why this stays portable: Vector is the vendor-neutral shipper. Docker
# logs to the journal, Vector tails the journal, and one generic HTTP
# sink (endpoint from cluster-settings.nix, token from 1Password) does
# the shipping. Migrating to self-hosted Loki/ClickStack/any OTLP
# backend means swapping this sink — no node plumbing changes.
#
# Disabled entirely while cluster.logging.endpoint is empty.
{ config, pkgs, lib, ... }:

let
  cfg = config.cluster;
  enabled = cfg.logging.endpoint != "";
in
{
  config = lib.mkIf enabled {
    # Containers log to the journal too, so one shipper covers the node
    # baseline, Swarm workloads, and the kernel. `docker logs` still works.
    virtualisation.docker.daemon.settings."log-driver" = "journald";

    systemd.services.logging-secret = {
      description = "Fetch log shipping token from 1Password";
      wants = [ "op-bootstrap.service" ];
      after = [ "op-bootstrap.service" ];
      before = [ "vector.service" ];
      requiredBy = [ "vector.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        umask 077
        mkdir -p /run/logging
        printf 'LOG_TOKEN=%s\n' "$(/run/current-system/sw/bin/op-cluster read \
          'op://${cfg.vault}/BetterStack/credential')" > /run/logging/secret.env
      '';
    };

    services.vector = {
      enable = true;
      journaldAccess = true;
      # Validation would fail on the LOG_TOKEN env placeholder at build time.
      validateConfig = false;
      settings = {
        sources.journal = {
          type = "journald";
          current_boot_only = true;
        };
        sinks.remote = {
          type = "http";
          inputs = [ "journal" ];
          uri = cfg.logging.endpoint;
          encoding.codec = "json";
          compression = "gzip";
          batch.timeout_secs = 5;
          auth = {
            strategy = "bearer";
            token = "\${LOG_TOKEN}";
          };
        };
      };
    };

    systemd.services.vector.serviceConfig.EnvironmentFile = "/run/logging/secret.env";
  };
}
