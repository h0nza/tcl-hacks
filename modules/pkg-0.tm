package require options

namespace eval ::pkg {

    # using the one option -unknown for -ensemble and normal unknowns is a bit fucked
    proc pkg args {
        options {-ensemble} {-export {{[a-z]*}}} {-import yes} {-unknown ""}
        arguments {name script}
        catch {uplevel 1 [list namespace delete $name]}
        append script "; namespace export [list {*}$export]"
        if {$ensemble} {
            append script {; namespace ensemble create}
            if {$unknown ne ""} {
                append script " -unknown [list $unknown]"
            }
        } else {
            if {$unknown ne ""} {
                append script "namespace unknown $unknown"
            }
            if {$import} {
                append script {; uplevel #0 namespace import [namespace current]::*}
            }
        }
        tailcall namespace eval $name $script 
    }


    proc reload {pkg} {
        package forget $pkg
        package require $pkg
    }

    namespace export pkg

}
namespace import ::pkg::pkg
