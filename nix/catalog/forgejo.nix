{ ... }:
{
  fleet.catalog.apps.forgejo = {
    title = "Forgejo";
    description = "Self-hosted lightweight software forge";
    category = "git";
    upstream = { url = "https://forgejo.org/"; repo = "forgejo/forgejo"; repoHost = "codeberg"; license = "GPL-3.0-or-later"; };
    # The legacy script sized the container per OS at runtime (Alpine 1/256/1,
    # Debian 2/2048/10); the NixOS host needs the Debian-class numbers.
    defaults = { cpu_cores = 2; memory_mb = 2048; root_disk_gb = 10; };
    impl = "nixos-service";
    nixModule = "forgejo";
    status = "ported";
  };
}
