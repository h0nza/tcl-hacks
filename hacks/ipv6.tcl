if 0 {
    Native representation of an IP address (4 or 6) is as an integer.  Use [expr] to work with it.

    This parser is pretty permissive, but assertions should catch actual errors.

    Useful procs:

      ipv6 parse 2002::127.0.0.1
      ipv6 format $addr_as_int

    Base85 isn't fully supported yet, but is a trivial addition.

    To make computation useful needs some simple operations on {ip mask} pairs.
    netaddr-tcl is a better model than tcllib_ip.

    <dkf> The problem with IPv6 is that it's address/port combinations are like this: [abcd::ef01]:234
}



namespace eval ipv6 {

    namespace ensemble create -map {parse Parse format Format}

    # some helpers:
    #interp alias {} assert {} debug assert
    if {[info commands assert] eq ""} {
        proc assert {expr} {
            if {![uplevel 1 [list expr $expr]]} {
                throw ASSERT "Assertion failed! $expr"
            }
        }
        proc all {args} {
            set ls [lindex $args end]
            set cmd [lrange $args 0 end-1]
            if {$cmd eq ""} {
                set cmd K
            }
            foreach x $ls {
                if {![uplevel 1 {*}$cmd [list $x]]} {return false}
            }
            return true
        }
    }

    proc Parse {str} {
        try {
            set x [ParseAddr $str]
            assert {[string length $x] == 32}
        } on error {e o} {
            dict incr o -level
            dict set o -errorcode {IPv6 PARSE ERROR}
            return {*}$o "IPv6 parse error: $e"
        }
        scan $x %llx x
        return $x
    }

    # Affix::Affix
    proc ParseAddr {str} {
        if {[regexp {^(.*)::(.*)$} $str -> pre suf]} {
            set pre [ParseAffix $pre]
            set suf [ParseAffix $suf]
            set nz [expr {32 - [string length $pre] - [string length $suf]}]
            string cat $pre [string repeat 0 $nz] $suf
        } else {
            ParseAffix $str
        }
    }

    # a Word(:Word)*
    proc ParseAffix {str} {
        set parts [split $str :]
        join [lmap word $parts {ParseWord $word}] {}
    }

    # a single part of an address:  [:xdigit:]{1,3}  or  dotted-quad
    proc ParseWord {str} {
        if {[regexp {^(\d+)\.(\d+)\.(\d+)\.(\d+)$} $str -> o1 o2 o3 o4]} {
            assert {[all {expr 256 >} [list $o1 $o2 $o3 $o4]]}
            format {%02X%02X%02X%02X} $o1 $o2 $o3 $o4
        } else {
            assert {[string is xdigit -strict $str]}
            assert {[string length $str] <= 4}
            format %04s $str
        }
    }

    # none of the variants are exposed, for want of a nice interface
    proc Format {n} {
        Compress [FormatLong $n]
    }
    proc Fourmat {n} {
        Compress [Fourify [FormatLong $n]]
    }
    proc FourmatLong {n} {
        Fourify [FormatLong $n]
    }
    proc Compress {s} {
        regsub {(^|:)(0($|:))+} $s :: s
        return $s
    }
    proc FormatLong {n} {
        set s [format %032llX $n]
        set parts [lmap {a b c d} [split $s {}] {
            format %X [string cat 0x $a $b $c $d]
        }]
        set s [join $parts :]
    }
    proc Fourify {s} {
        regexp {(.*):([^:]*):([^:]*)$} $s -> pre x y
        scan $x %X x
        scan $y %X y
        set a [expr {$x >> 8}]
        set b [expr {$x & 0xff}]
        set c [expr {$y >> 8}]
        set d [expr {$y & 0xff}]
        set v4 [format {%d.%d.%d.%d} $a $b $c $d]
        string cat $pre : $v4
    }

    proc Base85 {n} {
        set base85 [split [string cat {*}{
             0123456789
             ABCDEFGHIJKLMNOPQRSTUVWXYZ
             abcdefghijklmnopqrstuvwxyz
             {!#$%&()*+-;<=>?@^_`{|}~}
        }] {}]
        loop i 0 20 {
            lappend res [lindex $base85 [expr {$n % 85}]]
            set n [expr {$n / 85}]
        }
        join [lreverse $res] {}
    }

    proc test {} {
        foreach {short long} {
                1080::8:800:200C:417A           1080:0:0:0:8:800:200C:417A
                FF01::43                        FF01:0:0:0:0:0:0:43
                ::1                             0:0:0:0:0:0:0:1
                ::                              0:0:0:0:0:0:0:0
                ::13.1.68.3                     0:0:0:0:0:0:13.1.68.3
                ::FFFF:129.144.52.38            0:0:0:0:0:FFFF:129.144.52.38
        } {
            assert {[set a [ipv6 parse $short]] eq [ipv6 parse $long]}
            assert {$short eq [ipv6 format $a] || $short eq [ipv6::Fourmat $a]}
            assert {$long eq [ipv6::FormatLong $a] || $long eq [ipv6::FourmatLong $a]}
        }
    }

}

ipv6::test
