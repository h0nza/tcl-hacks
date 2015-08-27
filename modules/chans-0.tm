package require coroutine
package require pkg
pkg chans {

    namespace eval tee {
        proc initialize {what x mode}    {
            fconfigure $what -buffering none -translation binary
            info procs
        }
        proc finalize {what x }          { }
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
