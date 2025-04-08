{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    astal = {
      url = "github:aylur/astal";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    astal,
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    packages.${system}.default = astal.lib.mkLuaPackage {
      inherit pkgs;
      name = "kaneru";
      src = ./.;

      extraPackages = with astal.packages.${system};
        [
          battery
          astal3
          io
          apps
          bluetooth
          mpris
          network
          notifd
          powerprofiles
          tray
          wireplumber
        ]
        ++ (with pkgs; [
          dart-sass
          inotify-tools
          brightnessctl
          gammastep
          wget
          curl
          fastfetch
        ])
        ++ (with pkgs.lua52Packages; [
          cjson
          luautf8
        ]);
    };
  };
}
