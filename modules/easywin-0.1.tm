# from http://wiki.tcl.tk/20619 revision 10 2015-12-01
if 0 {
    [NEM] 2008-01-11: Here is a little (ish) package that wraps up [toplevel], [wm], [winfo]
    and [MacWindowStyle] into a single mega-widget using [snit]. The window is actually somewhat
    more than just a toplevel, as it incorporates a toolbar ([ttk::frame]), menubar and a status/
    progressbar, as these are frequently needed items (at least for the apps I like to develop).
    I'm trying to put as much platform-specific knowledge into the implementation of this as
    possible, while keeping the interface platform-independent. Options that only make sense on
    a certain platform are ignored on others, etc.

        easywin .ew -option value -option value ...

    OPTIONS:

    A rather large number of options are supported, and probably more will be added.

        -title:         Set the title of the window (i.e. [wm title]).
        -toolbar:       Boolean, indicates whether to display the toolbar or not.
        -statusbar:     Whether to display the statusbar (and progressbar).
        -document:      Use this to set the full path name of the file currently being viewed in the window (if it is being used in that way).
                        On Mac this will set the -titlepath so that an appropriate proxy icon is displayed (very cool bit of polish).
        -modified:      Indicates whether the contents of the window have been modified since last save.

    Lots of other options which related to various [wm attributes] options for different platforms (and are no-ops on other platforms).

        -windowclass:   Sets the window class on TkAqua (see [MacWindowStyle])
        -attributes:    Sets the window attributes on TkAqua (see [MacWindowStyle])
        -savecommand:   Sets a command to invoke to save the current window contents (see below).

    METHODS:

        $win status ?msg?:          Get or set the current status message displayed in the statusbar.
        $win progress total done:   Set the current progress value. 
            This will display a progress bar in the statusbar if one is not already visible.
            If total==done then the progressbar is hidden again.
        $win hide ?component?/show ?component?/hidden ?component/toggle ?component?:   Hide or show a particular component of the window or check the status of a component.
            Valid component names are:
                self (ie, the entire window) (default)
                statusbar
                toolbar
        $win toolbar:               Returns the tk command of the toolbar frame widget, so you can add items to it.

    In addition, direct access to the underlying widgets is provided through the commands

        $win statusbar ...:   
        $win progressbar ...:   
        $win menu ...:   

    So for example you can do
        $win menu add cascade ...

    Various other methods exist: essentially the whole of [wm] and [winfo] exist as methods on the window.

    PROMPT TO SAVE FILE:

    If you supply a ''-savecommand'' option then the widget will check the ''-modified'' flag when
    a user attempts to close the window. If the contents have been modified then a dialog will be
    displayed asking if the user wants to save first. If they click yes, then the -savecommand is
    invoked passing the window name as an argument.
}
# easywin.tcl --
#
#       A wrapper around Tk's built-in toplevel command, providing support for
#       toolbars etc.
#
# Author: 2008 Neil Madden (nem@cs.nott.ac.uk).
# Public Domain.

package require Tcl         8.5
package require Tk          8.5
package require snit        2.2

