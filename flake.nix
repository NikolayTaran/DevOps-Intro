{
  description = "QuickNotes — reproducible Go build + deterministic OCI image (Lab 11)";

  inputs = {
    # Pinned channel (the exact snapshot is fixed by the committed flake.lock
    # via narHash). Tarball form on purpose: it resolves through
    # codeload.github.com and does not depend on the api.github.com rate
    # limit; the lockfile still pins the tarball hash byte-for-byte.
    nixpkgs.url = "https://github.com/NixOS/nixpkgs/archive/nixos-25.11.tar.gz";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # app/go.mod declares `go 1.24`; use that toolchain explicitly instead of
      # whatever the channel happens to ship as its default `go`.
      buildGo = pkgs.buildGoModule.override {
        go = pkgs.go_1_24 or pkgs.go;
      };

      quicknotes = buildGo {
        pname = "quicknotes";
        version = "0.1.0";
        src = ./app;

        # QuickNotes is stdlib-only (go.mod has zero require lines), so the
        # vendor tree is empty and nixpkgs requires `null` here; a pinned
        # empty-tree hash is rejected.
        vendorHash = null;

        env.CGO_ENABLED = "0";
        # Same flags as the Lab 6 Dockerfile: stripped, no debug info.
        ldflags = [
          "-s"
          "-w"
        ];

        meta = with pkgs.lib; {
          description = "QuickNotes API (DevOps-Intro)";
          mainProgram = "quicknotes";
          license = licenses.mit;
        };
      };

      # seed.json copied from the app source into /etc inside the image.
      seed = pkgs.runCommand "quicknotes-seed" { } ''
        mkdir -p $out/etc
        install -m 0644 ${./app/seed.json} $out/etc/seed.json
      '';

      # Deterministic OCI image built WITHOUT a Docker daemon (dockerTools).
      dockerImage = pkgs.dockerTools.buildImage {
        name = "quicknotes";
        tag = "nix";
        # Fixed creation time: no wall-clock leak, bit-identical tarball.
        created = "1970-01-01T00:00:01Z";
        copyToRoot = pkgs.buildEnv {
          name = "quicknotes-root";
          paths = [
            quicknotes
            seed
            pkgs.dockerTools.fakeNss
            pkgs.dockerTools.usrBinEnv
            pkgs.cacert
          ];
          pathsToLink = [
            "/bin"
            "/etc"
          ];
        };
        config = {
          Entrypoint = [ "/bin/quicknotes" ];
          ExposedPorts = {
            "8080/tcp" = { };
          };
          # Lab 6 discipline carried over: non-root (nobody = uid 65534 from fakeNss).
          User = "65534:65534";
          Env = [
            "ADDR=:8080"
            "DATA_PATH=/tmp/notes.json"
            "SEED_PATH=/etc/seed.json"
            "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
          ];
          # /tmp is the only writable location for the notes file.
          WorkingDir = "/tmp";
        };
        # The runtime stage has no shell, so ship a writable /tmp in the image.
        extraCommands = ''
          mkdir -p tmp
          chmod 1777 tmp
        '';
      };
    in
    {
      packages.${system} = {
        quicknotes = quicknotes;
        default = quicknotes;
        docker = dockerImage;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          (pkgs.go_1_24 or pkgs.go)
          pkgs.gopls
          pkgs.golangci-lint
        ];
      };
    };
}
