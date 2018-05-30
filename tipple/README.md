## A simple no-magic Tcl package installer

**T**rivial **i**nstaller for **p**ackages in a **p**ortable **l**ocal **e**nvironment.

Goals:

 * easy for newbie adoption
  * download one script and use it on 8.6+ to set up an env
  * no reliance on any packages not shipped with the core.  `sqlite3` only possible exception
 * access packages from git/fossil repos and teapot
 * use a simple requirements txt format
 * easily consume sensibly-structured source repos without further work on the author's part

Requirements:

 * Tcl 8.6+
 * a unix-like environment (this limitation may be revisited in future)
 * any of `curl`, `wget`, `fetch`
 * for installing from repos, `git`, `fossil`

Non-goals:

 * building extensions from source.  Those can come from a teapot
 * doing more than the 80% necessary to bootstrap newbies
 * installing Tcl


## Synopsis

    ./tipple init DIR

Create a new environment in `DIR`

    . DIR/bin/activate

Set up your environment for working in `DIR`

    DIR/bin/tclsh

Run system `tclsh` with environment from `DIR/bin/activate`.

    tipple install PKG ?VERSION? ?ARCH?
    tipple install REPO-URL ?CHECKOUT?

Add packages to environment, from any of:

 * teapot
 * a local directory or tarball
 * a tarball on the internet
 * a fossil or git repository


## Filesystem

Tipple creates a project directory consisting of:

    bin/                -- executables
    lib/tclX.Y          -- pkgIndex.tcl style packages
    lib/tclX/site-tcl/  -- .tm style modules
    bin/activate        -- source-able script that sets up the environment
    bin/tipple          -- tipple itself
    bin/tclsh           -- wrapper for system tclsh that sources activate first

Also:

    tipple.txt  -- configuration
    src/        -- where source repos/archives get downloaded and unpacked.  Do Not put this in starpacks.


## Environment

`activate` sets up these environment vars, creating new ones or *prefixing* existing ones

    TCL_8.6_TM_PATH     DIR/modules
    TCLLIBPATH          DIR/lib
    PATH                DIR/bin


## Package sources

Packages can be fetched from:

 * teapot:  one of the urls specified in `tipple.txt`
 * tarball:  local or remote path to archive, which must be *well-behaved*
 * filesystem path:  local path to directory, which must be *well-behaved*
 * git repo:  `git+$url`, must be *well-behaved*
 * fossil repo:  `fossil+$url`, must be *well-behaved*

A *well-behaved* package source is expected to Install Correctly by the following means:

    cp -a lib/*     $TCLLIBPATH
    cp -a modules/* $TCL8_6_TM_PATH
    cp -a bin/*     DIR/bin/

It must *not*:

 * rely at runtime on anything not in these directories
 * require path-dependent preprocessing

The source directory will be left around (in `DIR/src`) so users can view documentation and examples in there.

*(means to install packages according to metadata in the form of `tipple.txt` or other "blessed" formats will come soon)*


## Environment Metadata:  `tclenv.txt`

At the root of the environment, `tclenv.txt` records some metadata about the environment.  It looks like:

    # this is a comment, as you might expect
    # empty lines are ignored
    
    tcl_version 8.6
    
    # directories where things are installed to:
    lib_dir     lib/tcl8.6
    tm_dir      lib/tcl8/site-tcl
    
    # teapot repos to use, in order of preference
    teapot https://teapot.rkeene.org/
    teapot https://teapot.activestate.org/
    
    # MAYBE: optionally specify architecture for fetching binary pkgs from teapot
    architecture OS ARCH


## Package Metadata: `tipple.txt`

Tipple looks in the root of any package it installs for `tipple.txt`, which can specify requirements that will be satisfied recursively.  It looks like:

    # this is a comment, as you might expect
    # empty lines are allowed, and ignored
    
    # strictly optional.
    require Tcl 8.6
    
    # require from teapot, latest version
    require package-name
    
    # require from teapot, specific version
    require package-name version
    
    # require from git, latest master or specific checkout
    require git+https://github.com/somebody/somepackage
    require git+https://github.com/somebody/somepackage branch-or-tag-or-commit-id
    
    # require from fossil, latest trunk or specific checkout
    require fossil+https://chiselapp.com/user/somebody/repository/somepackage
    require fossil+https://chiselapp.com/user/somebody/repository/somepackage branch-or-tag-or-commit-id


### Coming soon

A `tipple.txt` file might also want to be written for an upstream repo that we don't control.  This **will** be supported by creating a local `tipple.txt` that can use additional directives:

    provide somepackage 0.1.2
    source https://some.url/tarball.tar.gz
    require some-dependency
    patch some-file.patch


## Use cases (mostly articulated by stevel)

 * I want to install my own copies of packages that are not installed on the system, and I may not have root
 * I want to install a more up-to-date copy of a package that is already installed on the system
 * I want to wrap a script (as a starpack or just an archive) and include a copy of the dependent packages
 * I want to run a script to download and install all the dependencies of a package or script that I have
 * I want to publish a script or package that I have made, so users can easily install it with its dependencies
 * I want to use a modified version of a third-party package in my project


## Inspiration / see also

 * <https://teaparty.rkeene.org/> - `teapot-client` from here is used
 * <https://github.com/wduquette/tcl-quill/>
 * <https://github.com/AngryLawyer/mug/>
 * python's `pip` + `virtualenv`

Related, but beyond the scope of this project:

 * <https://chiselapp.com/user/aspect/repository/sdx/wiki?name=howto>
 * `../hacks/cuppa` has some stuff for processing teapot + gutter metadata
 * <https://sourceforge.net/projects/kbskit/> inspired some of the `tipple.txt` commands

Bigger, more capable but much hairier things:

 * <https://github.com/ActiveState/teapot>
 * <https://core.tcl.tk/akupries/kettle/index>
 * <http://fossil.etoyoc.com/fossil/odie/home>
