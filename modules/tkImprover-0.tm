# most of this is from marsgui by WHD @ JPL:  http://wiki.tcl.tk/41820
#   git://github.com/AthenaModel/mars
#   lib/marsgui/global.tcl
#
# See also:
#   * user interface guidelines from http://wiki.tcl.tk/41773
#   * further text improvements from http://wiki.tcl.tk/14918
#   * treeview RowSelect events from http://wiki.tcl.tk/24636
#   * treeview search by typing from http://wiki.tcl.tk/20065

# widgets should take focus when clicked on

bind all <1> {+catch {if {[%W cget -takefocus] ne 0} {puts "Focusing %W"; focus %W}}}

# workaround for https://core.tcl.tk/tk/tktview/3009450fffffffffffffffffffffffffffffffff
# FIXME: this assumes the parent is normally -disabled 0.
rename grab _grab
proc grab {args} {
    switch -glob -- [lindex $args 0] {
        set - -* {
            set win [lindex $args end]
            set parent [wm transient $win]
            if {$parent ne ""} {
                wm attributes $parent -disabled 1
            }
        }
        release {
            set win [lindex $args end]
            set parent [wm transient $win]
            if {$parent ne ""} {
                wm attributes $parent -disabled 0
            }
        }
    }
    tailcall _grab {*}$args
}


# helper for re-binding events
namespace eval Events {

    #variable Events ;# this isn't really needed
    variable Keys    ;# tracking what keys are already bound is importand for rebinding!
    variable Log on

    proc Init {} {
        #variable Events
        variable Keys
        foreach event [event info] {
            set keys [event info $event]
            #dict set Events $event $keys
            foreach key $keys {
                dict set Keys $key $event
            }
        }
    }

    # this isn't very clever, only close enough for the immediate need here.
    # A fully-accurate version might use <http://wiki.tcl.tk/1401#pagetoc4d1849c3>
    # (or at least be tested against it)
    proc normalize {event} {
        set event [string range $event 1 end-1]
        set parts [split $event -]
        foreach type {Button ButtonPress ButtonRelease Key KeyPress KeyRelease} {
            if {$type in $parts} {
                return $event
            }
        }
        set bit [lindex $parts end]
        if {[string is digit -strict $bit]} {
            set parts [linsert $parts end-1 "Button"]
        } else {
            set parts [linsert $parts end-1 "Key"]
        }
        return <[join $parts -]>
    }

    proc Lock {event} {
        set event [string range $event 1 end-1]
        set parts [split $event -]
        if {"Lock" in $parts} {
            return ""   ;# nothing to add
        }
        if {[string match Key* [lindex $parts end-1]]} {
            set key [lindex $parts end]
            if {[string is upper $key]} {
                set key [string tolower $key]
            } elseif {[string is lower $key]} {
                set key [string toupper $key]
            } else {
                return ""   ;# nothing to add
            }
            lset parts end $key
            set parts [linsert $parts end-2 "Lock"]
        }
        return <[join $parts -]>
    }

    proc rebind {event key args} {
        variable Log
        #variable Events
        variable Keys
        set args [list $key {*}$args]
        set args [lmap a $args {normalize $a}]
        foreach arg $args {
            set lock [Lock $arg]
            if {$lock ne ""} {
                if {$Log} {
                    puts stderr "Warning: implicitly binding $lock as well as $key"
                }
                lappend args $lock
            }
        }
        foreach key $args {
            try {
                set old [dict get $Keys $key]
                if {$Log} {
                    puts stderr "Warning: rebinding $key to $event (from $old)"
                }
                event del $old $key
                dict set Keys $key $event
            } trap {TCL LOOKUP DICT} {} {
                # ok
            }
        }
        event add $event {*}$args
        #dict lappend Events $event {*}$args
    }
    Init
}


apply {{} {

    global tcl_platform

    # identify the platform in a useful way:

    if {$tcl_platform(platform) eq "windows"} {
        set platform "win"
    } elseif {$tcl_platform(os) eq "Darwin"} {
        set platform "mac"
    } else {
        set platform "unix"
    }

    # the default theme is a bit crap, particularly on Linux
    switch $platform {
        "windows" {
            ::ttk::style theme use vista
        }
        "unix" {
            ::ttk::style theme use alt
        }
    }

    # Relate the virtual events to these keystrokes.  Widgets will get
    # the virtual event on the keystroke, unless there's some other
    # keybinding.

    Events::rebind <<Cut>>       <Control-x>
    Events::rebind <<Copy>>      <Control-c>
    Events::rebind <<Paste>>     <Control-v>
    Events::rebind <<Undo>>      <Control-z>

    if {$tcl_platform(os) eq "SunOS"} {
        Events::rebind <<Redo>>      <Control-Shift-z>  ;# Control-Shift-Z - <Control-y> is <<Paste>>
    } else {
        Events::rebind <<Redo>>      <Control-y>
    }

    if {$platform eq "unix"} {
        Events::rebind <<SelectAll>> <Control-A>  ;# Control-Shift-A - <Control-a> is <<Home>>
    } else {
        Events::rebind <<SelectAll>> <Control-a>
    }

    # Entry and Text Widget Paste Behavior
    #
    # For some odd reason, if you paste via <<Paste>> into an entry widget
    # when text is selected, the pasted text doesn't replace the selected
    # text.  I don't know why this is, but it's counter-intuitive.  The
    # default binding says explicitly that if we're on x11 *don't* delete
    # the previously selected text.  So we override that check in the default
    # bindings.

    set map {{[tk windowingsystem] ne "x11"}
             {1 || [tk windowingsystem] ne "x11"}}

    bind Entry <<Paste>> [
        string map $map [bind Entry <<Paste>>]
    ]

    proc ::tk_textPaste {w} [
        string map $map [info body ::tk_textPaste]
    ]

# Virtual events for forms:  <<Submit>> and <<Cancel>>

    # .. these make a mess when widgets already handle said keystroke
    #event add <<Submit>> <Return>
    #event add <<Cancel>> <Escape>
 
    # .. so some extra smarts are needed:
    bind all <Return> {
        if {%M==0} {
            event generate %W <<Submit>>
        }
    }
    bind all <Escape> {
        if {%M==0} {
            event generate %W <<Cancel>>
        }
    }
# rebind do-nothing keys to generate these events
    foreach tag {Entry TEntry Text} {   ;# CText?
        foreach {event key} {
            <<Submit>> <Return>
            <<Cancel>> <Escape>
        } {
            set script [bind $tag $key]
            if {$script eq "# nothing"} {
                bind $tag $key "[list event generate %W $event]; break"
            }
        }
    }
    #bind all <<Submit>> {puts Sbmit!%W}
    #bind all <<Cancel>> {puts Cancl!%W}


# set up some better default options
    set defaultBackground [ttk::style configure . -background]
    set defaultBackground [ttk::style lookup . -background active]
    set stripeBackground  #EEF9FF

    # Give a combobox with focus the same kind of halo as a ttk::entry.
    ttk::style map TCombobox \
        -lightcolor      [list  focus "#6f9dc6"] \
        -darkcolor       [list  focus "#6f9dc6"] \
        -fieldbackground [list disabled $defaultBackground]

    # TEntry: Set background for readonly and disabled ttk::entry widgets
    ttk::style map TEntry \
        -fieldbackground [list readonly $defaultBackground \
                               disabled $defaultBackground]

    # the default TButton minwidth of 11 is too big:
    ttk::style configure TButton -width -8

    # tearoff menus suck:
    option add *Menu.tearOff                    no
}}
