#include <core.p4>
#include <v1model.p4>

struct egress_metadata_t {
    bit<16> payload_length;
    bit<9>  smac_idx;
    bit<16> bd;
    bit<1>  inner_replica;
    bit<1>  replica;
    bit<48> mac_da;
    bit<1>  routed;
    bit<16> same_bd_check;
    bit<4>  header_count;
    bit<8>  drop_reason;
    bit<1>  egress_bypass;
    bit<8>  drop_exception;
}

header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

header ipv6_t {
    bit<4>   version;
    bit<8>   trafficClass;
    bit<20>  flowLabel;
    bit<16>  payloadLen;
    bit<8>   nextHdr;
    bit<8>   hopLimit;
    bit<128> srcAddr;
    bit<128> dstAddr;
}

struct metadata {
    @name("egress_metadata") 
    egress_metadata_t egress_metadata;
}

struct headers {
    @name("ethernet") 
    ethernet_t ethernet;
    @name("ipv4") 
    ipv4_t     ipv4;
    @name("ipv6") 
    ipv6_t     ipv6;
}

parser ParserImpl(packet_in packet, out headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
    @name("parse_ethernet") state parse_ethernet {
        packet.extract<ethernet_t>(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            16w0x800: parse_ipv4;
            16w0x86dd: parse_ipv6;
            default: accept;
        }
    }
    @name("parse_ipv4") state parse_ipv4 {
        packet.extract<ipv4_t>(hdr.ipv4);
        transition accept;
    }
    @name("parse_ipv6") state parse_ipv6 {
        packet.extract<ipv6_t>(hdr.ipv6);
        transition accept;
    }
    @name("start") state start {
        transition parse_ethernet;
    }
}

control ingress(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
    headers hdr_0;
    metadata meta_0;
    standard_metadata_t standard_metadata_0;
    action NoAction_1() {
    }
    action NoAction_2() {
    }
    @name("do_setup") action do_setup(bit<9> idx, bit<1> routed) {
        meta.egress_metadata.mac_da = hdr.ethernet.dstAddr;
        meta.egress_metadata.smac_idx = idx;
        meta.egress_metadata.routed = routed;
    }
    @name("setup") table setup_0() {
        actions = {
            do_setup();
            NoAction_1();
        }
        key = {
            hdr.ethernet.isValid(): exact;
        }
        default_action = NoAction_1();
    }
    @name("process_mac_rewrite.nop") action process_mac_rewrite_nop_0() {
    }
    @name("process_mac_rewrite.rewrite_ipv4_unicast_mac") action process_mac_rewrite_rewrite_ipv4_unicast_mac_0(bit<48> smac) {
        hdr_0.ethernet.srcAddr = smac;
        hdr_0.ethernet.dstAddr = meta_0.egress_metadata.mac_da;
        hdr_0.ipv4.ttl = hdr_0.ipv4.ttl + 8w255;
    }
    @name("process_mac_rewrite.rewrite_ipv4_multicast_mac") action process_mac_rewrite_rewrite_ipv4_multicast_mac_0(bit<48> smac) {
        hdr_0.ethernet.srcAddr = smac;
        hdr_0.ethernet.dstAddr[47:23] = 25w0x0;
        hdr_0.ipv4.ttl = hdr_0.ipv4.ttl + 8w255;
    }
    @name("process_mac_rewrite.rewrite_ipv6_unicast_mac") action process_mac_rewrite_rewrite_ipv6_unicast_mac_0(bit<48> smac) {
        hdr_0.ethernet.srcAddr = smac;
        hdr_0.ethernet.dstAddr = meta_0.egress_metadata.mac_da;
        hdr_0.ipv6.hopLimit = hdr_0.ipv6.hopLimit + 8w255;
    }
    @name("process_mac_rewrite.rewrite_ipv6_multicast_mac") action process_mac_rewrite_rewrite_ipv6_multicast_mac_0(bit<48> smac) {
        hdr_0.ethernet.srcAddr = smac;
        hdr_0.ethernet.dstAddr[47:32] = 16w0x0;
        hdr_0.ipv6.hopLimit = hdr_0.ipv6.hopLimit + 8w255;
    }
    @name("process_mac_rewrite.mac_rewrite") table process_mac_rewrite_mac_rewrite() {
        actions = {
            process_mac_rewrite_nop_0();
            process_mac_rewrite_rewrite_ipv4_unicast_mac_0();
            process_mac_rewrite_rewrite_ipv4_multicast_mac_0();
            process_mac_rewrite_rewrite_ipv6_unicast_mac_0();
            process_mac_rewrite_rewrite_ipv6_multicast_mac_0();
            NoAction_2();
        }
        key = {
            meta_0.egress_metadata.smac_idx: exact;
            hdr_0.ipv4.isValid()           : exact;
            hdr_0.ipv6.isValid()           : exact;
        }
        size = 512;
        default_action = NoAction_2();
    }
    action act() {
        hdr_0 = hdr;
        meta_0 = meta;
        standard_metadata_0 = standard_metadata;
    }
    action act_0() {
        hdr = hdr_0;
        meta = meta_0;
        standard_metadata = standard_metadata_0;
    }
    table tbl_act() {
        actions = {
            act();
        }
        const default_action = act();
    }
    table tbl_act_0() {
        actions = {
            act_0();
        }
        const default_action = act_0();
    }
    apply {
        setup_0.apply();
        tbl_act.apply();
        if (meta_0.egress_metadata.routed == 1w1) 
            process_mac_rewrite_mac_rewrite.apply();
        tbl_act_0.apply();
    }
}

control egress(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
    apply {
    }
}

control DeparserImpl(packet_out packet, in headers hdr) {
    apply {
        packet.emit<ethernet_t>(hdr.ethernet);
        packet.emit<ipv6_t>(hdr.ipv6);
        packet.emit<ipv4_t>(hdr.ipv4);
    }
}

control verifyChecksum(in headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
    apply {
    }
}

control computeChecksum(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
    apply {
    }
}

V1Switch<headers, metadata>(ParserImpl(), verifyChecksum(), ingress(), egress(), computeChecksum(), DeparserImpl()) main;
