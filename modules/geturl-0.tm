package require http
package require uri
if {![catch {package require tls}]} {
    http::register https 443 ::tls::socket
}

# simple wrapper for http::geturl
# follows redirections and by returns the response body
# _meta is a dict out param.
proc geturl {url {_meta {}}} {
    if {$_meta ne ""} {
        upvar 1 $_meta meta
    }
    http::config -useragent moop    ;# thanks sourceforge!
    set tok [::http::geturl $url]   ;# -headers {User-Agent moop} adds a 2nd user-agent header
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
