Place native tun2socks libraries here to enable real packet forwarding:

Expected layout:
native/
  arm64-v8a/
    libtun2socks.so
  armeabi-v7a/
    libtun2socks.so
  x86/
    libtun2socks.so
  x86_64/
    libtun2socks.so

Current build source:
_android_native/hev-socks5-tunnel (real tun2socks engine)

Build and copy command:
tools/build-android-native-tun2socks.ps1

The app calls exports from this library:
- hev_socks5_tunnel_main_from_str(...)
- hev_socks5_tunnel_quit()

Without these libraries the VPN service starts but cannot forward traffic.