snit::widgetadaptor easywin {
    option -title       -default "" -configuremethod ChangeTitle
    option -toolbar     -default 0  -configuremethod ChangeComponent
    option -statusbar   -default 0  -configuremethod ChangeComponent
    option -document    -default "" -configuremethod ChangeDocument \
                                    -cgetmethod      GetDocument
    option -modified    -default 0  -configuremethod ChangeAttribute \
                                    -cgetmethod      GetAttribute
    option -alpha       -default 1  -configuremethod ChangeAttribute \
                                    -cgetmethod      GetAttribute
    option -toolwindow  -default 0  -configuremethod ChangeAttribute \
                                    -cgetmethod      GetAttribute
    option -topmost     -default 0  -configuremethod ChangeAttribute \
                                    -cgetmethod      GetAttribute
    option -disabled    -default 0  -configuremethod ChangeAttribute \
                                    -cgetmethod      GetAttribute
    option -fullscreen  -default 0  -configuremethod ChangeAttribute \
                                    -cgetmethod      GetAttribute
    option -transparentcolor -default 0  -configuremethod ChangeAttribute \
                                    -cgetmethod      GetAttribute
    option -notify      -default 0  -configuremethod ChangeAttribute \
                                    -cgetmethod      GetAttribute
    option -transparent -default 0  -configuremethod ChangeAttribute \
                                    -cgetmethod      GetAttribute
    option -zoomed      -default 0  -configuremethod ChangeAttribute \
                                    -cgetmethod      GetAttribute
    option -aspect      -default "" -configuremethod ChangeAspect
    option -client      -default [info hostname] \
                        -configuremethod ChangeClient
    # Tk Aqua window class and attributes (no-ops on other platforms)
    option -windowclass -default "document" -readonly 1
    option -attributes  -default {toolbarButton standardDocument} \
                        -readonly 1
    option -transient   -default ""  -configuremethod ChangeTransient
    option -savecommand -default ""
    delegate option -orient to mainframe

    component statusbar -public statusbar
    component progress  -public progressbar
    component menu      -public menu

    component mainframe
    component toolbar

    delegate option * to hull
    delegate method * to mainframe

    variable hidden [dict create]

    typevariable wmoptions
    typeconstructor {
        lappend ::snit::hulltypes window glib::window
        set wmoptions(aqua)     {-fullscreen -topmost -modified -titlepath
                                 -alpha -notify}
        set wmoptions(win32)    {-fullscreen -alpha -toolwindow -topmost
                                 -transparentcolor -disabled}
        set wmoptions(x11)      {-fullscreen -topmost -zoomed}
    }

    constructor args {

        # Extract options that must be supplied at creation time.
        set class ArtclWindow
        set orient vertical
        foreach op {class orient} {
            if {[set idx [lsearch -exact $args -$op]] >= 0} {
                set $op [lindex $args [expr {$idx+1}]]
                set args [lreplace $args $idx [incr idx]]
            }
        }

        if {[tk windowingsystem] eq "aqua"} {
            set tstyle Toolbar
        } else {
            set tstyle TFrame
        }

        # Construct components
        installhull         using toplevel -class $class
        wm withdraw $win
        install menu        using menu $win.mb
        install toolbar     using ttk::frame $win.tb -style $tstyle
        install mainframe   using ttk::panedwindow $win.main \
                                -orient $orient
        install statusbar   using ttk::label $win.status \
                                -font TkSmallCaptionFont \
                                -padding 2
        install progress    using ttk::progressbar $win.progress \
                                -orient horizontal -mode determinate

        $self configure -menu $menu
        wm protocol $win WM_DELETE_WINDOW [mymethod close]
        bind $win <<ToolbarButton>> [mymethod toggle toolbar]

        # Layout
        grid $toolbar       -sticky ew      -columnspan 2
        grid [ttk::separator $win.tsep -orient vertical] \
                            -sticky ew      -columnspan 2
        grid $mainframe     -sticky nsew    -columnspan 2
        grid [ttk::separator $win.bsep -orient vertical] \
                            -sticky ew      -columnspan 2
        grid $statusbar $progress -sticky ew

        # Add some space to avoid the window resize grip on Aqua
        grid configure $progress -padx {0 20}
        grid remove $progress

        grid columnconfigure $win 0 -weight 1
        grid rowconfigure    $win 2 -weight 1

        $self configurelist $args

        # Apply the window style on Mac OS X before the window gets mapped.
        if {[tk windowingsystem] eq "aqua"} {
            ::tk::unsupported::MacWindowStyle style $win \
                [$self cget -windowclass] [$self cget -attributes]
        }
        wm deiconify $win
    }

    # usage msg --
    #
    #       Convenience proc for creating wrong # args errors.
    #
    proc usage msg {
        return -code error -level 2 -errorcode [list WRONGARGS $msg] \
            "wrong # args: should be \"$msg\""
    }


    # status ?message? --
    #
    #       Get or set the status message for the window.
    #
    method status args {
        switch -exact [llength $args] {
            0       { $statusbar cget -text }
            1       { $statusbar configure -text [lindex $args 0] }
            default {
                usage "$self status ?message?"
            }
        }
    }

    # progress total done --
    #
    #       Set the progress value for the window. This causes the progress
    #       bar to be displayed in the status bar area (if the statusbar
    #       itself is visible). If total == done then the progress bar is
    #       removed.
    #
    method progress {total done} {
        if {$total == $done} {
            grid remove $progress
        } else {
            if {![$self hidden statusbar] &&
                $progress ni [grid slaves $win]} { grid $progress }
            $progress configure -maximum $total -value $done
        }
    }

    method toolbar {} { return $toolbar }

    # hide ?component? --
    #
    #       Hides the specified component (defaults to "self"). Valid
    #       component names are "statusbar", "toolbar" or "self" (which hides
    #       the entire window).
    #
    method hide {{component "self"}} {
        if {$component eq "self"} {
            wm withdraw $win
        } else {
            grid remove [set $component]
        }
        dict set hidden $component 1
    }

    # show ?component? --
    #
    #       Shows the specified component (defaults to "self"). Valid
    #       component names are "statusbar", "toolbar" or "self" (which
    #       deiconifies the entire window).
    #
    method show {{component "self"}} {
        if {$component eq "self"} {
            wm deiconify $self
        } else {
            grid [set $component]
        }
        dict set hidden $component 0
    }

    # hidden ?component? --
    #
    #       Returns 1 if the given component is hidden, or 0 otherwise.
    #
    method hidden {{component "self"}} {
        if {[dict exists $hidden $component]} {
            return [dict get $hidden $component]
        } else {
            return 0
        }
    }

    # toggle ?component? --
    #
    #       Toggles the hidden/shown status of a component.
    #
    method toggle {{component "self"}} {
        if {[$self hidden $component]} {
            $self show $component
        } else {
            $self hide $component
        }
    }

    # wm geometry ?newGeom? --
    #
    #       Wrapper around the [wm geometry] command.
    #
    method geometry args {
        wm geometry $win {*}$args
    }

    # close --
    #
    #       Attempt to close the window. This method will first check to see
    #       whether the contents of the window have been modified, and if so,
    #       offer the user the chance to save the contents before closing. The
    #       behaviour of this method is controlled by the -modified option and
    #       the -savecommand option. The dialog will only be displayed if
    #       -modified and a -savecommand has been specified. The save command
    #       will be invoked passing in the object command of this window. If
    #       the -savecommand returns 1 then closing of the window will be
    #       aborted.
    #
    method close {} {
        set command [$self cget -savecommand]
        if {[$self cget -modified] && $command ne ""} {
            set ans [tk_messageBox -icon warning -parent $win \
                -title "Contents Modified" \
                -message [concat \
                    "The contents of this window have been modified."\
                    "Do you want to save the changes before"\
                    "closing?"] \
                -type yesnocancel -default cancel]
            if {$ans eq "cancel"} { return 0 }
            if {$ans eq "yes"} {
                if {[uplevel #0 $command $self] == 1} {
                    # Save command aborted close
                    return 0
                }
            }
        }
        destroy $win
        return 1
    }

    # Various [wm] commands that I don't know how best to handle yet :-)
    foreach op {forget frame grid group iconbitmask iconify iconmask iconname
        iconphoto iconwindow manage maxsize minsize overrideredirect
        positionfrom protocol resizable sizefrom stackorder state} {

        method $op args [format { wm %s $win {*}$args } $op]
    }

    # And the same for [winfo] commands
    foreach op {atom atomname cells children class colormapfull containing
        depth exists fpixels height id interps ismapped manager name parent
        pathname pixels pointerx pointerxy pointery reqheight reqwidth rgb
        rootx rooty screen screencells screendepth screenheight screenmmheight
        screenmmwidth screenvisual screenwidth server toplevel viewable visual
        visualid visualsavailable vrootheight vrootwidth vrootx vrooty width x
        y} {

        method $op args [format { winfo %s $win {*}$args } $op]
    }

    #
    #======================================================================
    #
    # PRIVATE METHODS
    #
    #======================================================================
    #

    # Change the title of the window (implements -title option)
    method ChangeTitle {option value} {
        set options($option) $value
        wm title $win $value
    }

    # Change whether a particular component is displayed (-statusbar and
    # -toolbar options).
    method ChangeComponent {option value} {
        set options($option) $value
        set component [string range $option 1 end]
        if {$value} {
            $self show $component
        } else {
            $self hide $component
        }
    }

    # Change a window attribute (implements most of the platform-specific
    # options). Attributes that make no sense on a particular platform are
    # simply ignored.
    method ChangeAttribute {option value} {
        set options($option) $value

        if {$option in $wmoptions([tk windowingsystem])} {
            wm attributes $win $option $value
        }
    }

    # Return the current value of an option. This implements the cget method
    # for various [wm attribute] options as these can be changed from outside
    # the application itself (e.g. moving the file of a -document option in
    # the finder will change the -document value).
    method GetAttribute {option} {
        if {$option in $wmoptions([tk windowingsystem])} {
            return [wm attribute $win $option]
        }
        return $options($option)
    }

    # Maps the -document option to the rather more obscure -titlepath on
    # TkAqua.
    method ChangeDocument {option value} {
        set options($option) $value
        $self ChangeAttribute -titlepath $value
    }
    method GetDocument {option} {
        $self GetAttribute -titlepath
    }

    # Implements changes to -windowclass and -attributes options. Not sure if
    # you can actually change these after window creation, but might still be
    # useful in some cases.
    method ChangeWindow {option value} {
        if {[tk windowingsystem] eq "aqua"} {
            set class [$self cget -windowclass]
            set attrs [$self cget -attributes]
            ::tk::unsupported::MacWindowStyle style $win $class $attrs
        }
        set options($option) $value
    }

    # Implements -transient option
    method ChangeTransient {option value} {
        wm transient $win $value
        set options($option) $value
    }

    # Implements -aspect option
    method ChangeAspect {option value} {
        wm aspect $win $value
        set options($option) $value
    }

    # Implements -client option
    method ChangeClient {option value} {
        wm client $win $value
        set options($option) $value
    }
}

#  Demo:
if {[info exists ::argv0] && $::argv0 eq [info script]} {
    # editor.tcl --
    #
    #       A simple text editor application to demonstrate the glib library.
    #
    # Public domain.
    #

    package require Tcl     8.5
    package require Tk      8.5

    wm withdraw .

    set edcount 0

    proc editor w {
        global edcount
        # Create the editor window
        set win [easywin $w -title "Text Editor" -savecommand file:save]

        # Create the text component
        set f [ttk::frame $win.f]
        set t [text $f.t -highlightthickness 0 -yscrollcommand [list $f.vsb set]]
        set v [ttk::scrollbar $f.vsb -orient vertical -command [list $f.t yview]]

        bind $t <<Modified>> [list modified %W]

        # Grid them
        grid $t $v -sticky nsew
        grid rowconfigure $f 0 -weight 1
        grid columnconfigure $f 0 -weight 1

        $win add $f -weight 1

        # Create menu and toolbar entries
        set file [menu $win.file -tearoff 0]
        $win menu add cascade -label File -underline 0 -menu $file

        action $win open "Open..." O 0 [list file:open $win]
        $file add separator
        action $win close "Close" W 0 [list file:close $win]
        action $win save "Save" S 0 [list file:save $win]
        action $win saveas "Save As..." A 5 [list file:saveas $win]
        $file add separator
        action $win quit "Exit" Q 1 [list file:quit $win]

        $win status "Done"

        incr edcount
    }

    proc modifier key {
        switch -exact [tk windowingsystem] {
            aqua    { return "Command-$key" }
            win32   { return "Ctrl+$key"    }
            default { return "Ctrl-$key"    }
        }
    }
    proc binding key {
        set key [string tolower $key]
        switch -exact [tk windowingsystem] {
            aqua    { return "<Command-$key>" }
            default { return "<Control-$key>" }
        }
    }
    proc action {win name label accel uline cmd} {
        global col
        $win.file add command -label $label \
            -accelerator [modifier $accel] \
            -underline $uline \
            -command $cmd
        set tb [$win toolbar]
        ttk::button $tb.$name -text $label -command $cmd \
            -style Toolbutton
        grid $tb.$name -row 0 -column [incr col]
        bind $win [binding $accel] $cmd
    }

    # Handle changes to the text widget modified status
    proc modified w {
        set win [winfo toplevel $w]
        set text $win.f.t
        set mod [$text edit modified]
        $win configure -modified $mod
        set state [expr {$mod ? "normal" : "disabled"}]
        $win.file entryconfigure Save -state $state
        [$win toolbar].save configure -state $state
    }


    proc file:open win {
        set file [tk_getOpenFile -parent $win]
        if {$file eq ""} { return }
        set in [open $file]
        $win.f.t delete 1.0 end
        $win.f.t insert end [read $in]
        close $in
        $win.f.t see 1.0
        $win configure -document [file normalize $file] -title [file tail $file]
        $win.f.t edit modified 0
        modified $win
        $win status "Done"
    }

    proc file:save win {
        set file [$win cget -document]
        file:saveas $win $file
    }

    proc file:saveas win {
        if {$file eq ""} {
            set file [tk_getSaveFile -parent $win]
        }
        if {$file eq ""} { return 1 }
        set out [open $file w]
        puts $out [$win.f.t get 1.0 end-1c]
        close $out
        $win configure -document [file normalize $file]
        $win.f.t edit modified 0
        modified $win
        $win status "Opened $file"
    }

    proc file:close win { $win close }

    proc file:quit win {
        global edcount
        if {[$win close]} { incr edcount -1 }
        if {$edcount <= 0} { exit }
    }
    editor .ed
}
