{ lib }:
# Device-passthrough presets — the concrete /dev entries the legacy
# scripts appended to lxc.conf (misc/build.func configure_gpu_passthrough
# / configure_additional_devices / configure_usb_passthrough), as
# fleet.compute.<name>.devices entries (bpg device_passthrough → PVE devN).
#
# Vendor detection is not declarative: the consumer names the GPU vendor
# in mkApp { gpu = "intel"; } and the preset picks the node list. gid 44
# (video) matches what the community scripts used; the NixOS platform
# module pins the guest's video/render gids so both sides agree.
rec {
  tun = [ { path = "/dev/net/tun"; } ];

  coral = [ { path = "/dev/apex_0"; } ];

  gpu = {
    intel = [
      { path = "/dev/dri/renderD128"; gid = 44; mode = "0660"; }
      { path = "/dev/dri/card0"; gid = 44; mode = "0660"; }
    ];
    amd = gpu.intel ++ [ { path = "/dev/kfd"; gid = 44; mode = "0660"; } ];
    nvidia = [
      { path = "/dev/nvidia0"; }
      { path = "/dev/nvidiactl"; }
      { path = "/dev/nvidia-uvm"; }
      { path = "/dev/nvidia-uvm-tools"; }
      { path = "/dev/nvidia-modeset"; }
    ];
  };

  # USB serial adapters (Zigbee / Z-Wave sticks). The device nodes bind
  # cleanly; the stable /dev/serial/by-id directory and the hot-plug
  # cgroup rules (c 188:* / c 189:*) need raw lxc.conf lines, which go
  # through fleet.compute.<name>.lxc_extra_conf.
  usbSerial = {
    devices = [
      { path = "/dev/ttyUSB0"; } { path = "/dev/ttyUSB1"; }
      { path = "/dev/ttyACM0"; } { path = "/dev/ttyACM1"; }
    ];
    lxc_extra_conf = [
      "lxc.cgroup2.devices.allow: c 188:* rwm"
      "lxc.cgroup2.devices.allow: c 189:* rwm"
      "lxc.mount.entry: /dev/serial/by-id dev/serial/by-id none bind,optional,create=dir"
    ];
  };

  # Everything a preset's device flags imply for one host.
  forPreset = { preset, gpuVendor ? null, coral ? false, usbSerial' ? false }:
    lib.optionals preset.devices.tun tun
    ++ lib.optionals (preset.devices.gpu && gpuVendor != null) gpu.${gpuVendor}
    ++ lib.optionals (preset.devices.coral && coral) coral
    ++ lib.optionals (preset.devices.usbSerial && usbSerial') usbSerial.devices;
}
