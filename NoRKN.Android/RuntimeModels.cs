namespace NoRKN.Android;

public enum VpnStateCode
{
    Idle = 0,
    Starting = 1,
    Running = 2,
    Stopping = 3,
    Stopped = 4,
    VpnEstablishFail = 10,
    EngineInitFail = 11,
    DnsFail = 12,
    UdpPathFail = 13,
    Error = 99
}

public sealed class DpiEngineCounters
{
    public long BytesUp { get; set; }
    public long BytesDown { get; set; }
    public long PacketsUp { get; set; }
    public long PacketsDown { get; set; }
    public long ActiveConnections { get; set; }
    public long TotalConnections { get; set; }
    public long PktsPerSecond { get; set; }
    public long BytesPerSecond { get; set; }
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DpiEngineCounters Clone()
    {
        return new DpiEngineCounters
        {
            BytesUp = BytesUp,
            BytesDown = BytesDown,
            PacketsUp = PacketsUp,
            PacketsDown = PacketsDown,
            ActiveConnections = ActiveConnections,
            TotalConnections = TotalConnections,
            PktsPerSecond = PktsPerSecond,
            BytesPerSecond = BytesPerSecond,
            UpdatedAt = UpdatedAt
        };
    }
}

public sealed class VpnRuntimeState
{
    public bool IsRunning { get; set; }
    public string Mode { get; set; } = "-";
    public string VpnState { get; set; } = "stopped";
    public string EngineState { get; set; } = "stopped";
    public string ActiveStrategy { get; set; } = "-";
    public bool QuicFallback { get; set; }
    public VpnStateCode Code { get; set; } = VpnStateCode.Idle;
    public string LastError { get; set; } = string.Empty;
    public DpiEngineCounters Counters { get; set; } = new();
}

