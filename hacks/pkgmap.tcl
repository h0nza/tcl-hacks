# first, hook package:
oo::class create PkgMapper {
    variable Chain 
    variable Deps
    variable Cmd
    constructor {cmd args} {
        set Cmd $cmd
        set Chain {}
        set Deps {}
    }
    method info {} {
        array set deps $Deps
        parray deps
    }
    method package {cmd args} {
        switch $cmd {
            "require" {
                set reqs [lassign $args pkg]
                if {$pkg eq "-exact"} {
                    set reqs [lassign $reqs pkg]
                }
                lappend Chain $pkg
                set rc [catch {uplevel 1 [list $Cmd $cmd {*}$args]} e o]
                if {[llength $Chain] > 1} {
                    dict lappend Deps {*}[lrange $Chain end-1 end]
                }
                set Chain [lreplace $Chain end end]
                if {$rc != 0} {
                    dict unset Deps $pkg
                }
                if {[dict exists $o -level]} {
                    dict incr o -level 1
                }
                return {*}$o $e
            }
            "provide" {
                lassign $args pkg version
                dict lappend Known $pkg $version
                tailcall $Cmd $cmd {*}$args
            }
            default {
                tailcall $Cmd $cmd {*}$args
            }
        }
    }
}

if 1 {
    proc test {path} {
        catch {package require { none such }}
        set before [package names]

        set pm [PkgMapper new :package]
        rename package :package
        interp alias {} package {} $pm package

        lappend ::auto_path $path
        ::tcl::tm::path add $path
        catch {package require { none too }}
        set after [package names]

        set names [lmap a $after {
            if {$a in $before} continue
            set a
        }]
        puts [llength $before]-[llength $after]
        puts $names
        foreach pkg $names {
            try {
                package require $pkg
            } on error {e o} {
                puts "! $e"
            }
        }
        $pm info
    }


    test {*}$argv
}

if 0 {
    set pm [PkgMapper new :package]
    rename package :package
    interp alias {} package {} $pm package

    puts [package names]
    catch {package require { none such }}
    #catch {package require gpx}
    set names [package names]
    puts "+ $names"
    $pm info
    puts " ---- "
    puts -nonewline [llength $names]:
    foreach pkg [lrange $names 0 50] {
        catch {
            package require $pkg
            puts -nonewline .
            flush stdout
        }
    }
    puts ""

    $pm info
}
