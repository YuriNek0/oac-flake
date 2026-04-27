{
  description = "Nix flake module for OpenAgentsControl (OAC) + Home Manager OpenCode";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Upstream OpenAgentsControl source (pinned by flake.lock)
    oac = {
      url = "github:darrenhinde/OpenAgentsControl";
      flake = false;
    };
  };

  outputs =
    { self, oac, ... }:
    {
      homeManagerModules = {
        oac = import ./modules/home-manager/oac.nix { oacSource = oac; };
        default = self.homeManagerModules.oac;
      };
    };
}
