# see http://wiki.tcl.tk/40097 - "..." means we resolve symlinks
interp alias {} mainscript? {} expr {
       [info exists ::argv0]
    && [file dirname [file normalize $::argv0/...]]
    eq [file dirname [file normalize [info script]/...]]
}
