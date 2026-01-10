namespace WsusManager.Models
{
    public class DiskSpaceInfo
    {
        public double FreeGB { get; set; }
        public double UsedGB { get; set; }
        public double TotalGB { get; set; }
        public double PercentUsed { get; set; }

        public string FreeDisplay => $"{FreeGB:F1} GB free";
        public string UsedDisplay => $"{UsedGB:F1} GB used";
        public string TotalDisplay => $"{TotalGB:F1} GB total";

        public bool IsLow => PercentUsed >= 90;
        public bool IsWarning => PercentUsed >= 75 && PercentUsed < 90;
    }
}
