# Baseline shared by all nodes: flakes, SSH, time sync, firewall.
{ config, pkgs, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
    settings.PasswordAuthentication = false;
  };
  users.users.root.openssh.authorizedKeys.keys = config.cluster.adminSSHKeys;

  # Accurate clocks matter: 1Password API auth and Ceph both reject skew.
  services.chrony.enable = true;

  networking.firewall = {
    enable = true;
    # Swarm control/data plane and Portainer flow over the tailnet only.
    trustedInterfaces = [ "tailscale0" ];
  };

  environment.systemPackages = with pkgs; [ vim git jq ];

  system.stateVersion = "25.11"; # do not change after first install
}
