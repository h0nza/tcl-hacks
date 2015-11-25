#
# SYNOPSIS:
#
#   pack [labelled .e button -label "Type stuff" -text "Press me" -command {puts [.e get]}]
#
package require snit

proc otherside {side} {
    dict get {
        left right
        right left
        top bottom
        bottom top
    } $side
}

snit::widgetadaptor labelled {

    component label
    component widget

    option -side -default left
    option -state -default normal -configuremethod setOpt
    delegate option -label to label as -text
    delegate option * to widget
    delegate method * to widget

    method setOpt {opt value} {
        switch -exact $opt {
            -state {
                $label configure -state [expr {$value eq "disabled" ? "disabled" : "normal"}]
                $widget configure -state $value
            }
        }
        set options($opt) $value
    }

    constructor {cons args} {
        installhull using frame
        install label  using label $win.label -anchor w
        install widget using $cons $win.widget
        $self configure -takefocus {}   ;# why is this needed?  seems to only be in FormDialogs??
        $self configurelist $args
        pack $widget -side [otherside $options(-side)] -fill none -expand no    -padx 2 -pady 2
        pack $label  -side [otherside $options(-side)] -fill both -expand yes   -padx 2 -pady 2
#        grid $label  -sticky nsew
#        grid $widget -row 0 -column 1 
#        grid columnconfigure $win 1 -weight 0
#        grid columnconfigure $win 0 -weight 1
#        grid rowconfigure $win 0 -weight 1
        trace add command $widget delete "destroy $self; list"
    }

}

package provide labelled 0.1

if 0 {
    package require Tk
    grid [labelled .e button -label "This is a button" -text "Press me" -command {puts "aah!"}] -sticky nsew
    grid [labelled .e2 button -label "So is this" -side right -text "Push It" -command {puts "so good"}] -sticky nsew
    grid [labelled .e3 button -label "This is a button" -side top -text "Press me" -command {puts "aah!"}] -sticky nsew
    grid [labelled .e4 button -label "So is this" -side bottom -text "Push It" -command {puts "so good"}] -sticky nsew
    grid columnconfigure . 0 -weight 1
    grid rowconfigure . 0 -weight 1
    grid rowconfigure . 1 -weight 1
    grid rowconfigure . 2 -weight 1
    grid rowconfigure . 3 -weight 1
}
