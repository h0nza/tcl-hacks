package require snit

snit::widgetadaptor topleveled {
    component widget
    option -modal -default 0 -configuremethod setOpt
    delegate option * to widget
    delegate method * to widget

    constructor {cons args} {
        debug log {creating topleveled $cons $win}
        installhull using toplevel
        install widget using $cons $win.widget {*}$args
        grid $widget -sticky nsew
        grid rowconfigure $win 0 -weight 1
        grid columnconfigure $win 0 -weight 1
        trace add command $widget delete "destroy $self; list"
    }

    destructor {
        debug log {Destroying topleveled $win $self}
    }

    method setOpt {opt value} {
        switch -exact $opt {
            -modal {
                throw {UNIMPLEMENTED}
                # wm configure ...
            }
        }
        set options($opt) $value
    }
}
