namespace NoRKN.Android;

public sealed class LocalSocksCounters
{
    public long BytesUp { get; set; }
    public long BytesDown { get; set; }
    public long PacketsUp { get; set; }
    public long PacketsDown { get; set; }
    public long ActiveConnections { get; set; }
    public long TotalConnections { get; set; }
}
