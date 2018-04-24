# debugging
proc cmdtrace {cmdname} {
    upcall trace add execution $cmdname {enter leave} cmdtrace_cb
}
proc cmdtrace_cb {cmdstring args} {
    variable cmdtrace_indent
    if {[llength $args] == 1} {
        lassign $args op
    } else {
        lassign $args code result op
    }
    if {[string match enter* $op]} {
        incr cmdtrace_indent
        puts "[format %*s $cmdtrace_indent ""]> [cmdtrace_abbrev $cmdstring]"
    } else {
        puts "[format %*s $cmdtrace_indent ""]< $result"
        incr cmdtrace_indent -1
    }
}
proc cmdtrace_abbrev {cmd} {
    lmap w $cmd {
        if {[regexp \n $w]}             {set w {...}}
        #if {[string length $w] > 33}    {set w [string replace $w 15 end-15 "..."]}
        set w
    }
}


