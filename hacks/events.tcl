# The goal here is to redirect events from one window to another, while preserving all of
# their fields.  To decide what fields, we parse the text of event(n).
#
# this uncovered a BUG:  [event generate . <<Cut>> -serial 1 -bar   returns the wrong error

package require Tk
package require Ttk

namespace eval Event {

    # copied from http://www.tcl.tk/man/tcl/TkCmd/event.htm#M9
    variable Manual {
-above window
    Window specifies the above field for the event, either as a window path name or as an integer window id. Valid for Configure events. Corresponds to the %a substitution for binding scripts.

-borderwidth size
    Size must be a screen distance; it specifies the border_width field for the event. Valid for Configure events. Corresponds to the %B substitution for binding scripts.

-button number
    Number must be an integer; it specifies the detail field for a ButtonPress or ButtonRelease event, overriding any button number provided in the base event argument. Corresponds to the %b substitution for binding scripts.

-count number
    Number must be an integer; it specifies the count field for the event. Valid for Expose events. Corresponds to the %c substitution for binding scripts.

-data string
    String may be any value; it specifies the user_data field for the event. Only valid for virtual events. Corresponds to the %d substitution for virtual events in binding scripts.

-delta number
    Number must be an integer; it specifies the delta field for the MouseWheel event. The delta refers to the direction and magnitude the mouse wheel was rotated. Note the value is not a screen distance but are units of motion in the mouse wheel. Typically these values are multiples of 120. For example, 120 should scroll the text widget up 4 lines and -240 would scroll the text widget down 8 lines. Of course, other widgets may define different behaviors for mouse wheel motion. This field corresponds to the %D substitution for binding scripts.

-detail detail
    Detail specifies the detail field for the event and must be one of the following:

        NotifyAncestor
            

        NotifyNonlinearVirtual

        NotifyDetailNone
            

        NotifyPointer

        NotifyInferior
            

        NotifyPointerRoot

        NotifyNonlinear
            

        NotifyVirtual

    Valid for Enter, Leave, FocusIn and FocusOut events. Corresponds to the %d substitution for binding scripts.

-focus boolean
    Boolean must be a boolean value; it specifies the focus field for the event. Valid for Enter and Leave events. Corresponds to the %f substitution for binding scripts.

-height size
    Size must be a screen distance; it specifies the height field for the event. Valid for Configure events. Corresponds to the %h substitution for binding scripts.

-keycode number
    Number must be an integer; it specifies the keycode field for the event. Valid for KeyPress and KeyRelease events. Corresponds to the %k substitution for binding scripts.

-keysym name
    Name must be the name of a valid keysym, such as g, space, or Return; its corresponding keycode value is used as the keycode field for event, overriding any detail specified in the base event argument. Valid for KeyPress and KeyRelease events. Corresponds to the %K substitution for binding scripts.

-mode notify
    Notify specifies the mode field for the event and must be one of NotifyNormal, NotifyGrab, NotifyUngrab, or NotifyWhileGrabbed. Valid for Enter, Leave, FocusIn, and FocusOut events. Corresponds to the %m substitution for binding scripts.

-override boolean
    Boolean must be a boolean value; it specifies the override_redirect field for the event. Valid for Map, Reparent, and Configure events. Corresponds to the %o substitution for binding scripts.

-place where
    Where specifies the place field for the event; it must be either PlaceOnTop or PlaceOnBottom. Valid for Circulate events. Corresponds to the %p substitution for binding scripts.

-root window
    Window must be either a window path name or an integer window identifier; it specifies the root field for the event. Valid for KeyPress, KeyRelease, ButtonPress, ButtonRelease, Enter, Leave, and Motion events. Corresponds to the %R substitution for binding scripts.

-rootx coord
    Coord must be a screen distance; it specifies the x_root field for the event. Valid for KeyPress, KeyRelease, ButtonPress, ButtonRelease, Enter, Leave, and Motion events. Corresponds to the %X substitution for binding scripts.

-rooty coord
    Coord must be a screen distance; it specifies the y_root field for the event. Valid for KeyPress, KeyRelease, ButtonPress, ButtonRelease, Enter, Leave, and Motion events. Corresponds to the %Y substitution for binding scripts.

-sendevent boolean
    Boolean must be a boolean value; it specifies the send_event field for the event. Valid for all events. Corresponds to the %E substitution for binding scripts.

-serial number
    Number must be an integer; it specifies the serial field for the event. Valid for all events. Corresponds to the %# substitution for binding scripts.

-state state
    State specifies the state field for the event. For KeyPress, KeyRelease, ButtonPress, ButtonRelease, Enter, Leave, and Motion events it must be an integer value. For Visibility events it must be one of VisibilityUnobscured, VisibilityPartiallyObscured, or VisibilityFullyObscured. This option overrides any modifiers such as Meta or Control specified in the base event. Corresponds to the %s substitution for binding scripts.

-subwindow window
    Window specifies the subwindow field for the event, either as a path name for a Tk widget or as an integer window identifier. Valid for KeyPress, KeyRelease, ButtonPress, ButtonRelease, Enter, Leave, and Motion events. Similar to %S substitution for binding scripts.

-time integer
    Integer must be an integer value; it specifies the time field for the event. Valid for KeyPress, KeyRelease, ButtonPress, ButtonRelease, Enter, Leave, Motion, and Property events. Corresponds to the %t substitution for binding scripts.

-warp boolean
    boolean must be a boolean value; it specifies whether the screen pointer should be warped as well. Valid for KeyPress, KeyRelease, ButtonPress, ButtonRelease, and Motion events. The pointer will only warp to a window if it is mapped.

-width size
    Size must be a screen distance; it specifies the width field for the event. Valid for Configure events. Corresponds to the %w substitution for binding scripts.

-when when
    When determines when the event will be processed; it must have one of the following values:

    now
        Process the event immediately, before the command returns. This also happens if the -when option is omitted.

    tail
        Place the event on Tcl's event queue behind any events already queued for this application.

    head
        Place the event at the front of Tcl's event queue, so that it will be handled before any other events already queued.

    mark
        Place the event at the front of Tcl's event queue but behind any other events already queued with -when mark. This option is useful when generating a series of events that should be processed in order but at the front of the queue.

-x coord
    Coord must be a screen distance; it specifies the x field for the event. Valid for KeyPress, KeyRelease, ButtonPress, ButtonRelease, Motion, Enter, Leave, Expose, Configure, Gravity, and Reparent events. Corresponds to the %x substitution for binding scripts. If Window is empty the coordinate is relative to the screen, and this option corresponds to the %X substitution for binding scripts.

-y coord
    Coord must be a screen distance; it specifies the y field for the event. Valid for KeyPress, KeyRelease, ButtonPress, ButtonRelease, Motion, Enter, Leave, Expose, Configure, Gravity, and Reparent events. Corresponds to the %y substitution for binding scripts. If Window is empty the coordinate is relative to the screen, and this option corresponds to the %Y substitution for binding scripts. 
    }

