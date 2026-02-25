using Android.App;
using Android.Runtime;

namespace NoRKN.Android;

[Application]
public sealed class NoRknApplication : Application
{
    public NoRknApplication(IntPtr handle, JniHandleOwnership ownerShip) : base(handle, ownerShip)
    {
    }

    public override void OnCreate()
    {
        base.OnCreate();

        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            try
            {
                var ex = e.ExceptionObject as Exception;
                global::Android.Util.Log.Error("NoRKN", $"UnhandledException: {ex}");
            }
            catch
            {
                // ignored
            }
        };

        TaskScheduler.UnobservedTaskException += (_, e) =>
        {
            try
            {
                global::Android.Util.Log.Error("NoRKN", $"UnobservedTaskException: {e.Exception}");
            }
            catch
            {
                // ignored
            }

            e.SetObserved();
        };

        AndroidEnvironment.UnhandledExceptionRaiser += (_, e) =>
        {
            try
            {
                global::Android.Util.Log.Error("NoRKN", $"AndroidUnhandledException: {e.Exception}");
            }
            catch
            {
                // ignored
            }

            e.Handled = true;
        };
    }
}
