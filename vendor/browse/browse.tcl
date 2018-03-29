# -*- tcl -*-
# # ## ### ##### ######## ############# #####################

## Copyright (c) 2011-2012 ActiveState Software Inc.
## See file license.txt for the license terms.

# # ## ### ##### ######## ############# #####################
# Open browser for url ...
#
# Derived from the internal devkit/lib/help package, without
# the dependency on Tk.

# ### ######### ###########################
# Requisites

package require Tcl 8.5

namespace eval ::browse {}

# Dummy debugger proc for compatibility.
proc debug.browse args {
}

# ### ######### ###########################
# public API

proc ::browse::url {url} {
    debug.browse {}

    global tcl_platform

    if {$tcl_platform(platform) eq "windows"} {
        WinOpenUrl $url
    } elseif {$tcl_platform(os) eq "Darwin"} {
        MacOpenUrl $url
    } else {
        UnixOpenUrl $url
    }
    return
}

# ### ######### ###########################
# Internal commands

proc ::browse::WinOpenUrl {url} {
    debug.browse {}

    # Perform basic url quoting and escape &'s in url ...
    set url [string map {{ } %20 & ^&} $url]

    debug.browse {exec $::env(COMSPEC) /c start ($url)}
    if {[catch {
        exec >NUL: <NUL: $::env(COMSPEC) /c start $url &
    } msg]} {
        Fail $url $msg
    }
    return
}


proc ::browse::MacOpenUrl {url} {
    debug.browse {}

    set url [string map {{ } %20} $url]

    debug.browse {exec open ($url)}
    if {[catch {
        #package require Tclapplescript
        #AppleScript execute "do shell script \"open $url\""
        exec open $url &
    } msg]} {
        Fail $url $msg
    }
}

proc ::browse::UnixOpenUrl {url} {
    debug.browse {}
    set redir ">&/dev/null </dev/null"

    if {[info exists ::env(BROWSER)]} {
        set browser $::env(BROWSER)
    }

    if {[info exists ::env(DISPLAY)]} {
        expr {
              [info exists browser]              ||
              [FindExecutable xdg-open  browser] ||
              [FindExecutable chrome    browser] ||
              [FindExecutable firefox   browser] ||
              [FindExecutable mozilla   browser] ||
              [FindExecutable netscape  browser] ||
              [FindExecutable iexplorer browser] ||
              [FindExecutable opera     browser] ||
              [FindExecutable lynx      browser]
          }
    } else {
        # Terminal only.
        expr {
              [info exists browser]              ||
              [FindExecutable xdg-open  browser] ||
              [FindExecutable lynx      browser]
          }
    }

    # lynx can also output formatted text to a variable
    # with the -dump option, as a last resort:
    # set formatted_text [ exec lynx -dump $url ] - PSE

    if {![info exists browser]} {
        Fail $url "Could not find a browser to use"
        #return -code error "Could not find a browser to use"
    }

    if {[string equal [file tail $browser] netscape]} {
        # -remote url is not understood, only
        # -remote openUrl(url)
        if {
            [catch {RunBrowser $browser -remote openUrl($url) } msg] &&
            [catch {RunBrowser $browser                 $url &} msg]
        } {
            Fail $url "Browser \"$browser\": $msg"
        }
    } else {
        # Assume that browser may understand -remote url
        # perhaps browser doesn't understand -remote flag
        if {
            [catch {RunBrowser $browser -remote $url  } msg] &&
            [catch {RunBrowser $browser         $url &} msg]
        } {
            Fail $url "Browser \"$browser\": $msg"
        }
    }
    return
}

proc ::browse::Fail {url msg} {
    debug.browse {}

    set msg "Error displaying url \"$url\":\n$msg"
    if {[catch {package present Tk}]} {
        return -code error -errorcode {BROWSE FAIL} $msg
    } else {
        tk_messageBox \
            -title "Error displaying URL" \
            -icon error \
            -type ok \
            -message $msg
    }
    return
}

proc ::browse::FindExecutable {progname varname} {
    debug.browse {}

    upvar 1 $varname result
    set progs [auto_execok $progname]
    if {[llength $progs]} {
        set result [lindex $progs 0]
    }
    return [llength $progs]
}

proc ::browse::RunBrowser {args} {
    debug.browse {}
    eval exec $args
}

# ### ######### ###########################
# Define, initialize datastructures.

namespace eval ::browse {
    namespace export url
    namespace ensemble create
}

# ### ######### ###########################
# Ready

package provide browse 0