    variable Options
    variable Fields

    apply [list {} {
        variable Manual
        #set Manual [exec man --nh --nj event]
        regexp {\nEVENT FIELDS\n(.*?)(?=\n[A-Z])} $Manual -> Manual
        variable Options
        variable Fields

        foreach {_ option desc} [regexp -all -inline -lineanchor {^\s*?(-\S*) [^\n]*\n(.*)\.$} $Manual] {

            regsub -all {\s\s+} $desc " " desc
            set codes [regexp -all -inline {%.} $desc]
            regexp -nocase {Valid for (.*?) events.} $desc -> kinds
            set kinds [string map {"," "" " and " " "} $kinds]

            switch -exact $option {
                -warp - -when {continue}
                debug {
                    puts "option $option"
                    puts "desc $desc"
                    puts "codes $codes"
                    puts "kinds $kinds"
                }
            }

            foreach kind $kinds {
                dict lappend Fields $kind $option
            }

            switch -exact $option {
                -x  {
                    dict set Options -x { -x [expr {$win eq "" ? %X : %x}]}
                }
                -y {
                    dict set Options -y { -y [expr {$win eq "" ? %Y : %y}]}
                }
                default {
                    if {[lassign $codes code] ne ""} {
                        error "Bad codes for $option: $codes"
                    }
                    dict set Options $option " {*}\[if {{$code} ne {??}} {list [list $option $code]}\]"
                }
            }
        }
    } [namespace current]]

    proc redirect_script {event target} {
        variable Fields
        variable Options
        set script "event generate $target $event"
        set options [dict get $Fields "all"]
        if {[string match <<*>> $event]} {
            lappend options {*}[dict get $Fields "virtual"]
        }
        catch {
            lappend options {*}[dict get $Fields $event]
        }
        foreach opt $options {
            append script [dict get $Options $opt]
        }
        #set script "puts [list $script]"
        #puts $script
        return $script
    }

    proc redirect {win event target} {
        set script [redirect_script $event $target]
        append script ";break"
        bind $win $event $script
    }
}

if 0 {
    namespace path ::ttk
    pack [labelframe .f -text "Container"]
    pack [entry .e -textvariable str] -in .f
    bindtags .e {.e Entry .f all}
    set str "Hello"
    bind .f <<Cut>> {puts "<<Cut>> @ %W"}
    puts [Event::redirect .e <<Cut>> .f]
}
