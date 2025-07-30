# LuCI App AdGuard Home

Advanced OpenWrt LuCI app for AdGuard Home

[中文 README](README.CN.md)

Download `.ipk` and `.apk` from [Releases](https://github.com/stevenjoezhang/luci-app-adguardhome/releases)

## Features

- AdGuard Home service port, username and password management
- Download/update core in LuCI interface (supports custom download URL)
- Compress core with `upx`, reducing storage space usage
- DNS redirection methods:
  - Redirect port 53 to AdGuard Home (Directly using the system firewall settings, offers better compatibility with `nftables` and also supports IPv6 redirection)
  - As the upstream of `dnsmasq` (IP in AdGuard Home statistics will show as `127.0.0.1`, unable to track clients and adjust settings accordingly)
  - Replace `dnsmasq` with port 53 (Ports of `dnsmasq` and AdGuard Home will be exchanged, AdGuard Home will use port 53)
- Customization options:
  - Customize executable file path (supports `/tmp`, auto redownload after reboot)
  - Customize config file path
  - Customize work directory
  - Customize runtime log path
- GFWList query to specific DNS server. Also check out [luci-app-autoipsetadder](https://github.com/rufengsuixing/luci-app-autoipsetadder)
- View/delete/backup runtime log in positive/reverse order with 3-second updates + local browser timezone conversion
- Manual configuration:
  - YAML editor support
  - Templates for fast configuration
- File preservation during system upgrades
- Waits for network access at boot (3min timeout, mainly to prevent filter update failure)
- Workdir backup on shutdown (Note: backup also triggers during IPK updates)
- Scheduled tasks (default values, time and parameters adjustable in scheduler):
  - Auto update IPv6 hosts and restart AdGuard Home (hourly, no restart if no updates)
  - Auto update GFW list and restart AdGuard Home (`3:30/day`, no restart if no updates)

## Dependencies

- `wget` or `curl` (for downloading core)
- `upx` and `xz` (optional, for core compression)

Note: the plugin will install dependencies with `opkg` automatically if not present. However, if the `opkg` source is not available in your distribution, you need to include these packages during OpenWrt compilation.

## Known Issues

- Database doesn't support filesystems that don't support `mmap` (such as `jffs2` and `data-stk-oo`). Please modify work directory; if `jffs2` is detected, the app will automatically create soft links (`ln`) for the databases to `/tmp`, but DNS database will be lost after reboot
- If you find many localhost queries from `127.0.0.1`, the DDNS plugin might be the cause. If you don't use DDNS, please remove or comment out `/etc/hotplug.d/iface/95-ddns`. For other abnormal queries from the local machine, advanced users can use [kmod-plog-port](https://github.com/rufengsuixing/kmod-plog-port) to diagnose

## Usage

- Download release and install with `opkg`
- Or when building OpenWrt, clone the code to package path and set as `y` or `m`

## About Compression

The plugin supports compressing the AdGuard Home executable with `upx`, which is useful for devices with limited storage. Testing shows that using the `-1` parameter (Compress faster) takes 2 seconds and achieves a 42% compression rate, while using `--ultra-brute` (Try even more compression variants) takes 660 seconds and achieves a 23% compression rate.  
Note that if the filesystem already supports compression (like `jffs2`), using `upx` may not save much space.  
Also, compression trades RAM for ROM space, which consumes more memory during runtime.

## OpenClash Combination Methods

OpenClash and other proxy plugins often include DNS redirection features. When used with AdGuard Home, careful configuration is needed to avoid conflicts or DNS query issues. Here are recommended combination methods:
1. Disable DNS redirection in the proxy plugin to avoid modifying `dnsmasq` settings or setting firewall rules that may conflict.
2. Record the DNS server address and port provided by the proxy plugin, e.g., OpenClash's default port is 7874.
3. Set AdGuard Home's upstream DNS to the proxy plugin's DNS server address and port, e.g., `1127.0.0.1:7874`.
4. Enable DNS redirection in AdGuard Home plugin settings to redirect port 53 to AdGuard Home.

## Screenshots

Example in zh-cn:  
![Basic Settings - LuCI](screenshots/1.png)
![Core Settings - LuCI](screenshots/2.png)
![Manual Config - LuCI](screenshots/3.png)
![Log - LuCI](screenshots/4.png)
