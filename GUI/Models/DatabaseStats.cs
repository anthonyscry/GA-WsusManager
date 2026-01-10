namespace WsusManager.Models
{
    public class DatabaseStats
    {
        public double SizeMB { get; set; }
        public int UpdateCount { get; set; }
        public int SupersededCount { get; set; }
        public int DeclinedCount { get; set; }
        public int FileCount { get; set; }

        public string SizeDisplay => SizeMB >= 1024
            ? $"{SizeMB / 1024:F2} GB"
            : $"{SizeMB:F0} MB";
    }
}
