using System.Diagnostics;
using Microsoft.Win32;

namespace ZapretGlassGui;

/// <summary>
/// Windows Service installation helper for NoRKN
/// Creates a scheduled task that runs on system startup
/// </summary>
public static class ServiceInstaller
{
    private const string ServiceName = "NoRKNBypassService";
    private const string DisplayName = "NoRKN DPI Bypass Service";

    /// <summary>
    /// Install NoRKN as an auto-starting service using Windows Task Scheduler
    /// </summary>
    public static (bool success, string message) InstallService(string appRoot, string mode = "multisplit")
    {
        try
        {
            // Check if already installed
            if (ServiceExists())
            {
                return (false, "Service already installed. Remove it first.");
            }

            // Get the path to the GUI application
            var appPath = Path.Combine(appRoot, "NoRKN.exe");
            if (!File.Exists(appPath))
            {
                return (false, $"Application not found: {appPath}");
            }

            // Save configuration to registry
            SaveServiceConfig(appRoot, mode);

            // Create scheduled task using schtasks.exe
            // The task will run at startup with SYSTEM privileges
            var result = RunCommand(
                "schtasks.exe",
                new[]
                {
                    "/Create",
                    "/F",
                    "/TN", ServiceName,
                    "/SC", "ONSTART",
                    "/RL", "HIGHEST",
                    "/RU", "SYSTEM",
                    "/TR", $"\"{appPath}\" /service /mode:{mode}"
                });

            if (!result.success)
            {
                return (false, $"Failed to create scheduled task: {result.message}");
            }

            return (true, $"Service installed successfully.\nMode: {mode}\n\nThe bypass will now start automatically on system startup.");
        }
        catch (Exception ex)
        {
            return (false, $"Error installing service: {ex.Message}");
        }
    }

    /// <summary>
    /// Remove NoRKN Windows service (scheduled task)
    /// </summary>
    public static (bool success, string message) RemoveService()
    {
        try
        {
            // Check if service exists
            if (!ServiceExists())
            {
                return (false, "Service is not installed.");
            }

            // Delete the scheduled task
            var result = RunCommand(
                "schtasks.exe",
                new[] { "/Delete", "/F", "/TN", ServiceName });

            if (!result.success)
            {
                var all = result.message;
                var notFound =
                    all.Contains("cannot find", StringComparison.OrdinalIgnoreCase) ||
                    all.Contains("не удается найти", StringComparison.OrdinalIgnoreCase) ||
                    all.Contains("не найден", StringComparison.OrdinalIgnoreCase);
                if (!notFound)
                {
                    return (false, $"Failed to delete scheduled task: {result.message}");
                }
            }

            return (true, "Service removed successfully.");
        }
        catch (Exception ex)
        {
            return (false, $"Error removing service: {ex.Message}");
        }
    }

    /// <summary>
    /// Check if service is installed
    /// </summary>
    public static bool ServiceExists()
    {
        try
        {
            var result = RunCommand(
                "schtasks.exe",
                new[] { "/Query", "/TN", ServiceName });

            return result.success;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Get service status (Running, Stopped, etc)
    /// </summary>
    public static string GetServiceStatus()
    {
        try
        {
            var result = RunCommand(
                "schtasks.exe",
                new[] { "/Query", "/TN", ServiceName, "/V" });

            if (!result.success)
            {
                return "Not installed";
            }

            // Parse output to get status
            var output = result.message;
            if (output.Contains("Ready", StringComparison.OrdinalIgnoreCase))
            {
                return "Ready";
            }
            if (output.Contains("Running", StringComparison.OrdinalIgnoreCase))
            {
                return "Running";
            }

            return "Active";
        }
        catch
        {
            return "Unknown";
        }
    }

    /// <summary>
    /// Start the service immediately
    /// </summary>
    public static (bool success, string message) StartService()
    {
        return RunCommand(
            "schtasks.exe",
            new[] { "/Run", "/TN", ServiceName });
    }

    /// <summary>
    /// Stop the service
    /// </summary>
    public static (bool success, string message) StopService()
    {
        return RunCommand(
            "taskkill.exe",
            new[] { "/F", "/IM", "NoRKN.exe" });
    }

    /// <summary>
    /// Save service configuration to registry
    /// </summary>
    private static void SaveServiceConfig(string appRoot, string mode)
    {
        try
        {
            using var key = Registry.LocalMachine.CreateSubKey(@"Software\NoRKN");
            key?.SetValue("AppRoot", appRoot, RegistryValueKind.String);
            key?.SetValue("ServiceMode", mode, RegistryValueKind.String);
            key?.Close();
        }
        catch { }
    }

    /// <summary>
    /// Run a command and capture output
    /// </summary>
    private static (bool success, string message) RunCommand(string fileName, IEnumerable<string> arguments)
    {
        try
        {
            using var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = fileName,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                    StandardOutputEncoding = System.Text.Encoding.UTF8,
                    StandardErrorEncoding = System.Text.Encoding.UTF8
                }
            };

            foreach (var arg in arguments)
            {
                process.StartInfo.ArgumentList.Add(arg);
            }

            process.Start();
            var output = process.StandardOutput.ReadToEnd();
            var error = process.StandardError.ReadToEnd();
            process.WaitForExit();

            var message = string.IsNullOrWhiteSpace(error) ? output : error;
            return (process.ExitCode == 0, message);
        }
        catch (Exception ex)
        {
            return (false, ex.Message);
        }
    }
}
