package require tdom

set fd [open gutter/packages.xml r]
fconfigure $fd -encoding utf-8
set data [read $fd]
set dom [dom parse $data]

proc dump {_d} {
    set _n [dict get $_d name]
    if {$_n ne "tdom"} return
    array set $_n $_d
    parray $_n
}
foreach p [$dom selectNodes {/gutter/package}] {
    set pkg {}
    dict set pkg name [$p @id]
    foreach c [$p childNodes] {
        set attr [$c nodeName]
        set text [$c asText]
        if {$attr in {author license requires homepage summary description}} {
            dict set pkg $attr $text
        }
        if {$attr in {link}} {
            dict lappend pkg $attr [$c @rel] $text
        }
        if {$attr in {release}} {
            dict lappend pkg $attr [$c @version] $text
        }
        if {$attr in {depends}} {
            dict lappend pkg $attr {*}[split $text ,]
        }
    }
    dump $pkg
}
