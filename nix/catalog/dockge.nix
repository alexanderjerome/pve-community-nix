{ ... }:
{
  fleet.catalog.apps.dockge = {
    title = "Dockge";
    description = "Self-hosted Docker compose stack manager";
    upstream = { url = "https://dockge.kuma.pet/"; repo = "louislam/dockge"; license = "MIT"; };
    impl = "oci";
    nixModule = "dockge";
    status = "ported";
  };
}
