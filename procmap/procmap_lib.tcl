# Tcl 8.6.4 from /home/aspect/tclenv/bin/tclsh at (1437662027) Fri Jul 24 00:33:47 AEST 2015
#	tcl_platform(osVersion)      = 3.16.0-4-amd64
#	tcl_platform(pointerSize)    = 8
#	tcl_platform(byteOrder)      = littleEndian
#	tcl_platform(threaded)       = 1
#	tcl_platform(machine)        = x86_64
#	tcl_platform(platform)       = unix
#	tcl_platform(pathSeparator)  = :
#	tcl_platform(os)             = Linux
#	tcl_platform(user)           = aspect
#	tcl_platform(wordSize)       = 8
set ::procmap::procs {
	::tell ::tell
	::socket ::socket
	::subst ::subst
	::open ::open
	::eof ::eof
	::pwd ::pwd
	::glob ::glob
	::list ::list
	::pid ::pid
	::exec ::exec
	::auto_load_index ::auto_load_index
	::time ::time
	::unknown ::unknown
	::eval ::eval
	::lassign ::lassign
	::lrange ::lrange
	::fblocked ::fblocked
	::lsearch ::lsearch
	::auto_import ::auto_import
	::gets ::gets
	::case ::case
	::lappend ::lappend
	::proc ::proc
	::throw ::throw
	::break ::break
	::variable ::variable
	::llength ::llength
	::auto_execok ::auto_execok
	::return ::return
	::linsert ::linsert
	::error ::error
	::catch ::catch
	::clock ::clock
	{::clock add} ::tcl::clock::add
	{::clock clicks} ::tcl::clock::clicks
	{::clock format} ::tcl::clock::format
	{::clock microseconds} ::tcl::clock::microseconds
	{::clock milliseconds} ::tcl::clock::milliseconds
	{::clock scan} ::tcl::clock::scan
	{::clock seconds} ::tcl::clock::seconds
	::info ::info
	{::info args} ::tcl::info::args
	{::info body} ::tcl::info::body
	{::info cmdcount} ::tcl::info::cmdcount
	{::info commands} ::tcl::info::commands
	{::info complete} ::tcl::info::complete
	{::info coroutine} ::tcl::info::coroutine
	{::info default} ::tcl::info::default
	{::info errorstack} ::tcl::info::errorstack
	{::info exists} ::tcl::info::exists
	{::info frame} ::tcl::info::frame
	{::info functions} ::tcl::info::functions
	{::info globals} ::tcl::info::globals
	{::info hostname} ::tcl::info::hostname
	{::info level} ::tcl::info::level
	{::info library} ::tcl::info::library
	{::info loaded} ::tcl::info::loaded
	{::info locals} ::tcl::info::locals
	{::info nameofexecutable} ::tcl::info::nameofexecutable
	{::info patchlevel} ::tcl::info::patchlevel
	{::info procs} ::tcl::info::procs
	{::info script} ::tcl::info::script
	{::info sharedlibextension} ::tcl::info::sharedlibextension
	{::info tclversion} ::tcl::info::tclversion
	{::info vars} ::tcl::info::vars
	{::info object} ::oo::InfoObject
	{::info object call} ::oo::InfoObject::call
	{::info object class} ::oo::InfoObject::class
	{::info object definition} ::oo::InfoObject::definition
	{::info object filters} ::oo::InfoObject::filters
	{::info object forward} ::oo::InfoObject::forward
	{::info object isa} ::oo::InfoObject::isa
	{::info object methods} ::oo::InfoObject::methods
	{::info object methodtype} ::oo::InfoObject::methodtype
	{::info object mixins} ::oo::InfoObject::mixins
	{::info object namespace} ::oo::InfoObject::namespace
	{::info object variables} ::oo::InfoObject::variables
	{::info object vars} ::oo::InfoObject::vars
	{::info class} ::oo::InfoClass
	{::info class call} ::oo::InfoClass::call
	{::info class constructor} ::oo::InfoClass::constructor
	{::info class definition} ::oo::InfoClass::definition
	{::info class destructor} ::oo::InfoClass::destructor
	{::info class filters} ::oo::InfoClass::filters
	{::info class forward} ::oo::InfoClass::forward
	{::info class instances} ::oo::InfoClass::instances
	{::info class methods} ::oo::InfoClass::methods
	{::info class methodtype} ::oo::InfoClass::methodtype
	{::info class mixins} ::oo::InfoClass::mixins
	{::info class subclasses} ::oo::InfoClass::subclasses
	{::info class superclasses} ::oo::InfoClass::superclasses
	{::info class variables} ::oo::InfoClass::variables
	::split ::split
	::array ::array
	{::array anymore} ::tcl::array::anymore
	{::array donesearch} ::tcl::array::donesearch
	{::array exists} ::tcl::array::exists
	{::array get} ::tcl::array::get
	{::array names} ::tcl::array::names
	{::array nextelement} ::tcl::array::nextelement
	{::array set} ::tcl::array::set
	{::array size} ::tcl::array::size
	{::array startsearch} ::tcl::array::startsearch
	{::array statistics} ::tcl::array::statistics
	{::array unset} ::tcl::array::unset
	::if ::if
	::fconfigure ::fconfigure
	::coroutine ::coroutine
	::concat ::concat
	::join ::join
	::lreplace ::lreplace
	::source ::source
	::fcopy ::fcopy
	::global ::global
	::switch ::switch
	::auto_qualify ::auto_qualify
	::update ::update
	::close ::close
	::cd ::cd
	::for ::for
	::auto_load ::auto_load
	::file ::file
	{::file atime} ::tcl::file::atime
	{::file attributes} ::tcl::file::attributes
	{::file channels} ::tcl::file::channels
	{::file copy} ::tcl::file::copy
	{::file delete} ::tcl::file::delete
	{::file dirname} ::tcl::file::dirname
	{::file executable} ::tcl::file::executable
	{::file exists} ::tcl::file::exists
	{::file extension} ::tcl::file::extension
	{::file isdirectory} ::tcl::file::isdirectory
	{::file isfile} ::tcl::file::isfile
	{::file join} ::tcl::file::join
	{::file link} ::tcl::file::link
	{::file lstat} ::tcl::file::lstat
	{::file mtime} ::tcl::file::mtime
	{::file mkdir} ::tcl::file::mkdir
	{::file nativename} ::tcl::file::nativename
	{::file normalize} ::tcl::file::normalize
	{::file owned} ::tcl::file::owned
	{::file pathtype} ::tcl::file::pathtype
	{::file readable} ::tcl::file::readable
	{::file readlink} ::tcl::file::readlink
	{::file rename} ::tcl::file::rename
	{::file rootname} ::tcl::file::rootname
	{::file separator} ::tcl::file::separator
	{::file size} ::tcl::file::size
	{::file split} ::tcl::file::split
	{::file stat} ::tcl::file::stat
	{::file system} ::tcl::file::system
	{::file tail} ::tcl::file::tail
	{::file tempfile} ::tcl::file::tempfile
	{::file type} ::tcl::file::type
	{::file volumes} ::tcl::file::volumes
	{::file writable} ::tcl::file::writable
	::append ::append
	::lreverse ::lreverse
	::format ::format
	::lmap ::lmap
	::unload ::unload
	::read ::read
	::package ::package
	::set ::set
	::namespace ::namespace
	{::namespace children} ::tcl::namespace::children
	{::namespace code} ::tcl::namespace::code
	{::namespace current} ::tcl::namespace::current
	{::namespace delete} ::tcl::namespace::delete
	{::namespace ensemble} ::tcl::namespace::ensemble
	{::namespace eval} ::tcl::namespace::eval
	{::namespace exists} ::tcl::namespace::exists
	{::namespace export} ::tcl::namespace::export
	{::namespace forget} ::tcl::namespace::forget
	{::namespace import} ::tcl::namespace::import
	{::namespace inscope} ::tcl::namespace::inscope
	{::namespace origin} ::tcl::namespace::origin
	{::namespace parent} ::tcl::namespace::parent
	{::namespace path} ::tcl::namespace::path
	{::namespace qualifiers} ::tcl::namespace::qualifiers
	{::namespace tail} ::tcl::namespace::tail
	{::namespace unknown} ::tcl::namespace::unknown
	{::namespace upvar} ::tcl::namespace::upvar
	{::namespace which} ::tcl::namespace::which
	::binary ::binary
	{::binary format} ::tcl::binary::format
	{::binary scan} ::tcl::binary::scan
	{::binary encode} ::tcl::binary::encode
	{::binary encode hex} ::tcl::binary::encode::hex
	{::binary encode uuencode} ::tcl::binary::encode::uuencode
	{::binary encode base64} ::tcl::binary::encode::base64
	{::binary decode} ::tcl::binary::decode
	{::binary decode hex} ::tcl::binary::decode::hex
	{::binary decode uuencode} ::tcl::binary::decode::uuencode
	{::binary decode base64} ::tcl::binary::decode::base64
	::scan ::scan
	::apply ::apply
	::trace ::trace
	::seek ::seek
	::zlib ::zlib
	::while ::while
	::chan ::chan
	{::chan blocked} ::tcl::chan::blocked
	{::chan close} ::tcl::chan::close
	{::chan copy} ::tcl::chan::copy
	{::chan create} ::tcl::chan::create
	{::chan eof} ::tcl::chan::eof
	{::chan event} ::tcl::chan::event
	{::chan flush} ::tcl::chan::flush
	{::chan gets} ::tcl::chan::gets
	{::chan names} ::tcl::chan::names
	{::chan pending} ::tcl::chan::pending
	{::chan pipe} ::tcl::chan::pipe
	{::chan pop} ::tcl::chan::pop
	{::chan postevent} ::tcl::chan::postevent
	{::chan push} ::tcl::chan::push
	{::chan puts} ::tcl::chan::puts
	{::chan read} ::tcl::chan::read
	{::chan seek} ::tcl::chan::seek
	{::chan tell} ::tcl::chan::tell
	{::chan truncate} ::tcl::chan::truncate
	{::chan configure} ::fconfigure
	::flush ::flush
	::after ::after
	::vwait ::vwait
	::dict ::dict
	{::dict append} ::tcl::dict::append
	{::dict create} ::tcl::dict::create
	{::dict exists} ::tcl::dict::exists
	{::dict filter} ::tcl::dict::filter
	{::dict for} ::tcl::dict::for
	{::dict get} ::tcl::dict::get
	{::dict incr} ::tcl::dict::incr
	{::dict info} ::tcl::dict::info
	{::dict keys} ::tcl::dict::keys
	{::dict lappend} ::tcl::dict::lappend
	{::dict map} ::tcl::dict::map
	{::dict merge} ::tcl::dict::merge
	{::dict remove} ::tcl::dict::remove
	{::dict replace} ::tcl::dict::replace
	{::dict set} ::tcl::dict::set
	{::dict size} ::tcl::dict::size
	{::dict unset} ::tcl::dict::unset
	{::dict update} ::tcl::dict::update
	{::dict values} ::tcl::dict::values
	{::dict with} ::tcl::dict::with
	::uplevel ::uplevel
	::continue ::continue
	::try ::try
	::foreach ::foreach
	::lset ::lset
	::rename ::rename
	::fileevent ::fileevent
	::yieldto ::yieldto
	::regexp ::regexp
	::lrepeat ::lrepeat
	::upvar ::upvar
	::tailcall ::tailcall
	::encoding ::encoding
	::expr ::expr
	::unset ::unset
	::load ::load
	::regsub ::regsub
	::interp ::interp
	::exit ::exit
	::puts ::puts
	::incr ::incr
	::lindex ::lindex
	::lsort ::lsort
	::tclLog ::tclLog
	::string ::string
	{::string bytelength} ::tcl::string::bytelength
	{::string cat} ::tcl::string::cat
	{::string compare} ::tcl::string::compare
	{::string equal} ::tcl::string::equal
	{::string first} ::tcl::string::first
	{::string index} ::tcl::string::index
	{::string is} ::tcl::string::is
	{::string last} ::tcl::string::last
	{::string length} ::tcl::string::length
	{::string map} ::tcl::string::map
	{::string match} ::tcl::string::match
	{::string range} ::tcl::string::range
	{::string repeat} ::tcl::string::repeat
	{::string replace} ::tcl::string::replace
	{::string reverse} ::tcl::string::reverse
	{::string tolower} ::tcl::string::tolower
	{::string toupper} ::tcl::string::toupper
	{::string totitle} ::tcl::string::totitle
	{::string trim} ::tcl::string::trim
	{::string trimleft} ::tcl::string::trimleft
	{::string trimright} ::tcl::string::trimright
	{::string wordend} ::tcl::string::wordend
	{::string wordstart} ::tcl::string::wordstart
	::yield ::yield
}

