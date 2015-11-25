# WORK IN PROGRESS - NOT USABLE
snit::widgetadaptor Notebook {
    option -command     -default {}     -configuremethod setOpt
    variable tabs
    variable current

    constructor args {
        installhull using ttk::frame
        grid [RadioSet $win.panes -packside left -itemstyle Toolbutton] -sticky new
        set tabs {}
        set current {}
        $self configurelist $args
        $self build
    }
    method build {} {
        $win.panes configure -choices $tabs
        if {[dict exists $pages $current]} {
            set page [dict get $pages $current]
            grid $page -in $win -sticky nsew
            grid rowconfigure $win $slave -weight 1
            grid columnconfigure $win $slave -weight 1
        }
    }
    method add {name w} {
        if {[dict exists $pages $name]} {
            return -code error "Already have an entry called $name"
        }
        dict set pages $name $w
        dict set tabs  $name $w
        if {![dict exists $tabs $current]} {
            set current $name
        }
        $self build
    }
}

