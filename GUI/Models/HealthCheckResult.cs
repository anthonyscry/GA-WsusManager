using System.Collections.Generic;

namespace WsusManager.Models
{
    public class HealthCheckResult
    {
        public bool Success { get; set; }
        public List<HealthCheck> Checks { get; set; } = new();
    }

    public class HealthCheck
    {
        public string Name { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public string Message { get; set; } = string.Empty;

        public bool IsSuccess => Status.ToLower() == "pass" || Status.ToLower() == "ok" || Status.ToLower() == "success";
        public bool IsWarning => Status.ToLower() == "warning" || Status.ToLower() == "warn";
        public bool IsError => Status.ToLower() == "fail" || Status.ToLower() == "error" || Status.ToLower() == "failed";
    }
}
