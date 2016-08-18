#include <core.p4>

extern Checksum16 {
    void clear();
    void update<D>(in D dt);
    void update<D>(in bool condition, in D dt);
    bit<16> get();
}

typedef bit<4> PortId_t;
struct InControl {
    PortId_t inputPort;
}

struct OutControl {
    PortId_t outputPort;
}

parser Parser<H>(packet_in b, out H parsedHeaders);
control MAP<H>(inout H headers, in error parseError, in InControl inCtrl, out OutControl outCtrl);
control Deparser<H>(inout H outputHeaders, packet_out b);
package Simple<H>(Parser<H> p, MAP<H> map, Deparser<H> d);
@ethernetaddress typedef bit<48> EthernetAddress;
@ipv4address typedef bit<32> IPv4Address;
header Ethernet_h {
    EthernetAddress dstAddr;
    EthernetAddress srcAddr;
    bit<16>         etherType;
}

header IPv4_h {
    bit<4>      version;
    bit<4>      ihl;
    bit<8>      diffserv;
    bit<16>     totalLen;
    bit<16>     identification;
    bit<3>      flags;
    bit<13>     fragOffset;
    bit<8>      ttl;
    bit<8>      protocol;
    bit<16>     hdrChecksum;
    IPv4Address srcAddr;
    IPv4Address dstAddr;
}

error {
    IPv4IncorrectVersion,
    IPv4OptionsNotSupported,
    IPv4ChecksumError
}

struct Parsed_packet {
    Ethernet_h ethernet;
    IPv4_h     ip;
}

parser TopParser(packet_in b, out Parsed_packet p) {
    Checksum16() ck;
    state start {
        b.extract<Ethernet_h>(p.ethernet);
        transition select(p.ethernet.etherType) {
            16w0x800: parse_ipv4;
        }
    }
    state parse_ipv4 {
        b.extract<IPv4_h>(p.ip);
        verify(p.ip.version == 4w4, IPv4IncorrectVersion);
        verify(p.ip.ihl == 4w5, IPv4OptionsNotSupported);
        ck.clear();
        ck.update<IPv4_h>(p.ip);
        verify(ck.get() == 16w0, IPv4ChecksumError);
        transition accept;
    }
}

control Pipe(inout Parsed_packet headers, in error parseError, in InControl inCtrl, out OutControl outCtrl) {
    action Drop_action() {
        outCtrl.outputPort = 4w0xf;
    }
    action Set_nhop(out IPv4Address nextHop, IPv4Address ipv4_dest, PortId_t port) {
        nextHop = ipv4_dest;
        headers.ip.ttl = headers.ip.ttl + 8w255;
        outCtrl.outputPort = port;
    }
    table ipv4_match(out IPv4Address nextHop) {
        key = {
            headers.ip.dstAddr: lpm;
        }
        actions = {
            Set_nhop(nextHop);
            Drop_action();
        }
        size = 1024;
        default_action = Drop_action();
    }
    action Send_to_cpu() {
        outCtrl.outputPort = 4w0xe;
    }
    table check_ttl() {
        key = {
            headers.ip.ttl: exact;
        }
        actions = {
            Send_to_cpu();
            NoAction();
        }
        const default_action = NoAction();
    }
    action Set_dmac(EthernetAddress dmac) {
        headers.ethernet.dstAddr = dmac;
    }
    table dmac(in IPv4Address nextHop) {
        key = {
            nextHop: exact;
        }
        actions = {
            Set_dmac();
            Drop_action();
        }
        size = 1024;
        default_action = Drop_action();
    }
    action Rewrite_smac(EthernetAddress sourceMac) {
        headers.ethernet.srcAddr = sourceMac;
    }
    table smac() {
        key = {
            outCtrl.outputPort: exact;
        }
        actions = {
            Drop_action();
            Rewrite_smac();
        }
        size = 16;
        default_action = Drop_action();
    }
    apply {
        if (parseError != NoError) {
            Drop_action();
            return;
        }
        IPv4Address nextHop;
        ipv4_match.apply(nextHop);
        if (outCtrl.outputPort == 4w0xf) 
            return;
        check_ttl.apply();
        if (outCtrl.outputPort == 4w0xe) 
            return;
        dmac.apply(nextHop);
        if (outCtrl.outputPort == 4w0xf) 
            return;
        smac.apply();
    }
}

control TopDeparser(inout Parsed_packet p, packet_out b) {
    Checksum16() ck;
    apply {
        b.emit<Ethernet_h>(p.ethernet);
        if (p.ip.isValid()) {
            ck.clear();
            p.ip.hdrChecksum = 16w0;
            ck.update<IPv4_h>(p.ip);
            p.ip.hdrChecksum = ck.get();
            b.emit<IPv4_h>(p.ip);
        }
    }
}

Simple<Parsed_packet>(TopParser(), Pipe(), TopDeparser()) main;
