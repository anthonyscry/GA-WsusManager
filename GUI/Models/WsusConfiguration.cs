namespace WsusManager.Models
{
    public class WsusConfiguration
    {
        public string ContentPath { get; set; } = "C:\\WSUS";
        public string SqlInstance { get; set; } = ".\\SQLEXPRESS";
        public string ExportPath { get; set; } = string.Empty;
        public string LogPath { get; set; } = "C:\\WSUS\\Logs";
        public string DefaultArchivePath { get; set; } = "\\\\lab-hyperv\\d\\WSUS-Exports";
    }
}
