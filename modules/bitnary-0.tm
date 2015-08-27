# SYNOPSIS:
#
#   A wrapper for [binary scan] and [binary format] which can take consecutive bitstrings out of the same byte.
# 
# bitnary::format {iwb2b3b2i} 16 32 4 8 4 16
#  -> binary format {iwb7i} 16 32 [format %02b%03b%02b 4 8 4] 16
#
# bitnary::scan $s {iwb2b3b2i} i w f1 f2 f3 i2
#  -> try {
#          binary scan $s {iwb7i} i w %b%0 i2
#          scan [set %b%0] %02b%03b%02b f1 f2 f3
#          unset %b%0
#     }
#
#
# This is only lightly tested.  It seems to work with http://rosettacode.org/wiki/ASCII_art_diagram_converter#Tcl
# 
# "b" behaviour might not make much sense - "B" seems more important.
#
# Walf-way through I realise an *incompatibility* with binary:  
#   [bitnary format b4b4 1 2] works with integers.
#   [binary format b4b4 1 2]  will fail as it expects bitstrings
# I find integers more consistent here than bitstrings, so I'm leaving it as an incompatibility.

oo::object create bitnary
oo::objdefine bitnary {
    # bitnary args iwb2b3b2i 16 32 2 4 2 16
    #  -> format iwb7i args {16 32 %b%0 16} bitmap {%b%0 {fmt b nbits 7 str %02b%03b%02b args {2 4 2}}}
    # The format is changed to suit ::binary.  Args are synthesised where needed, and specified in bitmap
    method args {fmt args} {
        set parts [regexp -all -inline {[a-zA-Z@]u?\d*} $fmt]
        set bitwords {}     ;# dictionary of:
                            ;#  {syntheticVarName -> {fmt B nbits 7 str %02b%03b%02b args {f1 f2 f3}}}
        set partial {}      ;# {fmt B str %.. args {..}}
        set fmt ""          ;# this will be regenerated
        lappend parts ""    ;# sentinel to save code repetition
        foreach part $parts arg $args[unset args] {
            if {[regexp {^([bB])\D*(\d*)$} $part -> b nbits] && ($partial eq "" || [dict get $partial fmt] eq $b)} {
                if {$nbits eq ""} {set nbits 1}
                if {$partial eq ""} {
                    dict set partial fmt $b
                }
                dict incr    partial nbits $nbits
                dict append  partial str   "%0${nbits}b"
                dict lappend partial args   $arg
            } else {
                if {$partial ne ""} {
                    set varname %$b%[dict size $bitwords]
                    append fmt  [dict get $partial fmt] [dict get $partial nbits]
                    lappend args $varname
                    dict set bitwords $varname $partial
                    set partial ""
                }
                if {$part eq ""} break  ;# this is our sentinel
                append fmt $part
                lappend args $arg
            }
        }
        set res [dict create]
        dict set res format $fmt
        dict set res args   $args
        dict set res bitmap $bitwords
        return $res
    }

    method format {fmt args} {
        set spec [my args $fmt {*}$args]
        set args [lmap arg [dict get $spec args] {
            if {[dict exists $spec bitmap $arg]} {
                # FIXME: if the arg is too big, this should truncate it
                format [dict get $spec bitmap $arg str] {*}[dict get $spec bitmap $arg args]
            } else {
                set arg
            }
        }]
        tailcall ::binary format [dict get $spec format] {*}$args
    }

    method scan {s fmt args} {
        set spec [my args $fmt {*}$args]
        set script {}
        lappend script [list ::binary scan $s [dict get $spec format] {*}[dict get $spec args]]
        dict for {arg bitmap} [dict get $spec bitmap] {
            lappend script [string trim [format {
                ::scan [set %1$s] %2$s %3$s
                ::unset %1$s
            } [list $arg] [list [dict get $bitmap str]] [dict get $bitmap args]]]
        }
        tailcall ::try [join $script \n\t]
    }
}


if 1 {
    proc h2b args { binary format H* [join $args ""] }
    proc b2h {data} { binary scan $data H* hex; set hex }
    proc frombinary args { binary format B* [join $args ""] }
    proc tobinary {s} { binary scan $s B* d; set d }

    proc string_chunk {n s} {
        if {$s eq ""} return
        set i 0
        while {$i < [string length $s]} {
            lappend res [string range $s $i [incr i $n]-1]
        }
        return $res
    }

    proc tests {} {
        debug assert {[bitnary format b4b4 1 1] eq [frombinary 10001000]}
        debug assert {[bitnary format B4B4 1 1] eq [frombinary 00010001]}
        #debug assert {[bitnary format B4b4 1 1] eq [frombinary 0001000000001000]}
        #debug assert {[bitnary format b4B4 1 1] eq [frombinary 0000000100010000]}
        debug assert {[bitnary format cB2B3B2c 0xa5 2 7 1 0x5a] eq [frombinary 10100101 10 111 01 0 01011010]}
        debug assert {[bitnary format cB2B3B2c 0xa5 1 4 2 0x5a] eq [frombinary 10100101 01 100 10 0 01011010]}
    }
    #tests
}
