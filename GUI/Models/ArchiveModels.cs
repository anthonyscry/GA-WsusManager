using System.Collections.Generic;

namespace WsusManager.Models
{
    public class ArchiveYear
    {
        public string Year { get; set; } = string.Empty;
        public string Path { get; set; } = string.Empty;
        public List<ArchiveMonth> Months { get; set; } = new();
    }

    public class ArchiveMonth
    {
        public string Name { get; set; } = string.Empty;
        public string Path { get; set; } = string.Empty;
        public int BackupCount { get; set; }
        public List<ArchiveBackup> Backups { get; set; } = new();
    }

    public class ArchiveBackup
    {
        public string Name { get; set; } = string.Empty;
        public string Path { get; set; } = string.Empty;
        public long SizeBytes { get; set; }
        public bool HasDatabase { get; set; }
        public bool HasContent { get; set; }

        public string SizeDisplay
        {
            get
            {
                if (SizeBytes >= 1024L * 1024 * 1024)
                    return $"{SizeBytes / (1024.0 * 1024 * 1024):F2} GB";
                if (SizeBytes >= 1024 * 1024)
                    return $"{SizeBytes / (1024.0 * 1024):F2} MB";
                if (SizeBytes > 0)
                    return $"{SizeBytes / 1024.0:F2} KB";
                return "Unknown";
            }
        }
    }
}
