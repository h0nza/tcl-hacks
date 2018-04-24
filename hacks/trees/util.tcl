# generic utilities
proc putl {args}            {puts $args}
proc pdict {dict {name ""}} {array set $name $dict; parray $name}
proc assert {expr {msg ""}} {
    if {$msg eq ""} {set msg $expr}
    tailcall if $expr {} else [list throw {ASSERT FAILURE} "Assert failure: $msg"]
}
proc upcall {cmd args} {
    set qcmd [uplevel 1 [list namespace which $cmd]]
    assert {$qcmd ne ""} "upcall: no such command \"$cmd\""
    tailcall uplevel 1 [list $qcmd {*}$args]
}
proc callback {cmd args} {
    set qcmd [uplevel 1 [list namespace which $cmd]]
    assert {$qcmd ne ""} "upcall: no such command \"$cmd\""
    list $qcmd {*}$args
}

# set ops
proc lfilter {varName ls test} {
    set body "if {\[$test\]} continue ; [callback set $varName]"
    tailcall lmap $varName $ls $body
}
proc all {test ls} {
    foreach elem $ls {
        if {![uplevel 1 $test [list $elem]]} {return false}
    }
    return true
}
proc forany {args} {        ;# aka [exists]
    set body [lindex $args end]
    set args [lrange $args 0 end-1]
    set body "if {\[$body\]} {throw {FORANY YES} {}}"
    tailcall try [
                callback foreach {*}$args $body
            ] trap {FORANY YES} {} {
                return -level 0 true
            } on ok {} {
                return -level 0 false
            }
}

proc dassign {dict args} {  ;# like [lassign] but for dicts: [dassign dictValue key ...]
    dict map {k v} $dict {
        if {$k in $args} {
            uplevel 1 [callback set $k $v]
            continue
        } else {
            set v
        }
    }
}

proc dict_get? {dict args} {
    if {[dict exists $dict {*}$args]} {
        return [dict get $dict {*}$args]
    }
}
