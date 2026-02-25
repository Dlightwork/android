namespace NoRKN.Android;

public sealed class PacketProcessor
{
    private readonly string _mode;
    private readonly Action<string> _log;
    private long _packetCount;

    public PacketProcessor(string mode, Action<string> log)
    {
        _mode = mode;
        _log = log;
    }

    public void Process(byte[] packet, int length)
    {
        if (length < 20)
        {
            return;
        }

        _packetCount++;
        if (_packetCount % 500 == 0)
        {
            _log($"packets observed: {_packetCount}");
        }

        var version = (packet[0] >> 4) & 0x0F;
        if (version != 4)
        {
            return;
        }

        var protocol = packet[9];
        if (protocol == 6)
        {
            ProcessTcp(packet, length);
        }
        else if (protocol == 17)
        {
            ProcessUdp(packet, length);
        }
    }

    private void ProcessTcp(byte[] packet, int length)
    {
        var ihl = (packet[0] & 0x0F) * 4;
        if (length < ihl + 20)
        {
            return;
        }

        var dstPort = (packet[ihl + 2] << 8) | packet[ihl + 3];
        if (dstPort != 443)
        {
            return;
        }

        if (_mode.Equals("multisplit", StringComparison.OrdinalIgnoreCase))
        {
            // Strategy hook for multisplit profile.
            // Real mutation is expected in native tun2socks forwarding core.
            return;
        }

        if (_mode.Equals("strong", StringComparison.OrdinalIgnoreCase))
        {
            // Strategy hook for strong profile.
            // Real mutation is expected in native tun2socks forwarding core.
            return;
        }
    }

    private void ProcessUdp(byte[] packet, int length)
    {
        var ihl = (packet[0] & 0x0F) * 4;
        if (length < ihl + 8)
        {
            return;
        }

        var dstPort = (packet[ihl + 2] << 8) | packet[ihl + 3];
        if (dstPort != 443)
        {
            return;
        }

        // Strategy hook for QUIC handling.
        // Real mutation is expected in native tun2socks forwarding core.
    }
}
