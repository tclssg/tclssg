# DustMote HTTP server by Harold Kaplan (wiki.tcl.tk/4333) with changes by
# Danyil Bohdan.
# This code is in the public domain.
package require Tcl 8.5

namespace eval ::tclssg::webserver {
    variable root
    variable host
    variable port
    variable default
    variable verbose

    variable handlers {}

    variable mimeTypeByExtension {
        .c      text/plain
        .conf   text/plain
        .css    text/css
        .csv    text/csv
        .gif    image/gif
        .gz     application/gzip
        .h      text/plain
        .htm    text/html
        .html   text/html
        .jpg    image/jpeg
        .jpeg   image/jpeg
        .js     application/javascript
        .json   application/json
        .pdf    application/pdf
        .png    image/png
        .ps     application/postscript
        .sh     text/plain
        .tcl    text/plain
        .txt    text/plain
        .xhtml  application/xhtml+xml
        .xml    application/xml
        .zip    application/zip
    }
}

# Detect MIME type by file extension. Needed, e.g., to serve RSS feeds.
proc ::tclssg::webserver::mime-type {filename} {
    variable mimeTypeByExtension
    set ext [file extension $filename]
    if {[dict exists $mimeTypeByExtension $ext]} {
        return [dict get $mimeTypeByExtension $ext]
    } else {
        return application/octet-stream
    }
}

# Handles a new connection.
proc ::tclssg::webserver::answer {socketChannel host2 port2} {
    fileevent $socketChannel readable \
            [list ::tclssg::webserver::read-request $socketChannel]
}

# Print $message to standard output if logging is enabled.
proc ::tclssg::webserver::log {message} {
    variable verbose
    if {$verbose} {
        puts $message
    }
}

# Read an HTTP request from a channel and respond once it can be processed.
proc ::tclssg::webserver::read-request {socketChannel} {
    variable root
    variable default
    variable verbose
    variable handlers

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
    if {[dict exists $handlers $shortName]} {
        ::tclssg::webserver::log "Hnd $shortName"
        apply [dict get $handlers $shortName] $socketChannel
    } elseif {[ catch { set fileChannel [open $wholeName RDONLY] } ]} {
        ::tclssg::webserver::log "404 $shortName"
        puts $socketChannel "HTTP/1.0 404 Not found"
        puts $socketChannel "Content-Type: text/html"
        puts $socketChannel ""
        puts $socketChannel "<!DOCTYPE html>"
        puts $socketChannel "<html><head><title>No such URL</title></head>"
        puts $socketChannel "<body><h1>"
        puts $socketChannel "The URL you requested does not exist."
        puts $socketChannel "</h1></body></html>"
        close $socketChannel
    } else {
        ::tclssg::webserver::log "200 $shortName"
        fconfigure $fileChannel -translation binary
        fconfigure $socketChannel -translation binary -buffering full
        puts $socketChannel "HTTP/1.0 200 OK"
        puts $socketChannel "Content-Type: [::tclssg::webserver::mime-type \
                $wholeName]"
        puts $socketChannel ""
        fcopy $fileChannel $socketChannel \
                -command [list ::tclssg::webserver::close-channels \
                        $fileChannel $socketChannel]
    }
}

# Called from read-request to clean up when a file request is completed.
proc ::tclssg::webserver::close-channels {inChan outChan args} {
    close $inChan
    close $outChan
}

# Add a handler $lambda to be called when a client navigates to $route. $lambda
# should be an [apply]-style anonymous function that takes a channel name as its
# only argument. It is up to the handler to close the channel.
proc ::tclssg::webserver::add-handler {route lambda} {
    variable handlers
    dict set handlers $route $lambda
}

# Start an HTTP server and handle requests asynchronously. If you want to wait
# until the server is finished run [vwait ::tclssg::webserver::done].
proc ::tclssg::webserver::serve {serverRoot {serverPort 8080}
        {serverHost localhost} {defaultFile "index.html"} {verboseOutput 0}} {
    variable root
    variable host
    variable port
    variable default
    variable verbose
    set root [file normalize $serverRoot]
    set host $serverHost
    set port $serverPort
    set default $defaultFile
    set verbose $verboseOutput

    puts "serving path $root on $host port $port"
    socket -server ::tclssg::webserver::answer -myaddr $host $port
}
