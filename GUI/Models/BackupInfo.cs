using System;

namespace WsusManager.Models
{
    public class BackupInfo
    {
        public string Name { get; set; } = string.Empty;
        public string FullPath { get; set; } = string.Empty;
        public long SizeBytes { get; set; }
        public DateTime Created { get; set; }

        public string SizeDisplay
        {
            get
            {
                if (SizeBytes >= 1024 * 1024 * 1024)
                    return $"{SizeBytes / (1024.0 * 1024 * 1024):F2} GB";
                if (SizeBytes >= 1024 * 1024)
                    return $"{SizeBytes / (1024.0 * 1024):F2} MB";
                return $"{SizeBytes / 1024.0:F2} KB";
            }
        }
    }
}