set ::procmap::arghelp {
	::after {arghelps {{option ?arg ...?}}}
	::append {arghelps {{varName ?value ...?}}}
	::apply {arghelps {{lambdaExpr ?arg ...?}}}
	::array {arghelps {{subcommand ?arg ...?}} subcommands {anymore donesearch exists get names nextelement set size startsearch statistics unset}}
	{::array anymore} {arghelps {{arrayName searchId}}}
	{::array donesearch} {arghelps {{arrayName searchId}}}
	{::array exists} {arghelps arrayName}
	{::array get} {arghelps {{arrayName ?pattern?}}}
	{::array names} {arghelps {{arrayName ?mode? ?pattern?}}}
	{::array nextelement} {arghelps {{arrayName searchId}}}
	{::array set} {arghelps {{arrayName list}}}
	{::array size} {arghelps arrayName}
	{::array startsearch} {arghelps arrayName}
	{::array statistics} {arghelps arrayName}
	{::array unset} {arghelps {{arrayName ?pattern?}}}
	::auto_execok {arghelps name}
	::auto_import {arghelps pattern}
	::auto_load {arghelps {{cmd ?namespace?}}}
	::auto_load_index {arghelps {{}}}
	::auto_qualify {arghelps {{cmd namespace}}}
	::binary {arghelps {{subcommand ?arg ...?}} subcommands {decode encode format scan}}
	{::binary decode} {arghelps {{subcommand ?arg ...?}} subcommands {base64 hex uuencode}}
	{::binary decode base64} {arghelps {{?options? data}}}
	{::binary decode hex} {arghelps {{?options? data}}}
	{::binary decode uuencode} {arghelps {{?options? data}}}
	{::binary encode} {arghelps {{subcommand ?arg ...?}} subcommands {base64 hex uuencode}}
	{::binary encode base64} {arghelps {{?-maxlen len? ?-wrapchar char? data}}}
	{::binary encode hex} {arghelps data}
	{::binary encode uuencode} {arghelps {{?-maxlen len? ?-wrapchar char? data}}}
	{::binary format} {arghelps {{formatString ?arg ...?}}}
	{::binary scan} {arghelps {{value formatString ?varName ...?}}}
	::break {arghelps ::break}
	::case {arghelps {{string ?in? ?pattern body ...? ?default body?}}}
	::catch {arghelps {{script ?resultVarName? ?optionVarName?}}}
	::cd {arghelps ?dirName?}
	::chan {arghelps {{subcommand ?arg ...?}} subcommands {blocked close configure copy create eof event flush gets names pending pipe pop postevent push puts read seek tell truncate}}
	{::chan blocked} {arghelps channelId}
	{::chan close} {arghelps {{channelId ?direction?}}}
	{::chan configure} {arghelps {{channelId ?-option value ...?}}}
	{::chan copy} {arghelps {{input output ?-size size? ?-command callback?}}}
	{::chan create} {arghelps {{mode cmdprefix}}}
	{::chan eof} {arghelps channelId}
	{::chan event} {arghelps {{channelId event ?script?}}}
	{::chan flush} {arghelps channelId}
	{::chan gets} {arghelps {{channelId ?varName?}}}
	{::chan names} {arghelps ?pattern?}
	{::chan pending} {arghelps {{mode channelId}}}
	{::chan pipe} {arghelps {{}}}
	{::chan pop} {arghelps channel}
	{::chan postevent} {arghelps {{channel eventspec}}}
	{::chan push} {arghelps {{channel cmdprefix}}}
	{::chan puts} {arghelps {{?-nonewline? ?channelId? string}}}
	{::chan read} {arghelps {{channelId ?numChars?} {?-nonewline? channelId}}}
	{::chan seek} {arghelps {{channelId offset ?origin?}}}
	{::chan tell} {arghelps channelId}
	{::chan truncate} {arghelps {{channelId ?length?}}}
	::clock {arghelps {{subcommand ?arg ...?}} subcommands {add clicks format microseconds milliseconds scan seconds}}
	{::clock add} {arghelps {{clockval ?arg ...?}}}
	{::clock clicks} {arghelps ?-switch?}
	{::clock format} {arghelps {{format clockval ?-format string? ?-gmt boolean? ?-locale LOCALE? ?-timezone ZONE?}}}
	{::clock microseconds} {arghelps {{}}}
	{::clock milliseconds} {arghelps {{}}}
	{::clock scan} {arghelps {{scan string ?-base seconds? ?-format string? ?-gmt boolean? ?-locale LOCALE? ?-timezone ZONE?}}}
	{::clock seconds} {arghelps {{}}}
	::close {arghelps {{channelId ?direction?}}}
	::continue {arghelps ::continue}
	::coroutine {arghelps {{name cmd ?arg ...?}}}
	::dict {arghelps {{subcommand ?arg ...?}} subcommands {append create exists filter for get incr info keys lappend map merge remove replace set size unset update values with}}
	{::dict append} {arghelps {{dictVarName key ?value ...?}}}
	{::dict create} {arghelps {{?key value ...?}}}
	{::dict exists} {arghelps {{dictionary key ?key ...?}}}
	{::dict filter} {arghelps {{dictionary filterType ?arg ...?}}}
	{::dict for} {arghelps {{{keyVarName valueVarName} dictionary script}}}
	{::dict get} {arghelps {{dictionary ?key ...?}}}
	{::dict incr} {arghelps {{dictVarName key ?increment?}}}
	{::dict info} {arghelps dictionary}
	{::dict keys} {arghelps {{dictionary ?pattern?}}}
	{::dict lappend} {arghelps {{dictVarName key ?value ...?}}}
	{::dict map} {arghelps {{{keyVarName valueVarName} dictionary script}}}
	{::dict remove} {arghelps {{dictionary ?key ...?}}}
	{::dict replace} {arghelps {{dictionary ?key value ...?}}}
	{::dict set} {arghelps {{dictVarName key ?key ...? value}}}
	{::dict size} {arghelps dictionary}
	{::dict unset} {arghelps {{dictVarName key ?key ...?}}}
	{::dict update} {arghelps {{dictVarName key varName ?key varName ...? script}}}
	{::dict values} {arghelps {{dictionary ?pattern?}}}
	{::dict with} {arghelps {{dictVarName ?key ...? script}}}
	::encoding {arghelps {{option ?arg ...?}}}
	::eof {arghelps channelId}
	::error {arghelps {{message ?errorInfo? ?errorCode?}}}
	::eval {arghelps {{arg ?arg ...?}}}
	::exec {arghelps {{?-option ...? arg ?arg ...?}}}
	::exit {arghelps ?returnCode?}
	::expr {arghelps {{arg ?arg ...?}}}
	::fblocked {arghelps channelId}
	::fconfigure {arghelps {{channelId ?-option value ...?}}}
	::fcopy {arghelps {{input output ?-size size? ?-command callback?}}}
	::file {arghelps {{subcommand ?arg ...?}} subcommands {atime attributes channels copy delete dirname executable exists extension isdirectory isfile join link lstat mkdir mtime nativename normalize owned pathtype readable readlink rename rootname separator size split stat system tail tempfile type volumes writable}}
	{::file atime} {arghelps {{name ?time?}}}
	{::file attributes} {arghelps {{name ?-option value ...?}}}
	{::file channels} {arghelps ?pattern?}
	{::file copy} {arghelps {{?-option value ...? source ?source ...? target}}}
	{::file dirname} {arghelps name}
	{::file executable} {arghelps name}
	{::file exists} {arghelps name}
	{::file extension} {arghelps name}
	{::file isdirectory} {arghelps name}
	{::file isfile} {arghelps name}
	{::file join} {arghelps {{name ?name ...?}}}
	{::file link} {arghelps {{?-linktype? linkname ?target?}}}
	{::file lstat} {arghelps {{name varName}}}
	{::file mtime} {arghelps {{name ?time?}}}
	{::file nativename} {arghelps name}
	{::file normalize} {arghelps name}
	{::file owned} {arghelps name}
	{::file pathtype} {arghelps name}
	{::file readable} {arghelps name}
	{::file readlink} {arghelps name}
	{::file rename} {arghelps {{?-option value ...? source ?source ...? target}}}
	{::file rootname} {arghelps name}
	{::file separator} {arghelps ?name?}
	{::file size} {arghelps name}
	{::file split} {arghelps name}
	{::file stat} {arghelps {{name varName}}}
	{::file system} {arghelps name}
	{::file tail} {arghelps name}
	{::file tempfile} {arghelps {{?nameVar? ?template?}}}
	{::file type} {arghelps name}
	{::file volumes} {arghelps {{}}}
	{::file writable} {arghelps name}
	::fileevent {arghelps {{channelId event ?script?}}}
	::flush {arghelps channelId}
	::for {arghelps {{start test next command}}}
	::foreach {arghelps {{varList list ?varList list ...? command}}}
	::format {arghelps {{formatString ?arg ...?}}}
	::gets {arghelps {{channelId ?varName?}}}
	::incr {arghelps {{varName ?increment?}}}
	::info {arghelps {{subcommand ?arg ...?}} subcommands {args body class cmdcount commands complete coroutine default errorstack exists frame functions globals hostname level library loaded locals nameofexecutable object patchlevel procs script sharedlibextension tclversion vars}}
	{::info args} {arghelps procname}
	{::info body} {arghelps procname}
	{::info class} {arghelps {{subcommand ?arg ...?}} subcommands {call constructor definition destructor filters forward instances methods methodtype mixins subclasses superclasses variables}}
	{::info class call} {arghelps {{className methodName}}}
	{::info class constructor} {arghelps className}
	{::info class definition} {arghelps {{className methodName}}}
	{::info class destructor} {arghelps className}
	{::info class filters} {arghelps className}
	{::info class forward} {arghelps {{className methodName}}}
	{::info class instances} {arghelps {{className ?pattern?}}}
	{::info class methods} {arghelps {{className ?-option value ...?}}}
	{::info class methodtype} {arghelps {{className methodName}}}
	{::info class mixins} {arghelps className}
	{::info class subclasses} {arghelps {{className ?pattern?}}}
	{::info class superclasses} {arghelps className}
	{::info class variables} {arghelps className}
	{::info cmdcount} {arghelps {{}}}
	{::info commands} {arghelps ?pattern?}
	{::info complete} {arghelps command}
	{::info coroutine} {arghelps {{}}}
	{::info default} {arghelps {{procname arg varname}}}
	{::info errorstack} {arghelps ?interp?}
	{::info exists} {arghelps varName}
	{::info frame} {arghelps ?number?}
	{::info functions} {arghelps ?pattern?}
	{::info globals} {arghelps ?pattern?}
	{::info hostname} {arghelps {{}}}
	{::info level} {arghelps ?number?}
	{::info library} {arghelps {{}}}
	{::info loaded} {arghelps ?interp?}
	{::info locals} {arghelps ?pattern?}
	{::info nameofexecutable} {arghelps {{}}}
	{::info object} {arghelps {{subcommand ?arg ...?}} subcommands {call class definition filters forward isa methods methodtype mixins namespace variables vars}}
	{::info object call} {arghelps {{objName methodName}}}
	{::info object class} {arghelps {{objName ?className?}}}
	{::info object definition} {arghelps {{objName methodName}}}
	{::info object filters} {arghelps objName}
	{::info object forward} {arghelps {{objName methodName}}}
	{::info object isa} {arghelps {{category objName ?arg ...?}}}
	{::info object methods} {arghelps {{objName ?-option value ...?}}}
	{::info object methodtype} {arghelps {{objName methodName}}}
	{::info object mixins} {arghelps objName}
	{::info object namespace} {arghelps objName}
	{::info object variables} {arghelps objName}
	{::info object vars} {arghelps {{objName ?pattern?}}}
	{::info patchlevel} {arghelps {{}}}
	{::info procs} {arghelps ?pattern?}
	{::info script} {arghelps ?filename?}
	{::info sharedlibextension} {arghelps {{}}}
	{::info tclversion} {arghelps {{}}}
	{::info vars} {arghelps ?pattern?}
	::interp {arghelps {{cmd ?arg ...?}}}
	::join {arghelps {{list ?joinString?}}}
	::lappend {arghelps {{varName ?value ...?}}}
	::lassign {arghelps {{list ?varName ...?}}}
	::lindex {arghelps {{list ?index ...?}}}
	::linsert {arghelps {{list index ?element ...?}}}
	::llength {arghelps list}
	::lmap {arghelps {{varList list ?varList list ...? command}}}
	::load {arghelps {{?-global? ?-lazy? ?--? fileName ?packageName? ?interp?}}}
	::lrange {arghelps {{list first last}}}
	::lrepeat {arghelps {{count ?value ...?}}}
	::lreplace {arghelps {{list first last ?element ...?}}}
	::lreverse {arghelps list}
	::lsearch {arghelps {{?-option value ...? list pattern}}}
	::lset {arghelps {{listVar ?index? ?index ...? value}}}
	::lsort {arghelps {{?-option value ...? list}}}
	::namespace {arghelps {{subcommand ?arg ...?}} subcommands {children code current delete ensemble eval exists export forget import inscope origin parent path qualifiers tail unknown upvar which}}
	{::namespace children} {arghelps {{?name? ?pattern?}}}
	{::namespace code} {arghelps arg}
	{::namespace current} {arghelps {{}}}
	{::namespace ensemble} {arghelps {{subcommand ?arg ...?}} subcommands {configure create exists}}
	{::namespace eval} {arghelps {{name arg ?arg...?}}}
	{::namespace exists} {arghelps name}
	{::namespace inscope} {arghelps {{name arg ?arg...?}}}
	{::namespace origin} {arghelps name}
	{::namespace parent} {arghelps ?name?}
	{::namespace path} {arghelps ?pathList?}
	{::namespace qualifiers} {arghelps string}
	{::namespace tail} {arghelps string}
	{::namespace unknown} {arghelps ?script?}
	{::namespace upvar} {arghelps {{ns ?otherVar myVar ...?}}}
	{::namespace which} {arghelps {{?-command? ?-variable? name}}}
	::open {arghelps {{fileName ?access? ?permissions?}}}
	::package {arghelps {{option ?arg ...?}}}
	::pid {arghelps ?channelId?}
	::proc {arghelps {{name args body}}}
	::puts {arghelps {{?-nonewline? ?channelId? string}}}
	::pwd {arghelps {{}}}
	::read {arghelps {{channelId ?numChars?} {?-nonewline? channelId}}}
	::regexp {arghelps {{?-option ...? exp string ?matchVar? ?subMatchVar ...?}}}
	::regsub {arghelps {{?-option ...? exp string subSpec ?varName?}}}
	::rename {arghelps {{oldName newName}}}
	::scan {arghelps {{string format ?varName ...?}}}
	::seek {arghelps {{channelId offset ?origin?}}}
	::set {arghelps {{varName ?newValue?}}}
	::socket {arghelps {{?-myaddr addr? ?-myport myport? ?-async? host port} {-server command ?-myaddr addr? port}}}
	::source {arghelps {{?-encoding name? fileName}}}
	::split {arghelps {{string ?splitChars?}}}
	::string {arghelps {{subcommand ?arg ...?}} subcommands {bytelength cat compare equal first index is last length map match range repeat replace reverse tolower totitle toupper trim trimleft trimright wordend wordstart}}
	{::string bytelength} {arghelps string}
	{::string compare} {arghelps {{?-nocase? ?-length int? string1 string2}}}
	{::string equal} {arghelps {{?-nocase? ?-length int? string1 string2}}}
	{::string first} {arghelps {{needleString haystackString ?startIndex?}}}
	{::string index} {arghelps {{string charIndex}}}
	{::string is} {arghelps {{class ?-strict? ?-failindex var? str}}}
	{::string last} {arghelps {{needleString haystackString ?startIndex?}}}
	{::string length} {arghelps string}
	{::string map} {arghelps {{?-nocase? charMap string}}}
	{::string match} {arghelps {{?-nocase? pattern string}}}
	{::string range} {arghelps {{string first last}}}
	{::string repeat} {arghelps {{string count}}}
	{::string replace} {arghelps {{string first last ?string?}}}
	{::string reverse} {arghelps string}
	{::string tolower} {arghelps {{string ?first? ?last?}}}
	{::string totitle} {arghelps {{string ?first? ?last?}}}
	{::string toupper} {arghelps {{string ?first? ?last?}}}
	{::string trim} {arghelps {{string ?chars?}}}
	{::string trimleft} {arghelps {{string ?chars?}}}
	{::string trimright} {arghelps {{string ?chars?}}}
	{::string wordend} {arghelps {{string index}}}
	{::string wordstart} {arghelps {{string index}}}
	::subst {arghelps {{?-nobackslashes? ?-nocommands? ?-novariables? string}}}
	::switch {arghelps {{?-option ...? string ?pattern body ...? ?default body?}}}
	::tclLog {arghelps string}
	::tell {arghelps channelId}
	::throw {arghelps {{type message}}}
	::time {arghelps {{command ?count?}}}
	::trace {arghelps {{option ?arg ...?}}}
	::try {arghelps {{body ?handler ...? ?finally script?}}}
	::unload {arghelps {{?-switch ...? fileName ?packageName? ?interp?}}}
	::update {arghelps ?idletasks?}
	::uplevel {arghelps {{?level? command ?arg ...?}}}
	::upvar {arghelps {{?level? otherVar localVar ?otherVar localVar ...?}}}
	::vwait {arghelps name}
	::while {arghelps {{test command}}}
	::zlib {arghelps {{command arg ?...?}} subcommands {adler32 compress crc32 decompress deflate gunzip gzip inflate push stream}}
	{::namespace ensemble configure} {arghelps {{cmdname ?-option value ...? ?arg ...?}}}
	{::namespace ensemble create} {arghelps {{?option value ...?}}}
	{::namespace ensemble exists} {arghelps cmdname}
	{::zlib adler32} {arghelps {{data ?startValue?}}}
	{::zlib compress} {arghelps {{data ?level?}}}
	{::zlib crc32} {arghelps {{data ?startValue?}}}
	{::zlib decompress} {arghelps {{data ?bufferSize?}}}
	{::zlib deflate} {arghelps {{data ?level?}}}
	{::zlib gunzip} {arghelps {{data ?-headerVar varName?}}}
	{::zlib gzip} {arghelps {{data ?-level level? ?-header header?}}}
	{::zlib inflate} {arghelps {{data ?bufferSize?}}}
	{::zlib push} {arghelps {{mode channel ?options...?}}}
	{::zlib stream} {arghelps {{mode ?-option value...?}}}
}

