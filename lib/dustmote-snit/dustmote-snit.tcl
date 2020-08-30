#!/usr/bin/env tclsh
# DustMote HTTP server originally developed by Harold Kaplan
# (https://wiki.tcl-lang.org/4333).  Modified by D. Bohdan.
# This code is in the public domain.

package require Tcl       8.5
package require fileutil  1
package require html      1
package require ncgi      1
package require snit      2
package require textutil  0-2


namespace eval ::dmsnit {
    variable version 0.15.0
}


::snit::type ::dmsnit::httpd {
    # Basic web server configuration.
    option -root \
            -default {} \
            -configuremethod Set-normalized
    option -host localhost
    option -port 8080
    option -default index.html
    option -verbose 1
    option -dirlists 1

    # TLS options.
    option -certfile \
            -default public.pem \
            -configuremethod Set-normalized \
            -validatemethod Assert-file-exists

    option -keyfile \
            -default private.pem \
            -configuremethod Set-normalized \
            -validatemethod Assert-file-exists

    option -tls \
            -default 0 \
            -configuremethod Set-tls

    # The "done" variable. Whoever creates the server object can vwait on this
    # variable using [vwait [$obj wait-var-name]] until a handler changes it to
    # signal that the server's work is done. Setting the variable to a true
    # value does not stop the server. It needs to be explicitly destroyed with
    # [$obj destroy] for that.
    variable done 0
    # Custom route handlers.
    variable handlers {}
    # The command used to create a new server socket.
    variable socketCommand socket
    # The server socket channel. Does not itself transfer data but can be closed
    # to stop accepting new connections.
    variable socketChannel
    # Connection state (per channel).
    variable connectState {}

    constructor {} {}

    destructor {
        variable socketChannel
        $self log {shutting down}
        close $socketChannel
    }

    # Private methods.

    method Assert-file-exists {option value} {
        if {![file isfile $value]} {
            error "file \"$value\" used for option $option doesn't exist"
        }
    }

    method Set-normalized {option value} {
        set options($option) [::fileutil::fullnormalize $value]
    }

    method Set-tls {option value} {
        if {$option ne {-tls}} {
            error {Set-tls is only for setting the option -tls}
        }

        if {$value} {
            package require tls 1.6.7
            ::tls::init \
                    -certfile [$self cget -certfile] \
                    -keyfile  [$self cget -keyfile] \
                    -ssl2 0 \
                    -ssl3 0 \
                    -tls1 1 \
                    -require 0 \
                    -request 1
            set socketCommand ::tls::socket
        } else {
            set socketCommand socket
        }

        set options(-tls) $value
    }

    # Public methods.

    # Create a server socket and start accepting connections.
    method serve {} {
        variable socketCommand
        variable socketChannel

        set root [$self cget -root]
        set host [$self cget -host]
        set port [$self cget -port]
        set tls [$self cget -tls]

        if {$root eq {}} {
            error {no root set}
        }

        set message "serving path $root on $host port $port"
        if {$tls} {
            append message { with TLS}
        }
        $self log $message

        set socketChannel [$socketCommand \
            -server "$self answer" \
            -myaddr $host $port \
        ]
    }

    # Print $message to standard output if logging is enabled.
    method log message {
        variable verbose
        if {[$self cget -verbose]} {
            puts $message
        }
    }

    # Set up event to run method read-request on $channel when it is readable.
    method wire-channel-reader channel {
        fileevent $channel \
            readable \
            [list $self read-request $channel]
    }

    # Handle a new connection.
    method answer {conn host2 port2} {
        fconfigure $conn -blocking 0 -translation binary
        $self wire-channel-reader $conn
    }

    method return-file {conn filename} {
        set fileSize [file size $filename]
        set fileChannel [open $filename RDONLY]
        fconfigure $fileChannel -translation binary
        fconfigure $conn -buffering full

        set contentLength $fileSize
        send $conn [header \
            {200 OK} \
            [mime::type $filename] \
            $contentLength \
            {Accept-Ranges: bytes} \
        ]

        set cleanUpCommand [list $self clean-up $conn $fileChannel]
        fcopy $fileChannel $conn -command $cleanUpCommand

        $self log "200 $filename"
    }

    method return-file-range {conn filename firstByte lastByte} {
        set fileSize [file size $filename]
        set fileChannel [open $filename RDONLY]
        fconfigure $fileChannel -translation binary
        fconfigure $conn -buffering full

        if {$firstByte >= $fileSize} {
            send $conn [header \
                {416 Range Not Satisfiable} \
                [mime::type $filename] \
                0 \
                "Content-Range: bytes */$fileSize"
            ]

            $self clean-up $conn $fileChannel
            $self log "416 $filename"

            return
        }

        if {$lastByte eq {}} {
            set lastByte [expr { $fileSize - 1 }]
        }
        set contentLength [expr { $lastByte - $firstByte + 1 }]

        set contentRange "Content-Range:\
                          bytes $firstByte-$lastByte/$contentLength"
        send $conn [header \
            {206 Partial Content} \
            [mime::type $filename] \
            $contentLength \
            $contentRange
        ]

        set cleanUpCommand [list $self clean-up $conn $fileChannel]
        seek $fileChannel $firstByte
        fcopy $fileChannel $conn \
            -size $contentLength \
            -command $cleanUpCommand

        $self log "206 $filename"
    }

    method return-404 {conn path} {
        send $conn [response \
            {404 Not Found} \
            text/html \
            [notice-page \
                {404 Not Found} \
                {} \
                {<h1>The URL you requested does not exist.</h1>} \
            ] \
        ]

        $self clean-up $conn
        $self log "404 $path"
    }

    # Write to the channel $conn the list of files and directories at
    # the local path $path formatted as HTML. $path should be an absolute path
    # and *not* one relative to -root.
    method return-dir-list {conn path} {
        set titlePath [file join \
            / \
            [::fileutil::relative [$self cget -root] $path] \
        ]
        if {$titlePath eq {/.}} {
            set titlePath /
        }

        # Redirect the client to "$path/" if necessary to ensure relative links
        # work correctly.
        if {$titlePath ne {/} && ![string match */ $path]} {
            send $conn [response \
                {302 Found} \
                text/html \
                [notice-page \
                    Redirecting... \
                    {} \
                    <h1>Redirecting...</h1> \
                ] \
                "Location: $titlePath/" \
            ]

            $self clean-up $conn
            $self log "302 $path -> $path/"

            return
        }

        foreach varName {dirList fileList} types {d {b c f l p s}} {
            set $varName [lsort \
                -dictionary \
                [glob -directory $path -nocomplain -tails -types $types *] \
            ]
        }

        set formatLink {{path {endSlash 0}} {
            set href [::html::html_entities [::dmsnit::url::encode $path]]
            set text [::html::html_entities $path]

            if {$endSlash} {
                append href /
                append text /
            }

            return "\n            <li><a href=\"$href\">$text</a></li>"
        }}

        set links {}
        foreach dir $dirList {
            lappend links [apply $formatLink $dir 1]
        }
        foreach file $fileList {
            # Skip symlinks to directories.
            if {$file in $dirList} continue
            lappend links [apply $formatLink $file 0]
        }

        set doc [notice-page \
            "Directory listing for [::html::html_entities $titlePath]" \
            {} \
            "<a href=\"..\">Up a level</a>\n       \
             <ul>[join $links {}]\n       \
             </ul>" \
        ]

        send $conn [response \
            {200 OK} \
            text/html \
            $doc \
        ]

        $self clean-up $conn
        $self log "200 $path"
    }

    # Read an HTTP request from a channel and respond once it can be processed.
    method read-request {conn} {
        variable handlers
        fileevent $conn readable {}

        # Read and store a request fragment.
        if {[dict exists $connectState $conn request]} {
            set request [dict get $connectState $conn request]
        } else {
            set request {}
        }
        while { [gets $conn line] >= 0 } {
            lappend request $line
        }
        dict set connectState $conn request $request

        # Return if the request is incomplete. Try again later if the channel is
        # open.
        if {[llength $request] == 0
             || ![string is space [lindex $request end]] } {
            if {![eof $conn]} {
                $self wire-channel-reader $conn
            }
            return
        }

        # Parse the request to extract the filename.
        set shortName /
        regexp {GET /([^ ]*)} $request _ shortName
        set gotRange [regexp \
            {Range: bytes=([0-9]+)(?:-([0-9]+))?} \
            $request \
            _ firstByte lastByte \
        ]
        set wholeName [::fileutil::jail \
            [$self cget -root] \
            [url::decode $shortName] \
        ]
        if {[string match */ $shortName] && ![string match */ $wholeName]} {
            append wholeName /
        }
        if {![string match /* $shortName]} {
            set shortName /$shortName
        }

        # Return data.
        if {[dict exists $handlers $shortName]} {
            $self log "Hnd $shortName"
            apply [dict get $handlers $shortName] $conn
        } else {
            # Default file.
            if {[file isdir $wholeName]} {
                set defaultFile [file join $wholeName [$self cget -default]]
                if {[file isfile $defaultFile]} {
                    set wholeName $defaultFile
                }
            }

            if {[file isfile $wholeName]} {
                if {$gotRange} {
                    $self return-file-range $conn \
                        $wholeName \
                        $firstByte \
                        $lastByte
                } else {
                    $self return-file $conn $wholeName
                }
            } elseif {[$self cget -dirlists] && [file isdir $wholeName]} {
                $self return-dir-list $conn $wholeName
            } else {
                $self return-404 $conn $wholeName
            }
        }
    }

    # Called from read-request to clean up when a file request is completed.
    method clean-up {conn {fileChannel {}} args} {
        close $conn
        dict unset connectState $conn

        if {$fileChannel ne {}} {
            close $fileChannel
        }
    }

    # Add a new handler $lambda to be called when a client requests the URL
    # $route. $lambda should be an [apply]-style anonymous function that takes a
    # channel name as its only argument. It is up to the handler to close the
    # channel.
    method add-handler {route lambda} {
        variable handlers
        dict set handlers $route $lambda
    }

    # Return the fully qualified name of the "done" variable for the current
    # object.
    method wait-var-name {} {
        return "${selfns}::done"
    }
}


proc ::dmsnit::header {code type length args} {
    set header {}
    lappend header "HTTP/1.1 $code"
    lappend header "Content-Type: $type"
    lappend header "Content-Length: $length"
    lappend header {*}$args

    return [join $header \r\n]\r\n\r\n
}


proc ::dmsnit::notice-page {title headExtra content} {
    return [template::expand {
        <!DOCTYPE html>
        <html>
            <head>
                <meta charset="utf-8">
                <title>%1$s</title>
                %2$s
            </head>
            <body>
                %3$s
            </body>
        </html>
    } $title $headExtra $content]
}


proc ::dmsnit::response {code type data args} {
    set length [string length $data]
    return [header $code $type $length {*}$args]$data
}


proc ::dmsnit::send {channel data} {
    puts -nonewline $channel $data
}


namespace eval ::dmsnit::mime {
    variable mimeDataInverted {
        text/plain {
            authors
            copying
            dockerfile
            license
            makefile
            readme
            todo
            vagrantfile

            .c
            .cfg
            .cmd
            .conf
            .cpp
            .h
            .ini
            .log
            .markdown
            .md
            .pl
            .py
            .sh
            .tcl
            .terms
            .tm
            .toml
            .txt
            .wiki
            .yaml
            .yml

            .howto
            .license
            .readme
        }
        text/css                .css
        text/csv                .csv
        image/gif               .gif
        application/gzip {
            .gz
            .tgz
        }
        text/html {
            .htm
            .html
        }
        image/jpeg {
            .jpg
            .jpeg
        }
        application/javascript  .js
        application/json        .json
        application/pdf         .pdf
        image/png               .png
        application/postscript  .ps
        image/svg+xml           .svg
        application/xhtml       .xhtml
        application/xml         .xml
        application/zip         .zip
    }

    variable byFilename {}
    variable byExtension {}
    foreach {mimeType files} $mimeDataInverted {
        foreach file $files {
            if {[string index $file 0] eq {.}} {
                lappend byExtension $file $mimeType
            } else {
                lappend byFilename $file $mimeType
            }
        }
    }
    unset mimeDataInverted


    proc type {filename} {
        variable byFilename
        variable byExtension
        set tail [string tolower [file tail $filename]]
        set ext [string tolower [file extension $filename]]
        if {[dict exists $byFilename $tail]} {
            return [dict get $byFilename $tail]
        } elseif {[dict exists $byExtension $ext]} {
            return [dict get $byExtension $ext]
        } else {
            return application/octet-stream
        }
    }
}


namespace eval ::dmsnit::template {
    proc expand {template args} {
        return [format [::textutil::undent $template] {*}$args]
    }
}


namespace eval ::dmsnit::url {
    variable reserved {
        !  %21
        #  %23
        $  %24
        &  %26
        '  %27
        (  %28
        )  %29
        *  %2A
        +  %2B
        ,  %2C
        /  %2F
        :  %3A
        ;  %3B
        =  %3D
        ?  %3F
        @  %40
        [  %5B
        ]  %5D
    }


    proc decode str {
        return [::ncgi::decode $str]
    }


    proc encode str {
        variable reserved
        return [string map $reserved $str]
    }
}


proc ::dmsnit::main {argv0 argv} {
    variable reload 0

    set httpd [::dmsnit::httpd create %AUTO%]

    # Process command line arguments.
    if {($argv eq {}) || ([lsearch -regexp $argv {^-(h|-?help)$}] > -1)} {
        set usageString "usage: $argv0"
        foreach option [$httpd info options] {
            set defaultValue [$httpd cget $option]
            if {$defaultValue eq {}} {
                append usageString " $option value"
            } else {
                append usageString " ?$option $defaultValue?"
            }
        }
        puts $usageString
        exit 0
    }
    $httpd configurelist $argv

    # Sample custom handlers that are used for development.
    if 1 {
        $httpd add-handler /quit {
            {conn} {
                upvar 1 self self
                send $conn [response {200 OK} text/html Bye!]
                $self clean-up $conn
                set [$self wait-var-name] 1
            } ::dmsnit
        }
        $httpd add-handler /reload {
            {conn} {
                upvar 1 self self
                send $conn [response \
                    {202 Accepted} \
                    text/html \
                    [notice-page \
                        Reloading... \
                        {<meta http-equiv="refresh" content="1; url=/">} \
                        <h1>Reloading...</h1> \
                    ] \
                    {Refresh: 2000; url=/} \
                ]
                $self clean-up $conn
                set [$self wait-var-name] 1
                set ::dmsnit::reload 1
            } ::dmsnit
        }
    }

    $httpd serve
    vwait [$httpd wait-var-name]
    $httpd destroy

    if {$reload} {
        # Reload the server script and restart the server.
        uplevel #0 [list source [info script]]
        if {[info commands tailcall] eq {tailcall}} {
            tailcall ::dmsnit::main $argv0 $argv
        } else {
            ::dmsnit::main $argv0 $argv
        }
    }
}


# If this is the main script...
if {[info exists argv0]
    && ([file tail [info script]] eq [file tail $argv0])} {
    # If this is not a reload...
    if {![info exists ::dmsnit::reload] || !$::dmsnit::reload} {
        ::dmsnit::main $argv0 $argv
    }
}

package provide dmsnit $::dmsnit::version
