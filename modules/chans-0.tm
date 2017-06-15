package require coroutine
package require pkg
pkg chans {

    namespace eval tee {
        proc initialize {what x mode}    {
            fconfigure $what -buffering none -translation binary
            info procs
        }
        proc finalize {what x}           { }
        proc write {what x data}         { 
            puts -nonewline $what $data
            chan flush $what
            return $data
        }
        proc flush {what x}              { }
        namespace export *
        namespace ensemble create -parameters what
    }

    namespace eval redir {
        proc initialize {what x mode}    {
            fconfigure $what -buffering none -translation binary
            info procs
        }
        proc finalize {what x }          { }
        proc write {what x data}         { 
            puts -nonewline $what $data
            chan flush $what
            return ""
        }
        proc flush {what x}              { }
        namespace export *
        namespace ensemble create -parameters what
    }

    namespace eval pipe {
        proc initialize {what x mode}    {
            info procs
        }
        proc finalize {what x}           { }
        proc write {what x data}         { 
            uplevel 0 $what [list $data]
        }
        proc flush {what x}              { }
        namespace export *
        namespace ensemble create -parameters what
    }

    namespace eval teecmd {
        proc initialize {what x mode}    {
            info procs
        }
        proc finalize {what x }          { }
        proc write {what x data}         { 
            uplevel #0 $what [list $data]
            return $data
        }
        proc flush {what x}              { }
        namespace export *
        namespace ensemble create -parameters what
    }

    oo::class create fifo {
        variable Block
        variable Watch
        variable Data
        variable Size
        constructor {{size 1}} {
            set Block 1
            set Watch {}
            set Size $size
            set Data {}
        }
        method Postevent {chan event} {
            if {$event in $Watch} {
                # FIXME: after idle? (see http://core.tcl.tk/tcl/tktview?name=67a5eabbd3)
                chan postevent $chan $event
            }
        }
        method data {} {
            return $Data
        }
        method initialize {chan mode} {
            return {initialize finalize blocking watch read write}
        }
        method finalize {chan} {
            my destroy
        }
        method blocking {chan mode} {
            set Block $mode
        }
        method watch {chan events} {
            set Watch $events
        }
        method read {chan bytes} {
            if {$Data eq ""} {
                #puts REAGAIN
                error EAGAIN
            }
            set data [lpop Data]
            #puts "READ: $data"
            if {[llength $Data] < $Size} {
                my Postevent $chan "write"
            }
            if {$Data ne ""} {
                my Postevent $chan "read"
            }
            return $data
        }
        method write {chan data} {
            if {[llength $Data] >= $Size} {
                #puts WEAGAIN
                error EAGAIN
            }
            #puts "WRITE: $data"
            lappend Data $data
            my Postevent $chan "read"
            if {[llength $Data] < $Size} {
                my Postevent $chan "write"
            }
            string length $data
        }
    }

    proc eachobj {_obj chan script} {
        upvar 1 $_obj obj
        while {1} {
            if {[coroutine::util gets $chan line] < 1} {
                if {[eof $chan]} break else continue
            }
            append blob $line\n
            if {![info complete $blob]} {continue}
            set obj [string range $blob 0 end-1]
            set blob ""
            uplevel 1 $script
        }
        if {$blob ne ""} {
            uplevel 1 $script
        }
    }

    oo::class create iterobj {
        variable chan
        constructor {Chan} {
            set chan $Chan
        }
        destructor {
            debug log {iterobj [self] closing $chan}
            close $chan     ;# ??
        }
        method next {} {
            set blob ""
            while {$blob eq "" || ![info complete [set blob $blob\n]]} {
                if {[set rc [coroutine::util gets $chan line]] < 0} {
                    if {[eof $chan]} {
                        if {$blob ne ""} {
                            debug log {iterobj($chan): discarding incomplete input {$blob}}
                        }
                        return -code break 
                    } else {
                        debug log {iterobj:  gets returned $rc but not eof ??}
                        continue
                    }
                }
                append blob $line
            }
            return $blob
        }
    }


}

if 0 {
    chans::fifo create fi 2
    set fd [chan create {read write} fi]
    chan configure $fd -buffering line -blocking 0
    foreach i {0 1 2} {
        puts $fd lalala$i
        puts put$i:[fi data]
        flush $fd
    }
    foreach i {0 1 2 3} {
        puts line$i:[gets $fd line]:$line
        puts get$i:[fi data]
    }
}
