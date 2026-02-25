using Android.OS;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace NoRKN.Android;

public sealed class DpiNativeBridge : IDisposable
{
    private readonly Action<string> _log;
    private CancellationTokenSource? _cts;
    private Task? _runnerTask;
    private volatile bool _running;
    private volatile bool _useNorknNative;
    private string _lastError = string.Empty;
    private string _runtimeRoot = string.Empty;
    private string _profileName = "multisplit";
    private string _optionsJson = "{}";
    private readonly DpiEngineCounters _counters = new();

    private long _lastTotalPkts;
    private long _lastTotalBytes;
    private DateTimeOffset _lastRateAt = DateTimeOffset.UtcNow;

    public DpiNativeBridge(Action<string> log)
    {
        _log = log;
    }

    public bool IsRunning => _running;

    public bool Init(string runtimeRoot, string profileName, string optionsJson)
    {
        _runtimeRoot = runtimeRoot;
        _profileName = string.IsNullOrWhiteSpace(profileName) ? "multisplit" : profileName;
        _optionsJson = string.IsNullOrWhiteSpace(optionsJson) ? "{}" : optionsJson;
        _lastError = string.Empty;

        try
        {
            var rc = norkn_dpi_init(runtimeRoot, _profileName, _optionsJson);
            if (rc == 0)
            {
                _useNorknNative = true;
                _log($"dpi native init: profile={_profileName}");
                return true;
            }

            _lastError = $"norkn_dpi_init rc={rc}";
            _log($"dpi native init returned rc={rc}; fallback to tun2socks");
        }
        catch (DllNotFoundException)
        {
            _lastError = "libnorkn_dpi.so not found";
            _log("libnorkn_dpi.so not found; fallback to tun2socks");
        }
        catch (EntryPointNotFoundException)
        {
            _lastError = "norkn_dpi symbols not found";
            _log("norkn_dpi symbols not found; fallback to tun2socks");
        }
        catch (Exception ex)
        {
            _lastError = ex.GetBaseException().Message;
            _log($"dpi init error: {_lastError}");
        }

        _useNorknNative = false;
        return true;
    }

    public void Start(ParcelFileDescriptor fd, TunnelSettings settings)
    {
        if (_running)
        {
            return;
        }

        var tunFd = fd.DetachFd();
        _cts = new CancellationTokenSource();
        _runnerTask = Task.Run(() => RunNative(tunFd, settings, _cts.Token));
        _running = true;
    }

    public void Stop()
    {
        try
        {
            _cts?.Cancel();
        }
        catch
        {
            // ignored
        }

        try
        {
            if (_useNorknNative)
            {
                norkn_dpi_stop();
            }
            else
            {
                hev_socks5_tunnel_quit();
            }
        }
        catch
        {
            // ignored
        }
    }

    public DpiEngineCounters GetCounters()
    {
        if (_useNorknNative)
        {
            try
            {
                var nativeJson = Marshal.PtrToStringAnsi(norkn_dpi_get_counters_json()) ?? string.Empty;
                if (!string.IsNullOrWhiteSpace(nativeJson))
                {
                    using var doc = JsonDocument.Parse(nativeJson);
                    var root = doc.RootElement;
                    _counters.BytesUp = root.TryGetProperty("bytes_up", out var bu) ? bu.GetInt64() : _counters.BytesUp;
                    _counters.BytesDown = root.TryGetProperty("bytes_down", out var bd) ? bd.GetInt64() : _counters.BytesDown;
                    _counters.PacketsUp = root.TryGetProperty("packets_up", out var pu) ? pu.GetInt64() : _counters.PacketsUp;
                    _counters.PacketsDown = root.TryGetProperty("packets_down", out var pd) ? pd.GetInt64() : _counters.PacketsDown;
                    _counters.ActiveConnections = root.TryGetProperty("active_connections", out var ac) ? ac.GetInt64() : _counters.ActiveConnections;
                    _counters.TotalConnections = root.TryGetProperty("total_connections", out var tc) ? tc.GetInt64() : _counters.TotalConnections;
                }
            }
            catch
            {
                // fallback to last counters
            }
        }

        UpdateRates();
        _counters.UpdatedAt = DateTimeOffset.UtcNow;
        return _counters.Clone();
    }

