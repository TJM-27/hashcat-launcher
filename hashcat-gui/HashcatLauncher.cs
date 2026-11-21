using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class HashcatLauncher
{
    [STAThread]
    private static int Main()
    {
        string appDirectory = AppDomain.CurrentDomain.BaseDirectory;
        string scriptPath = Path.Combine(appDirectory, "hashcat_gui.ps1");

        if (!File.Exists(scriptPath))
        {
            MessageBox.Show(
                "hashcat_gui.ps1 was not found next to Hashcat Launcher.exe.",
                "Hashcat launcher",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }

        string escapedScriptPath = scriptPath.Replace("\"", "\\\"");
        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -File \"" + escapedScriptPath + "\"",
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
            WorkingDirectory = appDirectory
        };

        try
        {
            Process.Start(startInfo);
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "Unable to start Hashcat launcher:" + Environment.NewLine + ex.Message,
                "Hashcat launcher",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
    }
}
