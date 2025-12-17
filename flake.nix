{
  description = "Pim flake";

  inputs.utils.url = "github:numtide/flake-utils";

  outputs =
    {
      self,
      nixpkgs,
      utils,
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            nushell
            zig
	    shader-slang
          ];

          shellHook = ''
            echo "nushell   `nu -v`"
            echo "zig       `zig version`"
            echo -n "slangc    "; slangc -v
            exec nu --config ./config.nu
          '';

          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
            pkgs.vulkan-loader
          ];
          VK_LAYER_PATH = "${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d";
        };
      }
    );
}
