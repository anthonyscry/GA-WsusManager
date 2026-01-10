using System.Collections.Generic;

namespace WsusManager.Models
{
    public class OperationResult
    {
        public bool Success { get; set; }
        public string Message { get; set; } = string.Empty;
        public List<object> Details { get; set; } = new();
    }
}
