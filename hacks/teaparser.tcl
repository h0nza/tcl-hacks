package require vfs::mk4
package require vfs::tar
package require vfs::zip

proc parse_teapot {path} {
    variable pkgInfo
    set meta [get_meta $path]
    set meta [string trim $meta]
    foreach line [split $meta \n] {
        set line [string trimleft $line #]
        set line [string trim $line]
        if {$line eq ""} {continue}
        try {
            set args [lassign $line cmd]
        } on error {} {
            error "Malformed teapot"
        }
        set cmd [string tolower $cmd]
        if {$cmd in {package profile application}} {
            lassign $args name version
            continue
        } elseif {$cmd ni {meta}} {
            error "Unknown TEAPOT.txt cmd: $cmd $args"
        }
        set args [lassign $args field]
        dict lappend pkgInfo($name-$version) $field {*}$args
    }
}

proc get_meta {path} {
    if {[file isdirectory $path]} {
        set fd [open $path/teapot.txt r]
        set meta [read $fd]
        close $fd
        return $meta
    }
    set fd [open $path r]
    if {[get_meta_text $fd meta]} {
        return $meta
    }
    seek $fd 0
    if {[get_meta_bin $fd meta]} {
        return $meta
    }
    close $fd
    set unmount [try_mount $path]
    if {$unmount ne ""} {
        try {
            return [get_meta $path]
        } finally {
            {*}$unmount
        }
    }
}
proc get_meta_text {fd _meta} {
    upvar 1 $_meta meta
    gets $fd line0
    if {![catch {llength $line0} r] && $r == 3} {
        gets $fd line1
        if {![catch {lindex $line1 0} r] && $r eq "Meta"} {
            set meta $line0\n$line1\n[read $fd]
            return true
        }
    }
    return false
}
proc get_meta_bin {fd _meta} {
    upvar 1 $_meta meta
    fconfigure $fd -encoding binary
    set block [read $fd 16384]
    return [regexp {# @@ Meta Begin(.*)# @@ Meta End} $block -> meta]
}

proc try_mount {path} {
    foreach ext {zip mk4 tar} {
        try {
            set fd [::vfs::${ext}::Mount $path $path]
        } on error {e o} {
            puts "Failed to mount ${ext}://$path"
            continue
        } on ok {fd} {
            puts "Mounted ${ext}://$path"
            return [list ::vfs::${ext}::Unmount $fd $path]
        }
    }
    return ""   ;# failed to mount
}


parse_teapot {*}$argv
parray pkgInfo
