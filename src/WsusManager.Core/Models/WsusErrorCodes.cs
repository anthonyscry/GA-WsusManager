namespace WsusManager.Core.Models;

/// <summary>
/// Static dictionary of common WSUS and Windows Update error codes with descriptions
/// and recommended fixes. Used by the error-code lookup feature (CLI-06).
///
/// Keys are uppercase hex codes without the "0x" prefix (e.g., "80244010").
/// The <see cref="Lookup"/> method accepts either format.
/// </summary>
public static class WsusErrorCodes
{
    private static readonly Dictionary<string, WsusErrorInfo> _codes =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["80244010"] = new WsusErrorInfo
            {
                Code = "0x80244010",
                HexCode = "80244010",
                Description = "WU_E_PT_EXCEEDED_MAX_SERVER_TRIPS — The number of round trips to the server exceeded the maximum limit.",
                RecommendedFix = "Check for excessive pending updates or a misconfigured WSUS server. Run 'wuauclt /resetauthorization /detectnow' on the client. If the problem persists, check WSUS server load and consider running the WSUS Server Cleanup Wizard."
            },
            ["8024402C"] = new WsusErrorInfo
            {
                Code = "0x8024402C",
                HexCode = "8024402C",
                Description = "WU_E_PT_WINHTTP_NAME_NOT_RESOLVED — The proxy server or target server name cannot be resolved.",
                RecommendedFix = "Verify DNS resolution for the WSUS server hostname. Check proxy settings with 'netsh winhttp show proxy'. Ensure the WSUS server FQDN is resolvable from the client. On air-gapped networks, verify local DNS or HOSTS file entries."
            },
            ["80244017"] = new WsusErrorInfo
            {
                Code = "0x80244017",
                HexCode = "80244017",
                Description = "WU_E_PT_HTTP_STATUS_DENIED — The WSUS server responded with HTTP 401 (Access Denied) during the update session.",
                RecommendedFix = "The WSUS server's identity changed mid-session. Re-run detection: 'wuauclt /resetauthorization /detectnow'. If using HTTPS, verify the server certificate has not changed. Check IIS authentication settings on the WSUS server."
            },
            ["8024401C"] = new WsusErrorInfo
            {
                Code = "0x8024401C",
                HexCode = "8024401C",
                Description = "WU_E_PT_HTTP_STATUS_PROXY_AUTH_REQ — The proxy server requires authentication.",
                RecommendedFix = "Configure proxy authentication in Internet Explorer or WinHTTP proxy settings. Run 'netsh winhttp set proxy proxy-server=\"<server>:<port>\" bypass-list=\"<local>\"'. If the proxy requires credentials, configure them via Group Policy or registry."
            },
            ["80070005"] = new WsusErrorInfo
            {
                Code = "0x80070005",
                HexCode = "80070005",
                Description = "E_ACCESSDENIED — Access is denied. The Windows Update service lacks permission to access a required resource.",
                RecommendedFix = "Run 'net stop wuauserv && net start wuauserv' to restart the service. Check permissions on C:\\Windows\\SoftwareDistribution. Run 'icacls C:\\Windows\\SoftwareDistribution /reset /T'. Verify the SYSTEM account has full control."
            },
            ["80072EE2"] = new WsusErrorInfo
            {
                Code = "0x80072EE2",
                HexCode = "80072EE2",
                Description = "WININET_E_TIMEOUT — The operation timed out. The WSUS server is unreachable or responding too slowly.",
                RecommendedFix = "Verify the WSUS server is running (check IIS and WSUS services). Test connectivity: 'Test-NetConnection -ComputerName <wsus-server> -Port 8530'. Check firewall rules on both client and server. Increase WUA timeout via registry if needed."
            },
            ["80072EFD"] = new WsusErrorInfo
            {
                Code = "0x80072EFD",
                HexCode = "80072EFD",
                Description = "WININET_E_CANNOT_CONNECT — A connection to the WSUS server could not be established.",
                RecommendedFix = "Verify WSUS server and IIS are running. Test port connectivity: 'Test-NetConnection -ComputerName <wsus-server> -Port 8530'. Check Windows Firewall rules. Verify the WUServer registry value points to the correct URL and port."
            },
            ["80072F8F"] = new WsusErrorInfo
            {
                Code = "0x80072F8F",
                HexCode = "80072F8F",
                Description = "WININET_E_DECODING_FAILED — A security error occurred. Usually an SSL/TLS certificate problem.",
                RecommendedFix = "Check the WSUS server certificate: verify it is not expired, is trusted by the client, and the CN/SAN matches the server name. Run 'certmgr.msc' on the client to inspect trusted root CAs. If using a self-signed cert, deploy it to the client's Trusted Root store via GPO."
            },
            ["8024D009"] = new WsusErrorInfo
            {
                Code = "0x8024D009",
                HexCode = "8024D009",
                Description = "WU_E_SETUP_SKIP_UPDATE — An update to the Windows Update Agent was skipped due to a directive in the wuident.cab file.",
                RecommendedFix = "The Windows Update Agent needs updating. Run 'wuauclt /updatenow' or download the latest WUA from Microsoft. In a WSUS environment, approve the Windows Update Agent update in the WSUS console."
            },
            ["80240022"] = new WsusErrorInfo
            {
                Code = "0x80240022",
                HexCode = "80240022",
                Description = "WU_E_ALL_UPDATES_FAILED — Operation failed for all the updates.",
                RecommendedFix = "Run Windows Update Troubleshooter. Clear the SoftwareDistribution folder: stop wuauserv, delete C:\\Windows\\SoftwareDistribution\\Download contents, restart wuauserv. Check individual update error codes in WindowsUpdate.log."
            },
            ["8024A000"] = new WsusErrorInfo
            {
                Code = "0x8024A000",
                HexCode = "8024A000",
                Description = "WU_E_AU_NOSERVICE — Automatic Updates was unable to service incoming requests because the service is not running.",
                RecommendedFix = "Start the Windows Update service: 'net start wuauserv'. Verify the service is set to Automatic startup: 'sc config wuauserv start= auto'. Check for dependency service failures (cryptsvc, bits)."
            },
            ["8024000B"] = new WsusErrorInfo
            {
                Code = "0x8024000B",
                HexCode = "8024000B",
                Description = "WU_E_CALL_CANCELLED — Operation was cancelled by the user.",
                RecommendedFix = "The operation was intentionally cancelled. Re-run the update check or installation. If this occurs automatically without user interaction, check for Group Policy settings that might be cancelling updates."
            },
            ["80244019"] = new WsusErrorInfo
            {
                Code = "0x80244019",
                HexCode = "80244019",
                Description = "WU_E_PT_HTTP_STATUS_NOT_FOUND — HTTP 404. The WSUS server URL returned a Not Found response.",
                RecommendedFix = "Verify the WUServer registry value has the correct URL and port. Check that the WSUS IIS application is running and the /ClientWebService virtual directory exists. Run 'iisreset' on the WSUS server if needed."
            },
            ["80070002"] = new WsusErrorInfo
            {
                Code = "0x80070002",
                HexCode = "80070002",
                Description = "ERROR_FILE_NOT_FOUND — A required file is missing. Often indicates SoftwareDistribution database corruption.",
                RecommendedFix = "Reset the SoftwareDistribution folder: 'net stop wuauserv && net stop bits', rename C:\\Windows\\SoftwareDistribution to SoftwareDistribution.old, 'net start wuauserv && net start bits'. Force re-detection: 'wuauclt /resetauthorization /detectnow'."
            },
            ["800B0109"] = new WsusErrorInfo
            {
                Code = "0x800B0109",
                HexCode = "800B0109",
                Description = "CERT_E_UNTRUSTEDROOT — A certificate chain processed but terminated in a root certificate that is not trusted by the trust provider.",
                RecommendedFix = "The WSUS server's certificate chain is not trusted by the client. Deploy the root CA certificate to the client's Trusted Root Certification Authorities store via GPO. Verify the full certificate chain is valid and not expired."
            },
            ["8024401A"] = new WsusErrorInfo
            {
                Code = "0x8024401A",
                HexCode = "8024401A",
                Description = "WU_E_PT_HTTP_STATUS_BAD_METHOD — The WSUS server returned an HTTP error indicating the request method is not allowed.",
                RecommendedFix = "Check IIS configuration on the WSUS server — verify the WSUS web application and its virtual directories are properly configured. Run 'wsusutil checkhealth' on the WSUS server. Reinstall WSUS IIS components if needed."
            },
            ["80240016"] = new WsusErrorInfo
            {
                Code = "0x80240016",
                HexCode = "80240016",
                Description = "WU_E_INSTALL_NOT_ALLOWED — Operation tried to install while another installation was in progress or the system was pending a mandatory restart.",
                RecommendedFix = "Restart the computer to clear the pending reboot state. Check for other running installers (MSI, Windows Installer service). After reboot, trigger a new update scan."
            },
            ["80244007"] = new WsusErrorInfo
            {
                Code = "0x80244007",
                HexCode = "80244007",
                Description = "WU_E_PT_SOAPCLIENT_SOAPFAULT — SOAP client SOAP fault error. The WSUS server returned an unexpected HTTP status code.",
                RecommendedFix = "Check WSUS server event logs for SOAP service errors. Verify the WSUS server has sufficient disk space and memory. Run WSUS Server Cleanup Wizard. Restart the WSUS service and IIS application pool."
            },
            ["8024D007"] = new WsusErrorInfo
            {
                Code = "0x8024D007",
                HexCode = "8024D007",
                Description = "WU_E_SETUP_REGISTRATION_FAILED — Windows Update Agent could not be updated because regsvr32.exe returned an error.",
                RecommendedFix = "Re-register Windows Update DLLs: run 'regsvr32 wuapi.dll', 'regsvr32 wuaueng.dll', 'regsvr32 wucltux.dll', 'regsvr32 wups.dll', 'regsvr32 wups2.dll'. If that fails, repair Windows Update Agent via Windows Update Standalone Installer."
            },
            ["80248007"] = new WsusErrorInfo
            {
                Code = "0x80248007",
                HexCode = "80248007",
                Description = "WU_E_DS_NODATA — The information requested is not in the data store. Update metadata download failed.",
                RecommendedFix = "Clear the Windows Update cache: stop wuauserv, delete C:\\Windows\\SoftwareDistribution\\DataStore, restart wuauserv. Force re-synchronization: 'wuauclt /resetauthorization /detectnow'. Check WSUS server synchronization status."
            }
        };

    /// <summary>
    /// Gets the read-only dictionary of all known error codes.
    /// Key is the uppercase hex code without "0x" prefix (e.g., "80244010").
    /// </summary>
    public static IReadOnlyDictionary<string, WsusErrorInfo> All => _codes;

    /// <summary>
    /// Looks up a WSUS/Windows Update error code and returns the associated info.
    /// </summary>
    /// <param name="input">
    /// Hex code in any of these formats:
    /// <list type="bullet">
    ///   <item>"0x80244010" (canonical hex with prefix)</item>
    ///   <item>"80244010" (hex without prefix)</item>
    ///   <item>"-2145107952" (signed decimal, as shown in some logs)</item>
    ///   <item>"2149859344" (unsigned decimal)</item>
    /// </list>
    /// </param>
    /// <returns>The <see cref="WsusErrorInfo"/> if found; otherwise <c>null</c>.</returns>
    public static WsusErrorInfo? Lookup(string? input)
    {
        if (string.IsNullOrWhiteSpace(input))
            return null;

        input = input.Trim();

        // Strip "0x" or "0X" prefix
        string hexKey = input.StartsWith("0x", StringComparison.OrdinalIgnoreCase)
            ? input[2..]
            : input;

        // Direct hex lookup
        if (_codes.TryGetValue(hexKey, out var info))
            return info;

        // Try parsing as decimal (signed or unsigned) and converting to hex
        if (long.TryParse(input, out long decimalValue))
        {
            // Convert to unsigned 32-bit hex representation
            string fromDecimal = ((uint)decimalValue).ToString("X8");
            if (_codes.TryGetValue(fromDecimal, out info))
                return info;
        }

        return null;
    }
}
