using Android.Content;

namespace NoRKN.Android;

public sealed class TunnelSettings
{
    public string SocksHost { get; set; } = "127.0.0.1";
    public int SocksPort { get; set; } = 1080;
    public string DnsServer { get; set; } = "1.1.1.1";
    public int Mtu { get; set; } = 1500;
    public bool FullTunnel { get; set; } = true;
    public string Mode { get; set; } = "multisplit";

    /// <summary>
    /// Flag indicating whether the VPN service should automatically start
    /// after the device boots. When set to <c>true</c>, the
    /// <see cref="BootCompletedReceiver"/> will trigger a call to the
    /// <see cref="NorknVpnService"/> during the boot sequence.
    /// </summary>
    public bool AutoStartOnBoot { get; set; } = false;

    /// <summary>
    /// The name of the profile (or mode) that should be used when
    /// automatically starting the VPN service on boot. If empty, the
    /// current <see cref="Mode"/> will be used instead.
    /// </summary>
    public string AutoStartProfile { get; set; } = "multisplit";

    public static TunnelSettings Load(Context context)
    {
        var prefs = context.GetSharedPreferences("norkn_android", FileCreationMode.Private);
        return new TunnelSettings
        {
            SocksHost = prefs?.GetString(nameof(SocksHost), "127.0.0.1") ?? "127.0.0.1",
            SocksPort = prefs?.GetInt(nameof(SocksPort), 1080) ?? 1080,
            DnsServer = prefs?.GetString(nameof(DnsServer), "1.1.1.1") ?? "1.1.1.1",
            Mtu = prefs?.GetInt(nameof(Mtu), 1500) ?? 1500,
            FullTunnel = prefs?.GetBoolean(nameof(FullTunnel), true) ?? true,
            Mode = prefs?.GetString(nameof(Mode), "multisplit") ?? "multisplit",

            // Autostart settings with safe defaults. If the keys are missing they
            // default to false for the boolean and "multisplit" for the
            // profile.
            AutoStartOnBoot = prefs?.GetBoolean(nameof(AutoStartOnBoot), false) ?? false,
            AutoStartProfile = prefs?.GetString(nameof(AutoStartProfile), "multisplit") ?? "multisplit"
        };
    }

    public void Save(Context context)
    {
        var prefs = context.GetSharedPreferences("norkn_android", FileCreationMode.Private);
        var editor = prefs?.Edit();
        if (editor == null)
        {
            return;
        }

        editor.PutString(nameof(SocksHost), SocksHost);
        editor.PutInt(nameof(SocksPort), SocksPort);
        editor.PutString(nameof(DnsServer), DnsServer);
        editor.PutInt(nameof(Mtu), Mtu);
        editor.PutBoolean(nameof(FullTunnel), FullTunnel);
        editor.PutString(nameof(Mode), Mode);

        // Persist autostart configuration. If AutoStartOnBoot is true the
        // BootCompletedReceiver will start the service using AutoStartProfile.
        editor.PutBoolean(nameof(AutoStartOnBoot), AutoStartOnBoot);
        editor.PutString(nameof(AutoStartProfile), AutoStartProfile);
        editor.Apply();
    }
}

