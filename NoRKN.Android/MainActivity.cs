using Android.App;
using Android.Content;
using Android.Graphics;
using Android.Net;
using Android.OS;
using Android.Views;
using Android.Widget;
using System.Net;
using System.Net.Sockets;

namespace NoRKN.Android;

[Activity(
    Label = "NoRKN",
    MainLauncher = true,
    Exported = true,
    Icon = "@mipmap/ic_launcher",
    Theme = "@android:style/Theme.DeviceDefault.NoActionBar")]
public class MainActivity : Activity
{
    private const int VpnPrepareRequestCode = 41001;
    private const string EmbeddedSocksHost = "127.0.0.1";
    private const int EmbeddedSocksPort = 1080;

    private TextView _statusValue = null!;
    private TextView _modeValue = null!;
    private TextView _logView = null!;
    private EditText _txtSocksHost = null!;
    private EditText _txtSocksPort = null!;
    private EditText _txtDns = null!;
    private Switch _swFullTunnel = null!;
    private string _pendingMode = "multisplit";

    protected override void OnCreate(Bundle? savedInstanceState)
    {
        base.OnCreate(savedInstanceState);

        try
        {
            if (Build.VERSION.SdkInt >= BuildVersionCodes.Lollipop)
            {
                Window?.SetStatusBarColor(Color.ParseColor("#10141A"));
            }

            var root = new LinearLayout(this)
            {
                Orientation = Orientation.Vertical
            };
            root.SetBackgroundColor(Color.ParseColor("#0E1520"));
            root.SetPadding(24, 24, 24, 24);

        var title = new TextView(this)
        {
            Text = "NoRKN",
            TextSize = 28
        };
        title.SetTextColor(Color.ParseColor("#EAF2FF"));
        title.SetTypeface(Typeface.DefaultBold, TypefaceStyle.Bold);
        root.AddView(title);

        var subtitle = new TextView(this)
        {
            Text = "Android network engine (VpnService)",
            TextSize = 14
        };
        subtitle.SetTextColor(Color.ParseColor("#A6B4CC"));
        subtitle.SetPadding(0, 0, 0, 14);
        root.AddView(subtitle);

        var warning = new TextView(this)
        {
            Text = "Android mode: встроенный локальный движок. Нажмите Start, ввод SOCKS не требуется.",
            TextSize = 13
        };
        warning.SetTextColor(Color.ParseColor("#FFC46B"));
        warning.SetPadding(0, 0, 0, 16);
        root.AddView(warning);

        var settings = TunnelSettings.Load(this);
        var settingsCard = new LinearLayout(this) { Orientation = Orientation.Vertical };
        settingsCard.SetBackgroundColor(Color.ParseColor("#1A2433"));
        settingsCard.SetPadding(14, 12, 14, 12);
        settingsCard.LayoutParameters = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MatchParent,
            ViewGroup.LayoutParams.WrapContent)
        {
            TopMargin = 6
        };
        var stTitle = new TextView(this)
        {
            Text = "Tunnel settings",
            TextSize = 15
        };
        stTitle.SetTextColor(Color.ParseColor("#EAF2FF"));
        stTitle.SetTypeface(Typeface.DefaultBold, TypefaceStyle.Bold);
        settingsCard.AddView(stTitle);

        _txtSocksHost = MakeEdit("SOCKS host", EmbeddedSocksHost);
        _txtSocksPort = MakeEdit("SOCKS port", EmbeddedSocksPort.ToString());
        _txtDns = MakeEdit("DNS server", settings.DnsServer);
        _txtSocksHost.Visibility = ViewStates.Gone;
        _txtSocksPort.Visibility = ViewStates.Gone;
        settingsCard.AddView(_txtDns);

        var swRow = new LinearLayout(this) { Orientation = Orientation.Horizontal };
        swRow.SetPadding(0, 8, 0, 0);
        var swLabel = new TextView(this)
        {
            Text = "Full tunnel",
            TextSize = 14
        };
        swLabel.SetTextColor(Color.ParseColor("#D3DEEF"));
        _swFullTunnel = new Switch(this) { Checked = settings.FullTunnel };
        swRow.AddView(swLabel, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WrapContent, 1f));
        swRow.AddView(_swFullTunnel);
        settingsCard.AddView(swRow);

        root.AddView(settingsCard);

        root.AddView(MakeCard("Status", out _statusValue, "Idle"));
        root.AddView(MakeCard("Mode", out _modeValue, "-"));

        var buttonsRow1 = new LinearLayout(this) { Orientation = Orientation.Horizontal };
        buttonsRow1.SetPadding(0, 10, 0, 0);
        var btnMulti = MakeButton("Start: multisplit");
        var btnStrong = MakeButton("Start: strong");
        btnMulti.Click += (_, _) => PrepareAndStartVpn("multisplit");
        btnStrong.Click += (_, _) => PrepareAndStartVpn("strong");
        buttonsRow1.AddView(btnMulti, MakeWeightParams());
        buttonsRow1.AddView(btnStrong, MakeWeightParams(12));
        root.AddView(buttonsRow1);

