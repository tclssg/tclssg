#! /usr/bin/env tclsh
# Tclssg, a static website generator.
# Copyright (c) 2013-2018, 2020, 2024
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

package require Tcl 8.6 9
package require base64 2
package require csv 0 1
package require fileutil 1
package require json 1
package require json::write 1
package require logger 0 1
package require Markdown 1.2
package require msgcat 1
package require sha256 1
package require sqlite3 3
package require struct 2
package require textutil 0 1

set PROFILE 0
if {$PROFILE} {
    package require profiler 0 1
    ::profiler::init
}

# Code conventions:
#
# Only use spaces for indentation. Keep the line width for code outside of
# templates under 80 characters.
#
# Procedures ("procs") have names-like-this; variables have namesLikeThis. "!"
# at the end of a proc's name means the proc modifies one or more of the
# variables it is passed by name (e.g., "unqueue!"). "?" in the same position
# means it returns a true/false value.

namespace eval tclssg {
    namespace export *
    namespace ensemble create

    variable version 3.0.0
    variable debugMode 1
    variable path

    proc version {} {
        variable version
        return $version
    }

    proc configure newPath {
        # What follows is the configuration that is generally not supposed to
        # vary from project to project.
        variable path
        set path $newPath
        lappend ::auto_path $newPath

        ::logger::initNamespace ::tclssg [expr {
            $::tclssg::debugMode ? {debug} : {info}
        }]
        # This is a hack that depends on the internal structure of the logger.
        set ::logger::tree::tclssg::lastSeen {}
        proc ::logger::tree::tclssg::stdoutcmd {level text} {
            namespace path ::tclssg::utils
            variable lastSeen

            set time [clock seconds]
            set timestamp [clock format $time -format {%Y-%m-%d %H:%M:%S %Z}]

            set printPrefix [expr {
                [dict-getdef $lastSeen level {}] ne $level ||
                $time - [dict-getdef $lastSeen time -1] >= 10
            }]

            # Check that the text is a valid list.
            if {$printPrefix} {
                set prefix "---- $timestamp \[$level\]\n"
                set output $prefix$text

                dict set lastSeen level $level
                dict set lastSeen time $time
            } else {
                set lastText [dict-getdef $lastSeen text {}]
                try {
                    lindex $text 0
                    lindex $lastText 0
                } on error {} {
                    set output $text
                } on ok {} {
                    set common [::tclssg::utils::longest-common-list-prefix \
                                    $lastText \
                                    $text]
                    set len [string length $common]
                    set output [string repeat { } $len]
                    append output [string range $text $len end]
                }
            }

            puts $output
            dict set lastSeen text $text
        }

        package require tclssg::cli
        package require tclssg::config
        package require tclssg::converters
        package require tclssg::db
        package require tclssg::debugger
        package require tclssg::interpreter
        package require tclssg::pipeline
        package require tclssg::templates
        package require tclssg::utils

        namespace import utils::dict-getdef

        return
    }

    proc run-pipeline-stage {ns files} {
        if {[info commands ${ns}::load] eq "${ns}::load"} {
            ${ns}::load $files
        }
        if {[info commands ${ns}::transform] eq "${ns}::transform"} {
            ${ns}::transform
        }
    }

    # Process input files in $inputDir to produce a static website in
    # $outputDir.
    proc compile-website args {
        utils::named-args {
            -inputDir   inputDir
            -outputDir  outputDir
            -debugDir   debugDir
            -config     websiteConfig

            -plugins    {plugins 0}
        }

        db init
        debugger init $inputDir $debugDir
        db config set inputDir $inputDir
        db config set outputDir $outputDir
        db config set buildTimestamp [clock seconds]
        # For security reasons the value of "plugins" can only be set via the
        # command line. It is not part of the config file schema.
        db config set plugins $plugins
        lappend ::tclssg::templates::paths [file join $inputDir templates]

        # Run the pre-build stages of the pipeline.
        set files [::fileutil::find $inputDir {file isfile}]
        foreach ns [lsort [namespace children pipeline 0*]] {
            run-pipeline-stage $ns $files
        }

        # Check that the config confirms to the schema and insert the settings
        # into the DB. We perform the validation here rather than earlier to let
        # plugins add their own settings to the schema.
        db transaction {
            dict for {key value} [config::parse-by-schema $websiteConfig] {
                if {$key in {inputDir outputDir}} continue
                db config set $key $value
            }
        }
        unset websiteConfig

        # Run the rest of the pipeline.
        foreach ns [lsort [namespace children pipeline]] {
            if {[string match 0* [namespace tail $ns]]} continue
            run-pipeline-stage $ns $files
        }
    }

