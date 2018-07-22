# adapted from http://wiki.tcl.tk/3307
oo::class create Zip {
    variable Data Directory

    constructor {bytes} {
        set Data $bytes
        my ReadDirectory
    }

    method ReadDirectory {} {
        set ofs 21
        while 1 {
            set dir [string range $Data end-$ofs end]
            binary scan $dir i sig
            if {$sig == 0x06054b50} {
                break
            }
            incr ofs            ;# FIXME: this is bloody slow, be more clever
        }
        binary scan $dir issssiis sig disk cddisk nrecd nrec dirsize diroff clen
        dict set Directory() comment [string range $dir 22 [expr {22 + $clen - 1}]]
        if {$disk != 0} {
            throw {ZIP UNSUPPORTED} "Multi-file zip not supported"
        }
        for {set i 0} {$i < $nrec} {incr i} {
            set entry [string range $Data $diroff [incr diroff 46]-1]
            binary scan $entry issssssiiisssssii \
                sig ver mver flag method time date crc csz usz n m k d ia ea ofs
            if {$sig != 0x02014b50} {
                throw {ZIP ERROR} "Bad directory entry at $diroff ([format %x $sig])"
            }
            set name [string range $Data $diroff [incr diroff $n]-1]
            set extra [string range $Data $diroff [incr diroff $m]-1]
            set c [string range $Data $diroff [incr diroff $k]-1]
            set Directory($name) [dict create timestamp [list $date $time] \
                size $csz disksize $usz offset $ofs method $method \
                extra $extra comment $c]
        }
    }
    method names {} {
        lsort [lsearch -inline -exact -all -not [array names Directory] ""]
    }
    method comment {{name ""}} {
        dict get $Directory($name) comment
    }
    method info {name {field ""}} {
        if {$field ne ""} {
            return [dict get $Directory($name) $field]
        }
        return $Directory($name)
    }
    method contents {name} {
        dict with Directory($name) {}
        binary scan [string range $Data $offset [incr offset 30]-1] \
            isssssiiiss sig - - - - - - - - nlen xlen
        if {$sig != 0x04034b50} {
            throw {ZIP NOTAFILE} "not a file record"
        }
        incr offset $nlen
        incr offset $xlen
        set data [string range $Data $offset [incr offset $size]-1]
        if {[string length $data] != $size} {
            error "read length mismatch: $size expected"
        }
        switch $method {
            0   { return $data }
            8   { return [zlib inflate $data] }
            default { throw {ZIP UNSUPPORTED} "Unsupported method $method" }
        }
    }
}

if {[info script] eq $::argv0} {
    set fd [open [lindex $argv 0] rb]
    set data [read $fd]
    Zip create z $data
    puts [z comment]
    foreach n [z names] {
        puts "$n ([z info $n disksize] bytes)"
    }
    puts [z contents teapot.txt]
}
