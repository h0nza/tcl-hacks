proc callback {cmd args} {
    list [uplevel 1 [list namespace which -command $cmd]] {*}$args
}

oo::class create Hexed {
    variable data
    variable pos
    variable endian
    constructor {{Data ""} {Pos 0}} {
        set data $Data; set pos $Pos
        set endian be
        trace add variable pos write [callback my Bounds]
    }

    method Bounds {args} {
        set len [string length $data]
        if {$pos > $len} {tailcall my Error "Seek past end of data ($pos > $len)!"}
        if {$pos < 0} {tailcall my Error "Seek before start data ($pos)!"}
    }

    method Error {str} {
        tailcall return -code error $str
    }

    method Type {type} {
        switch $type {
            s8      {return {1 c}}
            s32le   {return {4 i}}
            s32be   {return {4 I}}
            s16le   {return {2 s}}
            s16be   {return {2 S}}
            u8      {return {1 cu}}
            u32le   {return {4 iu}}
            u32be   {return {4 Iu}}
            u16le   {return {2 su}}
            u16be   {return {2 Su}}
            u16 - s16 - u32 - s32 {return [my Type ${type}${endian}]}
            a* - c* {
                scan %c%s $type c d
                return [list $d a$d]
            }
            default {
                return -code error "Unknown type \"$type\""
            }
        }
    }

    method endian {which} {
        switch $which {
            be - b - bi - big {set endian be}
            le - l - li - lit - litt - littl - little {set endian le}
        }
    }

    method load {filename} {
        set fd [open $filename r]
        chan configure $fd -translation binary
        set data [read $fd]
        set pos 0
        close $fd
    }
    method save {filename} {
        set fd [open $filename w]
        chan configure $fd -translation binary
        puts -nonewline $fd $data
        close $fd
    }

    method fromhex {args} { set data [binary decode hex     [join $args ""]] }
    method fromb64 {args} { set data [binary decode base64  [join $args ""]] }
    method tohex {}                 { binary encode hex     $data }
    method tob64 {}                 { binary encode base64  $data }

    method tell {} { return $pos }
    method here {} { return $pos }
    method seek {n} {
        set end [string length $data]
        set start 0
        set map [list end $end start $start]
        switch -glob $n {
            end* - start* {
                set pos [expr [string map $map $n]]
            }
            default {
                incr pos $n
            }
        }
    }
    method trunc {} {
        set data [string range $data 0 $pos-1]
    }
    method search {needle} {
        set ofs [string first $needle $data $pos]
        if {$ofs == -1} {
            my Error "Could not find search string \"$needle\""
        }
        set pos $ofs
    }
    method rsearch {needle} {
        set ofs [string last $needle $data $pos]
        if {$ofs == -1} {
            my Error "Could not find search string \"$needle\""
        }
        set pos $ofs
    }

    method read {type varName} {
        upvar 1 $varName var
        lassign [my Type $type] bytes code
        set bits [string range $data $pos $pos+$bytes]
        incr pos $bytes
        binary scan $bits $code var
    }
    method write {type value} {
        lassign [my Type $type] bytes code
        set bits [binary format $code $value]
        set data [string replace $data $pos [expr {$pos+$bytes-1}] $bits]
        incr pos $bytes
    }
    method insert {type value} {
        lassign [my Type $type] bytes code
        set bits [binary format $code $value]
        #set data [string insert $data $pos $bits]
        set data [string range $data 0 $pos-1]$bits[string range $data $pos end]
        incr pos $bytes
    }
    method replace {type check value} {
        lassign [my Type $type] bytes code
        set here $pos
        my read $type oldbits
        if {$oldbits ne $check} {
            my Error "Expected '$check', got '$value'"
        }
        my seek $here
        my write $type
    }
    method erase {type value} {
        lassign [my Type $type] bytes code
        set here $pos
        my read $type oldbits
        if {$oldbits ne $check} {
            my Error "Expected '$check', got '$value'"
        }
        set data [string replace $data $pos [expr {$pos+$bytes-1}] ""]
    }
}
