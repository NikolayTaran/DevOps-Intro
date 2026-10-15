{
  description = "QuickNotes — reproducible Go build + deterministic OCI image (Lab 11)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        # ------------------------------------------------------------------
        # Task 1: reproducible QuickNotes binary.
        # buildGoModule (not buildGoApplication) — it is the blessed nixpkgs
        # builder for plain Go modules: source + go.mod in, static-ish binary
        # out, with `-trimpath` and a fixed build environment by default.
        # QuickNotes has no cgo and no build-time code generation, so the
        # simpler builder is the right tool (see report, design question d).
        # ------------------------------------------------------------------
        quicknotes = pkgs.buildGoModule {
          pname = "quicknotes";
          version = "0.1.0";
          src = ./app;

          # go.mod is stdlib-only (no `require` lines, no go.sum): the correct
          # vendorHash is `null` — buildGoModule then skips the vendoring
          # derivation entirely. The moment a real dependency is added, the
          # build fails with the exact `got: sha256-…` line to paste here.
          vendorHash = null;

          # Lab 6 discipline carried forward: pure-Go static binary, no libc,
          # no dynamic loader — runs on any base (incl. scratch/empty layers).
          # (25.11 API: env vars passed via the `env` attrset, see module.nix.)
          env.CGO_ENABLED = 0;

          # `-s -w`: strip symbol table and DWARF — smaller, and removes a
          # source of environment-dependent bytes (carried from Lab 6).
          ldflags = [ "-s" "-w" ];

          # `go test` is already gated by the Lab 3 PR workflow on every push;
          # the flake's job here is the *artifact*, not the test suite.
          doCheck = false;
        };

        # ------------------------------------------------------------------
        # Task 2: deterministic OCI image, built without Docker.
        # dockerTools.buildImage renders the layer tar with sorted entries and
        # `created` pinned to the epoch — no wall clock ever enters the
        # tarball, so two independent builds hash identically.
        # ------------------------------------------------------------------
        docker = pkgs.dockerTools.buildImage {
          name = "quicknotes";
          tag = "lab11";

          # Root filesystem: the Task 1 binary (dereferenced from the store
          # symlink so the layer carries a real file), the seed notes, and a
          # pre-baked empty /data. At runtime Docker roots the container at a
          # root-owned `/` (the layer's `.` entry is skipped when the layer is
          # applied, and the overlayfs upper dir masks it), so a nonroot
          # process cannot mkdir at `/` — `/data` must ship in the layer.
          # tar --owner/--group (uid/gid below) rewrites it to 65532 with mode
          # 0755, so the app can write DATA_PATH there — Lab 6's nonroot
          # discipline, with no runAsRoot VM.
          copyToRoot = pkgs.runCommand "quicknotes-rootfs" { } ''
            mkdir -p $out/bin
            cp -L ${quicknotes}/bin/quicknotes $out/bin/quicknotes
            cp ${./app/seed.json} $out/seed.json
          '';

          # Every file and directory in the layer tar is owned by UID/GID
          # 65532 — distroless's `nonroot` — so the app owns everything it
          # needs to touch (the runtime `/` itself is root-owned by Docker's
          # layer application; that is why `/data` ships pre-baked above).
          # No runAsRoot VM involved.
          uid = 65532;
          gid = 65532;

          config = {
            # Exec form — no shell anywhere in the image anyway.
            Entrypoint = [ "/bin/quicknotes" ];
            ExposedPorts = { "8080/tcp" = { }; };
            # Numeric UID:GID, same 65532 as distroless's `nonroot`.
            User = "65532:65532";
            Env = [
              "ADDR=:8080"
              "DATA_PATH=/data/notes.json"
              "SEED_PATH=/seed.json"
            ];
          };
        };

        default = quicknotes;
      });

      devShells = forAllSystems (pkgs: {
        # `nix develop` drops collaborators into a pinned toolchain:
        # go (pinned by flake.lock), gopls, golangci-lint.
        default = pkgs.mkShell {
          packages = [ pkgs.go pkgs.gopls pkgs.golangci-lint ];
        };
      });
    };
}