package require snit

snit::widgetadaptor ThemeSwitcher {

    delegate method * to hull
    delegate option * to hull

    constructor args {
        installhull using listbox
        bind $win <<ListboxSelect>> [mymethod Select]
        set names [::ttk::style theme names]
        set cur [::ttk::style theme use]
        set idx [lsearch -exact $names $cur]
        $win insert end {*}$names
        $win selection set $idx
    }

    method Select {} {
        set theme [$self get [$self curselection]]
        ::ttk::style theme use $theme
    }

}