        var buttonsRow2 = new LinearLayout(this) { Orientation = Orientation.Horizontal };
        buttonsRow2.SetPadding(0, 10, 0, 0);
        var btnStop = MakeButton("Stop");
        var btnDiag = MakeButton("Diagnostics");
        btnStop.Click += (_, _) => StopVpn();
        btnDiag.Click += async (_, _) => await RunSocksDiagnostics();
        buttonsRow2.AddView(btnStop, MakeWeightParams());
        buttonsRow2.AddView(btnDiag, MakeWeightParams(12));
        root.AddView(buttonsRow2);

        var logTitle = new TextView(this)
        {
            Text = "Log",
            TextSize = 18
        };
        logTitle.SetTextColor(Color.ParseColor("#EAF2FF"));
        logTitle.SetTypeface(Typeface.DefaultBold, TypefaceStyle.Bold);
        logTitle.SetPadding(0, 18, 0, 8);
        root.AddView(logTitle);

        _logView = new TextView(this)
        {
            Text = string.Empty,
            TextSize = 13
        };
        _logView.SetTextColor(Color.ParseColor("#D3DEEF"));
        _logView.SetBackgroundColor(Color.ParseColor("#141D2A"));
        _logView.SetPadding(14, 14, 14, 14);

        var logScroller = new ScrollView(this);
        logScroller.AddView(_logView);
        root.AddView(logScroller, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MatchParent,
            0,
            1f));

            SetContentView(root);
            AppendLog("NoRKN Android UI ready.");
            AppendLog("Встроенный локальный SOCKS5 включается автоматически.");
        }
        catch (Exception ex)
        {
            ShowStartupError(ex);
        }
    }

    protected override void OnStart()
    {
        base.OnStart();
        NorknVpnService.Log += HandleServiceLog;
        NorknVpnService.StateChanged += HandleServiceState;
    }

    protected override void OnStop()
    {
        NorknVpnService.Log -= HandleServiceLog;
        NorknVpnService.StateChanged -= HandleServiceState;
        base.OnStop();
    }

    protected override void OnActivityResult(int requestCode, Result resultCode, Intent? data)
    {
        base.OnActivityResult(requestCode, resultCode, data);
        if (requestCode != VpnPrepareRequestCode)
        {
            return;
        }

        if (resultCode == Result.Ok)
        {
            StartVpn(_pendingMode);
            return;
        }

        AppendLog("VPN permission was denied.");
        SetUiState("Permission denied", "-", "Cannot start without VPN permission.");
    }

    private void PrepareAndStartVpn(string mode)
    {
        _pendingMode = mode;
        var intent = VpnService.Prepare(this);
        if (intent != null)
        {
            StartActivityForResult(intent, VpnPrepareRequestCode);
            AppendLog("Requesting VPN permission...");
            return;
        }

        StartVpn(mode);
    }

    private void StartVpn(string mode)
    {
        var settings = ReadAndSaveSettings(mode);
        var intent = new Intent(this, typeof(NorknVpnService));
        intent.SetAction(NorknVpnService.ActionStart);
        intent.PutExtra(NorknVpnService.ExtraMode, settings.Mode);
        intent.PutExtra(NorknVpnService.ExtraSocksHost, settings.SocksHost);
        intent.PutExtra(NorknVpnService.ExtraSocksPort, settings.SocksPort);
        intent.PutExtra(NorknVpnService.ExtraDns, settings.DnsServer);
        intent.PutExtra(NorknVpnService.ExtraMtu, settings.Mtu);
        intent.PutExtra(NorknVpnService.ExtraFullTunnel, settings.FullTunnel);
        StartService(intent);
        SetUiState("Starting", settings.Mode, $"Start requested: {settings.Mode}");
    }

    private void StopVpn()
    {
        var intent = new Intent(this, typeof(NorknVpnService));
        intent.SetAction(NorknVpnService.ActionStop);
        StartService(intent);
        StopService(new Intent(this, typeof(NorknVpnService)));
        SetUiState("Stopping", "-", "Stop requested.");
    }

    private void HandleServiceLog(string message)
    {
        RunOnUiThread(() => AppendLog(message));
    }

    private void HandleServiceState(bool running, string mode)
    {
        RunOnUiThread(() =>
        {
            _statusValue.Text = running ? "Running" : "Stopped";
            _modeValue.Text = running ? mode : "-";
        });
    }

    private LinearLayout MakeCard(string label, out TextView valueView, string initialValue)
    {
        var card = new LinearLayout(this) { Orientation = Orientation.Vertical };
        card.SetBackgroundColor(Color.ParseColor("#1A2433"));
        card.SetPadding(14, 12, 14, 12);
        card.LayoutParameters = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MatchParent,
            ViewGroup.LayoutParams.WrapContent)
        {
            TopMargin = 10
        };

        var name = new TextView(this)
        {
            Text = label,
            TextSize = 14
        };
        name.SetTextColor(Color.ParseColor("#A6B4CC"));
        card.AddView(name);

        valueView = new TextView(this)
        {
            Text = initialValue,
            TextSize = 24
        };
        valueView.SetTextColor(Color.ParseColor("#EAF2FF"));
        valueView.SetTypeface(Typeface.DefaultBold, TypefaceStyle.Bold);
        card.AddView(valueView);

        return card;
    }

    private Button MakeButton(string text)
    {
        var button = new Button(this)
        {
            Text = text
        };
        button.SetTextColor(Color.White);
        button.SetBackgroundColor(Color.ParseColor("#3A9DF5"));
        button.SetAllCaps(false);
        return button;
    }

    private static LinearLayout.LayoutParams MakeWeightParams(int leftMargin = 0)
    {
        return new LinearLayout.LayoutParams(
            0,
            ViewGroup.LayoutParams.WrapContent,
            1f)
        {
            LeftMargin = leftMargin
        };
    }

    private void SetUiState(string status, string mode, string log)
    {
        _statusValue.Text = status;
        _modeValue.Text = mode;
        AppendLog(log);
    }

    private void AppendLog(string text)
    {
        if (_logView is null)
        {
            return;
        }

        var line = $"[{DateTime.Now:HH:mm:ss}] {text}\n";
        _logView.Text += line;
    }

    private void ShowStartupError(Exception ex)
    {
        try
        {
            global::Android.Util.Log.Error("NoRKN", $"Startup crash: {ex}");
            var dir = FilesDir?.AbsolutePath ?? CacheDir?.AbsolutePath ?? "/data/local/tmp";
            var path = System.IO.Path.Combine(dir, "startup-crash.log");
            System.IO.File.WriteAllText(path, ex.ToString());
        }
        catch
        {
            // ignored
        }

        var scroll = new ScrollView(this);
        scroll.SetBackgroundColor(Color.ParseColor("#0E1520"));

        var message = new TextView(this)
        {
            Text = "NoRKN: ошибка при запуске интерфейса.\n\n" +
                   ex.Message + "\n\n" +
                   ex.ToString(),
            TextSize = 14
        };
        message.SetTextColor(Color.ParseColor("#FFB4B4"));
        message.SetPadding(24, 24, 24, 24);
        scroll.AddView(message);

        SetContentView(scroll);
    }

    private async Task RunSocksDiagnostics()
    {
        var host = EmbeddedSocksHost;
        var port = EmbeddedSocksPort;

        AppendLog($"Diagnostics: checking embedded SOCKS {host}:{port} ...");
        try
        {
            using var client = new TcpClient();
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(3));
            await client.ConnectAsync(host, port, cts.Token);
            AppendLog($"Diagnostics: SOCKS reachable ({host}:{port}).");
        }
        catch (System.OperationCanceledException)
        {
            AppendLog($"Diagnostics: timeout for {host}:{port}.");
        }
        catch (Exception ex)
        {
            AppendLog($"Diagnostics: SOCKS unreachable: {ex.GetBaseException().Message}");
            AppendLog("Hint: press Start first, embedded SOCKS starts with VPN service.");
        }
    }

    private static bool IsLoopbackHost(string host)
    {
        if (string.Equals(host, "localhost", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return IPAddress.TryParse(host, out var ip) && IPAddress.IsLoopback(ip);
    }

    private TunnelSettings ReadAndSaveSettings(string mode)
    {
        var settings = TunnelSettings.Load(this);
        settings.Mode = mode;
        settings.SocksHost = EmbeddedSocksHost;
        settings.SocksPort = EmbeddedSocksPort;
        settings.DnsServer = (_txtDns.Text ?? "1.1.1.1").Trim();
        settings.FullTunnel = _swFullTunnel.Checked;
        settings.Save(this);
        return settings;
    }

    private EditText MakeEdit(string hint, string value)
    {
        var edit = new EditText(this)
        {
            Text = value,
            Hint = hint
        };
        edit.SetTextColor(Color.ParseColor("#EAF2FF"));
        edit.SetHintTextColor(Color.ParseColor("#7E8CA2"));
        edit.SetBackgroundColor(Color.ParseColor("#141D2A"));
        edit.SetPadding(18, 12, 18, 12);
        var lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MatchParent, ViewGroup.LayoutParams.WrapContent)
        {
            TopMargin = 8
        };
        edit.LayoutParameters = lp;
        return edit;
    }
}

