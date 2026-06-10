{
  description = "NixOS Docker Swarm cluster — 1Password bootstrap, Tailscale mesh, Ceph storage, Portainer management";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;

      mkNode = name: role:
        lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./cluster-settings.nix
            ./modules/cluster.nix
            ./modules/common.nix
            ./modules/onepassword.nix
            ./modules/tailscale.nix
            ./modules/ceph.nix
            ./modules/swarm.nix
            ./modules/portainer.nix
            ./modules/logging.nix
            (./hosts + "/${name}/hardware-configuration.nix")
            {
              networking.hostName = name;
              cluster.role = role;
            }
          ];
        };

      managers = [ "node01" "node02" "node03" ];
      workers = [ "node04" "node05" "node06" "node07" "node08" "node09" "node10" ];
    in
    {
      nixosConfigurations =
        lib.genAttrs managers (name: mkNode name "manager")
        // lib.genAttrs workers (name: mkNode name "worker");
    };
}
