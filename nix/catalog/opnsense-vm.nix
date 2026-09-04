{ ... }:
# Tier 5 (image): an appliance VM with no NixOS inside. mkApp creates the
# VM (UEFI, no cloud-init, no colmena target); the consumer declares the
# disk image as a `download` resource with the `import` content type and
# points `compute.image` at it:
#
#   fleet.resources.opnsense-image = { kind = "download"; …; content_type = "import";
#     url = "https://…/OPNsense-<ver>-nano-amd64.img"; file_name = "opnsense.img"; datastore_id = "local"; };
#   catalog.lib.mkApp { app = "opnsense-vm"; compute = { image = "import:local:import/opnsense.img"; … }; }
{
  fleet.catalog.apps.opnsense-vm = {
    title = "OPNsense";
    description = "FreeBSD-based firewall and routing platform (appliance VM)";
    category = "network";
    upstream = { url = "https://opnsense.org/"; repo = "opnsense/core"; repoHost = "github"; license = "BSD-2-Clause"; };
    impl = "image";
    status = "ported";
    port = 443;
  };
}