    public void MergeLocalSocksCounters(LocalSocksCounters snapshot)
    {
        _counters.BytesUp = Math.Max(_counters.BytesUp, snapshot.BytesUp);
        _counters.BytesDown = Math.Max(_counters.BytesDown, snapshot.BytesDown);
        _counters.PacketsUp = Math.Max(_counters.PacketsUp, snapshot.PacketsUp);
        _counters.PacketsDown = Math.Max(_counters.PacketsDown, snapshot.PacketsDown);
        _counters.ActiveConnections = snapshot.ActiveConnections;
        _counters.TotalConnections = Math.Max(_counters.TotalConnections, snapshot.TotalConnections);
        _counters.UpdatedAt = DateTimeOffset.UtcNow;
    }

    public string GetLastError()
    {
        if (_useNorknNative)
        {
            try
            {
                var value = Marshal.PtrToStringAnsi(norkn_dpi_get_last_error()) ?? string.Empty;
                if (!string.IsNullOrWhiteSpace(value))
                {
                    _lastError = value;
                }
            }
            catch
            {
                // ignored
            }
        }

        return _lastError;
    }

    private void RunNative(int tunFd, TunnelSettings settings, CancellationToken token)
    {
        try
        {
            if (_useNorknNative)
            {
                var rc = norkn_dpi_start(tunFd);
                _lastError = rc == 0 ? string.Empty : $"norkn_dpi_start rc={rc}";
                _log(rc == 0 ? "norkn_dpi exited normally" : _lastError);
                return;
            }

            var config = BuildTun2SocksConfig(settings);
            var configBytes = Encoding.UTF8.GetBytes(config);
            _log($"tun2socks starting: socks={settings.SocksHost}:{settings.SocksPort}, dns={settings.DnsServer}, mtu={settings.Mtu}, mode={settings.Mode}");
            var result = hev_socks5_tunnel_main_from_str(configBytes, (uint)configBytes.Length, tunFd);
            _lastError = result == 0 ? string.Empty : $"tun2socks rc={result}";
            _log($"tun2socks exited with code: {result}");
        }
        catch (Exception ex)
        {
            _lastError = ex.GetBaseException().Message;
            _log($"dpi native runtime error: {_lastError}");
        }
        finally
        {
            _running = false;
        }
    }

    private static string BuildTun2SocksConfig(TunnelSettings settings)
    {
        var udpMode = string.Equals(settings.Mode, "strong", StringComparison.OrdinalIgnoreCase)
            ? "tcp"
            : "udp";

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

    private void UpdateRates()
    {
        var now = DateTimeOffset.UtcNow;
        var elapsed = (now - _lastRateAt).TotalSeconds;
        if (elapsed < 0.8)
        {
            return;
        }

        var totalPkts = _counters.PacketsUp + _counters.PacketsDown;
        var totalBytes = _counters.BytesUp + _counters.BytesDown;
        _counters.PktsPerSecond = Math.Max(0, (long)((totalPkts - _lastTotalPkts) / elapsed));
        _counters.BytesPerSecond = Math.Max(0, (long)((totalBytes - _lastTotalBytes) / elapsed));
        _lastTotalPkts = totalPkts;
        _lastTotalBytes = totalBytes;
        _lastRateAt = now;
    }

    [DllImport("norkn_dpi", EntryPoint = "norkn_dpi_init", CallingConvention = CallingConvention.Cdecl)]
    private static extern int norkn_dpi_init(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string runtimeRoot,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string profileName,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string optionsJson);

    [DllImport("norkn_dpi", EntryPoint = "norkn_dpi_start", CallingConvention = CallingConvention.Cdecl)]
    private static extern int norkn_dpi_start(int tunFd);

    [DllImport("norkn_dpi", EntryPoint = "norkn_dpi_stop", CallingConvention = CallingConvention.Cdecl)]
    private static extern void norkn_dpi_stop();

    [DllImport("norkn_dpi", EntryPoint = "norkn_dpi_get_counters_json", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr norkn_dpi_get_counters_json();

    [DllImport("norkn_dpi", EntryPoint = "norkn_dpi_get_last_error", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr norkn_dpi_get_last_error();

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
        _cts = null;
        _runnerTask = null;
        _running = false;
    }
}
