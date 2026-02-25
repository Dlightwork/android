using Android.OS;
using System.Runtime.InteropServices;
using System.Text;

namespace NoRKN.Android;

public sealed class Tun2SocksBridge : IDisposable
{
    private readonly Action<string> _log;
    private CancellationTokenSource? _cts;
    private Task? _runnerTask;

    public Tun2SocksBridge(Action<string> log)
    {
        _log = log;
    }

    public bool IsRunning => _runnerTask is { IsCompleted: false };

    public void Start(ParcelFileDescriptor fd, TunnelSettings settings)
    {
        if (IsRunning)
        {
            _log("[Tun2SocksBridge.Start] Already running, ignoring duplicate start");
            return;
        }

        _log("[Tun2SocksBridge.Start] Extracting TUN file descriptor...");
        var tunFd = fd.DetachFd();
        
        if (tunFd <= 0)
        {
            _log("[Tun2SocksBridge.Start] ✗ Invalid TUN fd: " + tunFd);
            return;
        }
        
        _log("[Tun2SocksBridge.Start] TUN fd=" + tunFd + ", launching native bridge...");
        _cts = new CancellationTokenSource();
        _runnerTask = Task.Run(() => RunNative(tunFd, settings, _cts.Token));
    }

    public void Stop()
    {
        _log("[Tun2SocksBridge.Stop] Stopping native bridge...");
        try
        {
            _cts?.Cancel();
            _log("[Tun2SocksBridge.Stop] Cancellation token signaled");
        }
        catch
        {
            // ignored
        }

        try
        {
            _log("[Tun2SocksBridge.Stop] Calling native quit function...");
            hev_socks5_tunnel_quit();
            _log("[Tun2SocksBridge.Stop] Native quit succeeded");
        }
        catch (DllNotFoundException)
        {
            _log("[Tun2SocksBridge.Stop] DLL not loaded (expected if already stopped)");
        }
        catch (EntryPointNotFoundException)
        {
            _log("[Tun2SocksBridge.Stop] Entry point not found (expected if already stopped)");
        }
        catch (Exception ex)
        {
            _log($"[Tun2SocksBridge.Stop] Exception during quit: {ex.Message}");
        }
        
        _log("[Tun2SocksBridge.Stop] Native bridge stopped");
    }

    private void RunNative(int tunFd, TunnelSettings settings, CancellationToken token)
    {
        try
        {
            var config = BuildConfig(settings);
            var configBytes = Encoding.UTF8.GetBytes(config);
            _log($"[RunNative] Starting tun2socks with fd={tunFd}");
            _log($"[RunNative] Config: SOCKS={settings.SocksHost}:{settings.SocksPort}, DNS={settings.DnsServer}, MTU={settings.Mtu}");
            _log($"[RunNative] Attempting to load native library: tun2socks...");

            var result = hev_socks5_tunnel_main_from_str(configBytes, (uint)configBytes.Length, tunFd);
            _log($"[RunNative] tun2socks exited with code: {result}");
        }
        catch (DllNotFoundException ex)
        {
            _log($"[RunNative] ✗ CRITICAL: libtun2socks.so not found");
            _log($"[RunNative] {ex.Message}");
            _log($"[RunNative] Device CPU ABI might not be supported");
            _log($"[RunNative] Supported ABIs in this APK: arm64-v8a, armeabi-v7a, x86, x86_64");
        }
        catch (EntryPointNotFoundException ex)
        {
            _log($"[RunNative] ✗ CRITICAL: Native function not found in library");
            _log($"[RunNative] {ex.Message}");
            _log($"[RunNative] libun2socks.so might be corrupted or incompatible");
        }
        catch (Exception ex)
        {
            _log($"[RunNative] ✗ CRITICAL: Exception in native call");
            _log($"[RunNative] Type: {ex.GetType().Name}");
            _log($"[RunNative] Message: {ex.Message}");
            _log($"[RunNative] StackTrace: {ex.StackTrace}");
        }
    }

    private static string BuildConfig(TunnelSettings settings)
    {
        // Embedded local SOCKS handles CONNECT/TCP only; force UDP-over-TCP mode for stability.
        var udpMode = "tcp";

        return $$"""
tunnel:
  mtu: {{settings.Mtu}}
  ipv4: 198.18.0.1
  ipv6: 'fc00::1'
socks5:
  address: {{settings.SocksHost}}
  port: {{settings.SocksPort}}
  udp: '{{udpMode}}'
misc:
  log-level: info
""";
    }

    [DllImport("tun2socks", EntryPoint = "hev_socks5_tunnel_main_from_str", CallingConvention = CallingConvention.Cdecl)]
    private static extern int hev_socks5_tunnel_main_from_str(byte[] configStr, uint configLen, int tunFd);

    [DllImport("tun2socks", EntryPoint = "hev_socks5_tunnel_quit", CallingConvention = CallingConvention.Cdecl)]
    private static extern void hev_socks5_tunnel_quit();

    public void Dispose()
    {
        Stop();
        try
        {
            _runnerTask?.Wait(300);
        }
        catch
        {
            // ignored
        }
        _cts?.Dispose();
        _runnerTask = null;
        _cts = null;
    }
}
