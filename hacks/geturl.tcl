package require http
package require uri
catch {
    package require tls
    http::register https 443 ::tls::socket
}

#http::config -useragent poop   ;# ?? I think this was to get around sourceforge?

# -- simple wrapper for http::geturl
#  FIXME:  add wget (getfile, binary mode)
#  this would be cool as a filesystem too
proc geturl {url {_meta {}}} {
    if {$_meta ne ""} {
        upvar 1 $_meta meta
    }
    http::config -useragent moop    ;# thanks source forge!
                                    ;# -headers {User-Agent moop} adds a 2nd user-agent header
                                    ;# and geturl doesn't take -useragent :(
    if {[info coroutine] eq ""} {
        set tok [::http::geturl $url]   
    } else {
        ::http::geturl $url -command [info coroutine]
        set tok [yield]
    }
    try {
        upvar 1 $tok state
        if {[set status [::http::status $tok]] ne "ok"} {
            error $status
        }
        set headers [dict map {key val} [::http::meta $tok] {
            set key [string tolower $key]
            set val
        }]
        if {[dict exists $headers location]} {
            tailcall geturl [::uri::resolve $url [dict get $headers location]] $_meta
        }
        return [::http::data $tok]
    } finally {
        unset ${tok}(body)
        # charset?  Content-Type {text/html;charset=UTF-8}
        set meta [array get $tok]
        ::http::cleanup $tok
    }
}

proc mirror {base destdir {queue ""}} {
    set blen [string length $base]
    lappend queue $base
    set pos -1
    while {[incr pos] < [llength $queue]} {
        set url [lindex $queue $pos]
        puts [list getting $url]

        set data [geturl $url meta]
        set type [dict get $meta type]

        set path [string range $url $blen end]
        if {[file tail $path] eq ""} {
            set path [file join $path index.html]
        }
        set path [file join $destdir $path]

        puts [list saving $path]
        file mkdir [file dirname $path]

        set fd [open $path w[expr {[string match text/* $type] ? "" : "b"}]]
        puts -nonewline $fd $data
        close $fd

        if {[string match text/html* $type]} {
            set doc [dom parse -html $data]
            $doc selectNodes {//a}
            foreach n [$doc selectNodes {//a}] {
                set href [$n getAttribute href]
                set href [lindex [split $href #] 0]
                set href [uri::resolve $base $href]
                if {[string range $href 0 $blen-1] eq $base && [string first ? $href] == -1} {
                    if {$href ni $queue} {
                        lappend queue $href
                    }
                }
            }
        }
    }
}

if 0 {
    set tar [geturl http://sourceforge.net/projects/tcl/files/Tcl/8.6.3/tk8.6.3rc1-src.tar.gz]
    puts [string length $tar]

    package require zlib
    set tar [zlib gunzip $tar]
    set chan [stringchan create $tar]
    #vfs::memchan
    package require vfs
    package require vfs::tar
}

# I used to have some stuff - maybe on thinkpad backup - wiring this to tdom + xpath
#   # see http://w3.linux-magazine.com/issue/20/tDOM.pdf
#   package require tdom
#   set d [dom parse -html [geturl $u]]
#   set x [$d documentElement]
#   foreach n [$x selectNodes {//..../}] {
#       puts [$x asText]
#   }

#namespace eval hp {
#    package require tdom
#    proc intags {html {tag title}} {
#        set dom [dom parse -html $html]
#        lmap n [$dom selectNodes "//$tag"] {
#            $n text
#        }
#    }
#    namespace export *
#    namespace ensemble create
#}

