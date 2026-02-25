using Android.App;
using Android.Content;

namespace NoRKN.Android;

/// <summary>
/// Handles system boot completion broadcasts and optionally starts the VPN
/// service if the user has enabled the autostart setting. When the device
/// boots this receiver loads the stored <see cref="TunnelSettings"/> and,
/// if <see cref="TunnelSettings.AutoStartOnBoot"/> is true, it starts
/// <see cref="NorknVpnService"/> with the configured profile.
/// </summary>
[BroadcastReceiver(Enabled = true, Exported = true)]
[IntentFilter(new[] { Intent.ActionBootCompleted, Intent.ActionLockedBootCompleted })]
public sealed class BootCompletedReceiver : BroadcastReceiver
{
    public override void OnReceive(Context? context, Intent? intent)
    {
        if (context == null)
        {
            return;
        }

        // Ensure we're handling the correct broadcast. On some devices both
        // BOOT_COMPLETED and LOCKED_BOOT_COMPLETED may be delivered.
        var action = intent?.Action;
        if (action != Intent.ActionBootCompleted && action != Intent.ActionLockedBootCompleted)
        {
            return;
        }

        // Load persisted settings. If no settings exist this will return
        // defaults defined in TunnelSettings.
        var settings = TunnelSettings.Load(context);
        if (!settings.AutoStartOnBoot)
        {
            // Autostart disabled; do nothing.
            return;
        }

        // Determine which profile (mode) to start with. If AutoStartProfile
        // hasn't been set explicitly fall back to the current Mode value.
        var profile = settings.AutoStartProfile;
        if (string.IsNullOrWhiteSpace(profile))
        {
            profile = settings.Mode;
        }

        // Construct an intent to start the VPN service. Use the profile
        // constants so both legacy and new keys are honoured by the service.
        var startIntent = new Intent(context, typeof(NorknVpnService));
        // Set an explicit action. We reuse ActionStart here rather than
        // defining a new action; the service treats missing action as a
        // request to start and uses extras to configure itself. The
        // ActionStartProfile constant is defined for completeness but not
        // strictly necessary.
        startIntent.SetAction(NorknVpnService.ActionStart);
        // Provide the selected profile via both keys. The service reads
        // ExtraMode and ExtraProfile interchangeably.
        startIntent.PutExtra(NorknVpnService.ExtraMode, profile);
        startIntent.PutExtra(NorknVpnService.ExtraProfile, profile);

        // Android 8.0+ requires that we start services in the foreground
        // context when responding to broadcasts. StartService will
        // automatically promote the service to the foreground when it begins.
        context.StartService(startIntent);
    }
}
