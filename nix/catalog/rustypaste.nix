{ ... }:
{
  fleet.catalog.apps.rustypaste = {
    title = "rustypaste";
    description = "Minimal file upload / pastebin service";
    upstream = { url = "https://github.com/orhun/rustypaste"; repo = "orhun/rustypaste"; license = "MIT"; };
    impl = "package-systemd";
    nixModule = "rustypaste";
    status = "ported";
  };
}
