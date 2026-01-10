namespace WsusManager.Models
{
    public class ServiceStatus
    {
        public string Name { get; set; } = string.Empty;
        public string DisplayName { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public bool IsRunning { get; set; }
    }
}
