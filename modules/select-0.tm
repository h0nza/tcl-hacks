# A read handler can be given a varname, which will have the available data read up front.
# A read handler will normally fire at EOF with empty $data, so the user should check for that OR install an EOF handler.
# If an EOF handler is installed, it will be called automatically at EOF (after the 0-length read).
# Read/EOF handlers will be disabled at EOF.
# Timeout occurs at a fixed interval after the select loop is started.  Idler occurs after a fixed interval of no events firing.
#  - disabling a handler / removing a socket should be easy, including in loop mode. (close will do!)
#  - errors in dynamic-with's unwind?  For channel properties, we just want to ignore.
#  - multiple idlers/timeouts might be useful?  Can always be reinstalled at runtime.
namespace eval select {

    oo::class create Select {

        variable inset outset eofset afters idlers
        constructor args {
            namespace path [list {*}[namespace path] ::select]
            lassign {} inset outset eofset afters idlers
        }

        method <- args  { tailcall my <-/[llength $args] {*}$args }
        method !- args  { tailcall my !-/[llength $args] {*}$args }
        method -> args  { tailcall my ->/[llength $args] {*}$args }

        method !-/1 {chan}          { dict unset eofset $chan $script }
        method !-/2 {chan script}   { dict set eofset $chan $script }

        method ->/1 {chan}          { dict unset outset $chan $script }
        method ->/2 {chan script}   { dict set outset $chan $script }

        method <-/1 {chan}          { dict unset inset $chan }
        method <-/2 {chan script}   { dict set  inset $chan $script }
        method <-/3 {chan varname script} { dict set inset $chan "set [list $varname] \[read [list $chan]\] ; $script" }

        method timeout {ms script}  { set afters [dict create $ms $script] }
        method idle {ms script}     { set idlers [dict create $ms $script] }

        method run {}   { tailcall my Run 1 }
        method loop {}  { tailcall my Run 0 }

        export <- !- -> {[a-z]*}

        method Run {once} {

            set outs [lsort -uniq [dict keys $outset]]
            set ins  [lsort -uniq [concat [dict keys $inset] [dict keys $eofset]]]
            set all  [lsort -uniq [concat $ins $outs]]

            foreach chan $all   { dynamic-with  {chan configure $chan -blocking}    0 }
            foreach chan $outs  { dynamic-with  {chan configure $chan -buffering}   none }
            foreach chan $ins   { dynamic-with  {chan event $chan readable}         [list [info coroutine] read $chan] }
            foreach chan $outs  { dynamic-with  {chan event $chan writable}         [list [info coroutine] write $chan] }

            dict for {ms script} $afters {
                set after       [after $ms  [list [info coroutine] timeout $ms]]
                finally after cancel $after
            }

            set idler {}

            while 1 {

                dict for {ms script} $idlers {
                    set idler   [after $ms  [list [info coroutine] idler $ms]]
                }

                lassign [yieldm] action val

                after cancel $idler

                set script [switch $action {
                    timeout { dict get $afters $val }
                    idler   { dict get $idlers $val }
                    write   { dict get $outset $val }
                    read    { dict get  $inset $val }
                    default {
                        throw OOPS "Unexpected action \"$action\""
                    }
                }]

                uplevel 1 $script

                if {$action eq "read" && [dict exists $eofset $val] && [eof $val]} {
                    uplevel 1 [dict get $eofset $val]
                }

                if {$once} break
            }
        }
    }

    proc dynamic-with {args} {
        if {[llength $args] % 2 == 1} {
            set body [lindex $args end]
            set args [lrange $args 0 end-1]
        }
        dict for {cmd new} $args {
            set old [uplevel 1  "$cmd"]
            uplevel 1           "$cmd [list $new]"
            set fin             "$cmd [list $old]"
            lappend fins $fin
        }
        if {[info exists body]} {
            tailcall try $body finally [join $fins \n]
        } else {
            foreach fin $fins {
                uplevel 1 [list finally {*}$fin]
            }
        }
    }

    proc finally {args}  { tailcall trace add variable :#finally#: unset [list apply [list args $args]] }

    proc yieldm {args}   { yieldto string cat {*}$args }

    proc callback {args} { namespace code $args }

}

if {[info exists ::argv0] && $::argv0 eq [info script]} {

    proc main {} {

        set io [open "|socat - EXEC:tclsh,pty,stderr" r+]
        chan configure $io -buffering none
        chan configure stdout -buffering none

        select::Select create select
        select <- $io   data {
            puts -nonewline stdout $data
            if {[eof $io]}   { puts "\nEOF:io:[string length $data]" }
        }
        select <- stdin data {
            puts -nonewline $io $data
            if {[eof stdin]} { puts "\nEOF:stdin:[string length $data]" }
        }
        select !- stdin      { puts "EOF on stdin" ;      break }
        select !- $io        { puts "Subprocess exited" ; break }
        select idle 1000     { puts "Hurry up!" }
        select timeout 10000 { puts "You've had your 10s" ; break }
        select loop
        select destroy

        close $io
        exit 0

    }

    coroutine Main main
    vwait forever
}
