proc sh_quote {args} {
    join [
        lmap arg $args {
            string cat ' [string map {' '\\''} $arg] '
        }
    ] " "
}

proc safe_exec {args} {
    exec sh -c [sh_quote {*}$args]
}

foreach cmdlist {
    {echo "<foo>"}
    {echo "[foo]"}
    {echo "$PS1"}
    {echo "| gzip -9"}
    {echo "$(sleep 100)"}
    {echo "`sleep 100`"}
} {
    puts "## $cmdlist"
    puts " -> [safe_exec {*}$cmdlist]"
}