    # Read the setting $settingName from the website config file in $inputDir.
    proc read-path-setting {inputDir settingName} {
        try {
            ::tclssg::config::load $inputDir 0
        } trap {POSIX ENOENT} {} - trap {POSIX EISDIR} {} {
            return {}
        } on ok config {}
        set value [dict-getdef $config $settingName {}]
        # Make a relative path from the config relative to $inputDir.
        if {$value ne {} && [utils::path-is-relative? $value]} {
            set value [utils::normalize-relative-path [file join $inputDir \
                                                                 $value]]
        }
        return $value
    }

    # Display the message and exit with exit code 1 if run as the main script
    # or cause a simple error otherwise.
    proc error-message {message} {
        if {[main-script?]} {
            log::error $message
            exit 1
        } else {
            error $message
        }
    }

    # Display an error message and exit if inputDir does not exist or isn't a
    # directory.
    proc check-input-directory {inputDir} {
        set errorMessage {}
        if {![file exist $inputDir]} {
            error-message "inputDir \"$inputDir\" does not exist"
        } elseif {![file isdirectory $inputDir]} {
            error-message "inputDir \"$inputDir\" exists but is not a directory"
        }
    }

    # This proc is run if Tclssg is the main script.
    proc main {argv0 argv} {
        # Note: Deal with symbolic links pointing to the actual
        # location of the application to ensure that we look for the
        # supporting code in the actual location, instead from where
        # the link is.
        #
        # Note further the trick with ___; it ensures that the
        # resolution of symlinks also applies to the nominally last
        # segment of the path, i.e. the application name itself. This
        # trick then requires the second 'file dirname' to strip off
        # the ___ again after resolution.

        tclssg configure \
               [file dirname [file dirname [file normalize $argv0/___]]]

        # Version.
        set currentPath [pwd]

        cd $::tclssg::path
        if {[file tail [pwd]] eq {app} &&
            [file isfile ../git-commit]} {
            set commit [fileutil::cat ../git-commit]
        } else {
            catch {
                set commit [exec git rev-parse HEAD]
            }
        }
        if {[info exists commit]} {
            append ::tclssg::version " (commit [string range $commit 0 9])"
        }
        cd $currentPath

        # Get the command line options, including the directories to operate on.
        lassign [cli parse-argv $argv] command \
                                       inputDir \
                                       outputDir \
                                       options

        # Defaults for inputDir and outputDir.
        if {($inputDir eq "") && ($outputDir eq "")} {
            set inputDir website/
            set outputDir [read-path-setting $inputDir outputDir]
            if {$outputDir eq ""} {
                set outputDir website/output/
            }
        } elseif {$outputDir eq ""} {
            set outputDir [read-path-setting $inputDir outputDir]
            if {$command ne {init} && $outputDir eq ""} {
                error-message [
                    utils::trim-indentation {
                        error: no outputDir given.

                        please either a) specify both inputDir and outputDir or
                                      b) set outputDir in your configuration
                                         file.
                    }
                ]
            }
        }

        set debugDir [read-path-setting $inputDir debugDir]
        if {$debugDir eq ""} {
            set debugDir website/debug
        }


        # Check if inputDir exists for commands that require it.
        if {($command in [::struct::list map \
                    [info commands ::tclssg::cli::command::*] \
                    {namespace tail}]) &&
                ($command ni {help init version})} {
            check-input-directory $inputDir
        }

        # Execute command.
        try {
                tclssg cli command $command \
                                   $inputDir \
                                   $outputDir \
                                   $debugDir \
                                   $options
        } on error errorMessage {
            set errorMessage "\n*** error: $errorMessage ***"
            if {$::tclssg::debugMode} {
                append errorMessage "\nTraceback:\n$::errorInfo"
            }
            error-message $errorMessage
        }
    }
} ;# namespace tclssg

# Check if we were run as the primary script by the interpreter. Code from
# http://wiki.tcl-lang.org/40097.
proc main-script? {} {
    global argv0

    if {[info exists argv0] &&
            [file exists [info script]] &&
            [file exists $argv0]} {
        file stat $argv0 argv0Info
        file stat [info script] scriptInfo
        expr {$argv0Info(dev) == $scriptInfo(dev)
           && $argv0Info(ino) == $scriptInfo(ino)}
    } else {
        return 0
    }
}

if {[main-script?]} {
    ::tclssg::main $argv0 $argv
    if {$PROFILE} {
        puts [::profiler::sortFunctions exclusiveRuntime]
    }
}
