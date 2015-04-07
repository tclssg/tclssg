# DustMote HTTP server by Harold Kaplan (wiki.tcl.tk/4333) with changes by
# Danyil Bohdan.
# License: public domain.

namespace eval ::tclssg::webserver {
    variable root
    variable host
    variable port
    variable default

    variable verbose 0
}

proc ::tclssg::webserver::answer {socketChannel host2 port2} {
    fileevent $socketChannel readable \
            [list ::tclssg::webserver::read-it $socketChannel]
}

proc ::tclssg::webserver::read-it {socketChannel} {
    variable root
    variable default
    variable verbose
    fconfigure $socketChannel -blocking 0

    # Parse the request to extract the filename.
    set gotLine [gets $socketChannel]
    if { [fblocked $socketChannel] } {
        return
    }
    fileevent $socketChannel readable ""
    set shortName "/"
    regexp {GET (/[^ ]*)} $gotLine _ shortName
    set shortNameLength [string length $shortName]
    set lastChar [string index $shortName [expr { $shortNameLength - 1 }] ]
    if {$lastChar eq "/"} {
        set shortName $shortName$default
    }
    set wholeName $root$shortName

    # Return data.
    if {[catch {set fileChannel [open $wholeName RDONLY] } ]} {
        if {$verbose} { puts "404 $shortName" }
        puts $socketChannel "HTTP/1.0 404 Not found"
        puts $socketChannel ""
        puts $socketChannel "<!DOCTYPE html>"
        puts $socketChannel "<html><head><title>No such URL.</title></head>"
        puts $socketChannel "<body><h1>"
        puts $socketChannel "The URL you requested does not exist."
        puts $socketChannel "</h1></body></html>"
        close $socketChannel
    } else {
        if {$verbose} { puts "200 $shortName" }
        fconfigure $fileChannel -translation binary
        fconfigure $socketChannel -translation binary -buffering full
        puts $socketChannel "HTTP/1.0 200 OK"
        puts $socketChannel ""
        fcopy $fileChannel $socketChannel \
                -command [list ::tclssg::webserver::done \
                        $fileChannel $socketChannel]
    }
}

proc ::tclssg::webserver::done {inChan outChan args} {
    close $inChan
    close $outChan
}

proc ::tclssg::webserver::serve {serverRoot {serverPort 8080}
        {serverHost localhost} {defaultFile "index.html"}} {
    variable root
    variable host
    variable port
    variable default
    set root [file normalize $serverRoot]
    set host $serverHost
    set port $serverPort
    set default $defaultFile

    puts "serving path $root on $host port $port"
    socket -server ::tclssg::webserver::answer -myaddr $host $port
    vwait forever
}
