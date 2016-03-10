package require bitnary

namespace eval asciipacket {
    proc assert {expr} {    ;# for "static" assertions that throw nice errors
        if {![uplevel 1 [list expr $expr]]} {
            raise {ASSERT ERROR} "{$expr} {[subst -noc $expr]}"
        }
    }
 
    proc b2h {data} {       ;# format a binary string in hex digits
        binary scan $data H* hex; set hex
    }
 
    proc parse {s} {
        set result {}                       ;# we will return a dictionary
        set s [string trim $s]              ;# remove whitespace
        set s [split $s \n]                 ;# split into lines
        set s [lmap x $s {string trim $x}]  ;# trim whitespace from each line
        set s [lassign $s border0]          ;# pop off top border row
                                            ;# calculate chars per row, chars per bit
        set rowlen [llength [string map {+ \ } $border0]]
        set bitlen [expr {([string length $border0] - 1) / $rowlen}]
        assert {$bitlen * $rowlen + 1 == [string length $border0]}
 
        foreach {row border} $s {
            assert {$border eq $border0}
            set row [string trim $row |]
            foreach field [split $row |] {
                set len [string length |$field]
                assert {$len % $bitlen == 0}
                set name [string trim $field]
                set nbits [expr {$len / $bitlen}]
                assert {![dict exists $result $name]}
                dict set result $name $nbits
            }
        }
        return $result
    }
 
    proc encode {schema values} {
        set bincodes {1 B 8 c 16 S 32 W}    ;# see binary(n)
        set binfmt ""                       ;# format string
        set binargs ""                      ;# positional args
        dict for {name bitlen} $schema {
            set val [dict get $values $name]
            if {[dict exists $bincodes $bitlen]} {
                set fmt "[dict get $bincodes $bitlen]"
            } else {
                set fmt "B${bitlen}"
            }
            append binfmt $fmt
            lappend binargs $val
        }
        bitnary format $binfmt {*}$binargs
    }
 
 
    proc decode {schema data} {
        set result   {}                     ;# we will return a dict
        set bincodes {1 B 8 c 16 S 32 W}    ;# see binary(n)
        set binfmt   ""                     ;# format string
        set binargs  ""                     ;# positional args
        dict for {name bitlen} $schema {
            if {[dict exists $bincodes $bitlen]} {
                set fmt "[dict get $bincodes $bitlen]u" ;# note unsigned
            } else {
                set fmt "B${bitlen}"
            }
            append binfmt $fmt
            lappend binargs $name
        }
        bitnary scan $data $binfmt {*}$binargs
        foreach _ $binargs {
            dict set result $_ [set $_]
        }
        return $result
    }
}
 
package require mainscript
if {[mainscript?]} {
proc test {} {
    set header {
        +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
        |                      ID                       |
        +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
        |QR|   Opcode  |AA|TC|RD|RA|   Z    |   RCODE   |
        +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
        |                    QDCOUNT                    |
        +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
        |                    ANCOUNT                    |
        +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
        |                    NSCOUNT                    |
        +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
        |                    ARCOUNT                    |
        +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    }
 
    set schema [asciipacket::parse $header]
    set values {
        ID 0xcafe
        QR 1
        Opcode 5
        AA 1
        TC 0
        RD 0
        RA 1
        Z  4
        RCODE 8
        QDCOUNT 0x00a5
        ANCOUNT 0x0a50
        NSCOUNT 0xa500
        ARCOUNT 0x500a
    }
    set pkt [asciipacket::encode $schema $values]
    puts "encoded packet (hex): [asciipacket::b2h $pkt]"
    set decoded [asciipacket::decode $schema $pkt]
    dict for {k v} $values {
        debug assert {$v == [dict get $decoded $k]}
    }
}
test
}
