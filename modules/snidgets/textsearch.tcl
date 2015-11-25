#package require opts
#
# SYNOPSIS
#
#  bind_textsearch .textwidget
#


bind TextSearch.TEntry <Key-Escape>      {close_textsearch %W; break}
bind TextSearch.TEntry <Control-f>       {do_textsearch -next %W; break}
bind TextSearch.TEntry <Control-r>       {do_textsearch -prev %W; break}
bind TextSearch.TEntry <Shift-Control-f> {do_textsearch -prev %W; break}

# ??
#ttk::style element create Entry.star [ttk::image create photo -file foo] -border {2 0} -sticky e
#ttk::style layout TextSearch.TEntry {
#    Entry.field -sticky nswe -border 1 -children {
#        Entry.padding -sticky nswe -children {
#            Entry.star -side e
#            Entry.textarea -sticky nswe
#        }
#    }
#}

proc bind_textsearch {w {event <Control-f>}} {
    bind $w $event [list open_textsearch $w]
    $w tag configure ts_match -background yellow
    $w configure -insertunfocussed hollow
}

proc open_textsearch {w} {
    ttk::entry ${w}._search -validate key -validatecommand {do_textsearch %W %P} ;#-class TextSearch.TEntry
    bindtags $w._search [list TextSearch.TEntry {*}[bindtags $w._search]]

    place ${w}._search -in $w -anchor s -relx 0.5 -rely 1.0
    focus ${w}._search
}

proc close_textsearch {w} {
   focus [set W [winfo parent $w]]
   destroy $w
   $W tag remove ts_match 1.0 end
}

proc do_textsearch args {
    options {-next} {-prev}
    arguments {w {s ""}}
    if {$s eq ""} {
        set s [$w get]
    }
    set w [winfo parent $w]
    set idx "insert"
    set dir -forwards
    if {$next} {
        append idx " + 1 chars"
    } elseif {$prev} {
        append idx " - 1 chars"
        set dir -backwards
    }
    set idx [$w search -exact $dir $s $idx]
    if {$idx eq ""} {
        return 0
    } else {
        $w mark set insert $idx
        $w tag remove ts_match 1.0 end
        $w tag add ts_match $idx [set i2 "$idx + [string length $s] chars"]
        $w see $i2
        $w see $idx
        return 1
    }
}

