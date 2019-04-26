# making a [chan pipe] out of refpipes
# passes the rudimentary synchronous test cases, does it pass async?
namespace eval refpipe {

    oo::class create Buffer {
        variable Size
        variable Data
        variable Block
        variable Watch
        constructor {size} {
            set Size $size
            set Block 1
            set Watch {}
            set Data {}
        }
        method initialize {chan mode} {
            return {initialize finalize blocking watch write read configure}
        }
        method finalize {chan} {
            puts "[self class] [self] finalize!"
            my destroy
        }
        method blocking {chan mode} {
            puts "[self class] [self] blocking $mode"
            set Block $mode
        }
        method watch {chan events} {
            set Watch $events
        }
        method configure {chan key val} {
            if {$key ne "-size"} {
                return -code error "Bad option \"$key\", should be \"-size\""
            }
            if {![string is integer $val]} {
                return -code error "Expected integer but got \"$val\""
            }
            set Size $val
        }
        method Postevent {chan event} {
            if {$event in $Watch} {
                # (see http://core.tcl.tk/tcl/tktview?name=67a5eabbd3)
                after idle [list chan postevent $chan $event]
            }
        }
        method write {chan data} {
            if {[string length $Data] + [string length $data] > $Size} {
                if {$Block} {
                    throw {POSIX EPIPE} "Buffer is full!"
                } else {
                    throw EAGAIN EAGAIN
                }
            }
            append Data $data
            my Postevent $chan "read"
            if {[string length $Data] < $Size} {
                my Postevent $chan "write"
            }
            return [string length $data]
        }
        method read {chan bytes} {
            if {$Data eq ""} {
                if {$Block} {
                    return ""
                } else {
                    throw EAGAIN EAGAIN
                }
            }
            set r [string range $Data 0 $bytes]
            set Data [string replace $Data 0 $bytes]
            return $r
        }
    }

    oo::class create Writer {
        variable Buffer
        variable Watch
        variable Block
        constructor {buffer} {
            set Buffer $buffer
            set Block 1
            set Watch {}
        }
        method initialize {chan mode} {
            return {initialize finalize blocking watch write}
        }
        method finalize {chan} {
            puts "[self class] [self] finalize!"
            my destroy
        }
        method blocking {chan mode} {
            set Block $mode
        }
        method watch {chan events} {
            set Watch $events
        }
        method Postevent {chan event} {
            if {$event in $Watch} {
                # (see http://core.tcl.tk/tcl/tktview?name=67a5eabbd3)
                after idle [list chan postevent $chan $event]
            }
        }
        method write {chan data} {
            puts -nonewline $Buffer $data
            return [string length $data]
        }
    }

    oo::class create Reader {
        variable Buffer
        variable Watch
        variable Block
        constructor {buffer} {
            set Buffer $buffer
            set Block 1
            set Watch {}
        }
        method initialize {chan mode} {
            return {initialize finalize blocking watch read}
        }
        method finalize {chan} {
            puts "[self class] [self] finalize!"
            chan configure $Buffer -size 0
            my destroy
        }
        method blocking {chan mode} {
            set Block $mode
        }
        method watch {chan events} {
            set Watch $events
        }
        method Postevent {chan event} {
            if {$event in $Watch} {
                # (see http://core.tcl.tk/tcl/tktview?name=67a5eabbd3)
                after idle [list chan postevent $chan $event]
            }
        }
        method read {chan size} {
            read $Buffer $size
        }
    }


    proc buffer {{size Inf}} {
        set fd [chan create {read write} [Buffer new $size]]
        chan configure $fd -buffering none
        return $fd
    }

    proc pipe {{size Inf}} {
        set buf [buffer $size]
        set rd [chan create read [Reader new $buf]]
        set wr [chan create write [Writer new $buf]]
        chan configure $wr -buffering none
        list $rd $wr
    }
}

proc ok {result args} {
    set r [uplevel 1 $args]
    if {$r eq $result} {
        puts "OK: got expected \"$result\""
    } else {
        puts "ERR: expected \"$result\" but got \"$r\""
    }
}

proc err {code args} {
    set rc [catch {uplevel 1 $args} res opts]
    set errcode {}
    catch {set errcode [dict get $opts -errorcode]}
    if {$errcode eq $code} {
        puts "OK: got expected {$code} \"$res\""
    } else {
        puts "ERR: expected error {$code} but got $rc \"$res\" $opts"
    }
}

proc main {} {
    set buf [refpipe::buffer 10]
    chan configure $buf -buffering none
    ok ""               puts $buf "Hello"
    err {POSIX EPIPE}   puts $buf "World"
    ok "Hello"          gets $buf
    ok ""               gets $buf
    ok 1                eof $buf
    ok ""               puts $buf "Hi"
    ok ""               puts $buf "Mate"
    ok "Hi"             gets $buf
    ok "Mate"           gets $buf
    ok ""               close $buf
    puts "buf ok"

    lassign [refpipe::pipe] rd wr
    ok ""               puts $wr "Hello"
    ok ""               puts $wr "World"
    ok ""               close $wr
    ok "Hello"          gets $rd
    ok "World"          gets $rd
    ok ""               gets $rd
    ok 1                eof $rd
    puts done!

    lassign [refpipe::pipe] rd wr
    close $rd
    err {POSIX EPIPE}   puts $wr "Hello"
}

main
