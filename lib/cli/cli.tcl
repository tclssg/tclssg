# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

# CLI utilities.
namespace eval ::tclssg::cli {
    namespace export *
    namespace ensemble create
    namespace path ::tclssg

    proc allow-options {allowed options} {
        if {[llength $allowed] == 0 && [llength $options] > 0} {
            error "this command accepts no options,\
                   but got [list $options]"
        }
        foreach option $options {
            if {$option ni $allowed} {
                error "unknown option [list $option],\
                       must be one of [list $allowed]"
            }
        }
    }

    proc parse-argv argv {
        set command [utils::unqueue! argv]

        set options {}
        while {[lindex $argv 0] ne {--}
               && [regexp ^--?(.*)$ [lindex $argv 0] _ option]} {
            utils::unqueue! argv
            lappend options --$option
        }
        set inputDir [utils::normalize-relative-path [utils::unqueue! argv]]
        set outputDir [utils::normalize-relative-path [utils::unqueue! argv]]

        if {$argv ne {}} {
            error "unknown extra arguments: [list $argv]"
        }

        return [list $command $inputDir $outputDir $options]
    }
}

# Commands that can be given to Tclssg on the command line.
namespace eval ::tclssg::cli::command {
    namespace export *
    namespace ensemble create \
            -prefixes 0 \
            -unknown ::tclssg::cli::command::unknown
    namespace path {::tclssg ::tclssg::cli}

    proc init {inputDir outputDir {debugDir {}} {options {}}} {
        allow-options {} $options

        utils::copy-files [file join $::tclssg::path skeleton] $inputDir ask
    }

    proc build {inputDir outputDir {debugDir {}} {options {}}} {
        allow-options {--debug --local --plugins} $options

        set websiteConfig [config::load $inputDir]

        if {{--debug} in $options} {
            debugger enable
        }

        if {{--local} in $options} {
            set host [utils::dict-default-get localhost \
                                              $websiteConfig \
                                              server \
                                              host]
            set port [utils::dict-default-get 8080 \
                                              $websiteConfig \
                                              server \
                                              port]
            dict set websiteConfig url http://$host:$port/
        }

        set plugins [expr {{--plugins} in $options}]

        if {[file isdir $inputDir]} {
            compile-website -inputDir $inputDir \
                            -outputDir $outputDir \
                            -debugDir $debugDir \
                            -config $websiteConfig \
                            -plugins $plugins
        } else {
            error "couldn't access directory [list $inputDir]"
        }
    }

    proc clean {inputDir outputDir {debugDir {}} {options {}}} {
        allow-options {} $options

        # Do not use -force to avoid deleting read-only files.
        foreach file [::fileutil::find $outputDir {file isfile}] {
            log::info "deleting [list $file]"
            file delete $file
        }
        # A hack to remove nested subdirectories first.
        foreach directory [lsort -decr [::fileutil::find \
                $outputDir {file isdirectory}]] {
            log::info "removing empty directory [list $directory]"
            file delete $directory
        }
    }

    proc update {inputDir outputDir {debugDir {}} {options {}}} {
        allow-options --yes $options

        set updateSourceDirs [
            list static {static files}
        ]
        if {{--yes} in $options} {
            set overwriteMode always
        } else {
            set overwriteMode ask
        }
        foreach {dir descr} $updateSourceDirs {
            log::info "updating $descr"
            utils::copy-files [file join $::tclssg::path skeleton $dir] \
                              [file join $inputDir $dir] \
                              $overwriteMode
        }
    }

    proc deploy-copy {inputDir outputDir {debugDir {}} {options {}}} {
        allow-options {} $options

        set websiteConfig [config::load $inputDir]
        set deployDest [dict get $websiteConfig deployCopy path]

        utils::copy-files $outputDir $deployDest always
    }

    proc deploy-custom {inputDir outputDir {debugDir {}} {options {}}} {
        allow-options {} $options

        proc exec-deploy-command {command substDict} {
            if {$command eq {}} return

            set script "string map [list $substDict] \$x"
            set preparedCommand [::struct::list mapfor x $command $script]

            log::info "running command [list $preparedCommand]"

            set exitStatus 0
            try {
                exec -ignorestderr -- {*}$preparedCommand >@ stdout 2>@ stderr
            } on error {msg options} {
                lassign [dict get $options -errorcode] errorCode _ exitStatus

                if {$errorCode ne {CHILDSTATUS}} {
                    return -options $options $msg
                }
            }

            if {$exitStatus != 0} {
                log::error "command [list $preparedCommand] returned exit\
                            code $exitStatus."
            }
        }

        set websiteConfig [config::load $inputDir]
        set deployCustom [dict get $websiteConfig deployCustom]

        log::info deploying...

        set vars [dict create \$outputDir $outputDir]

        exec-deploy-command [dict get $deployCustom start] $vars

        foreach file [::fileutil::find $outputDir {file isfile}] {
            dict set vars \$file $file
            dict set vars \$rel [::fileutil::relative $outputDir $file]

            exec-deploy-command [dict get $deployCustom file] $vars
        }

        exec-deploy-command [dict get $deployCustom end] $vars

        log::info done
    }

    proc deploy-ftp {inputDir outputDir {debugDir {}} {options {}}} {
        allow-options {} $options

        set websiteConfig [config::load $inputDir]

        package require ftp 2
        global errorInfo
        set conn [
            ::ftp::Open \
                    [dict get $websiteConfig deployFTP server] \
                    [dict get $websiteConfig deployFTP user] \
                    [dict get $websiteConfig deployFTP password] \
                    -port [utils::dict-default-get 21 \
                                                   $websiteConfig \
                                                   deployFTP \
                                                   port] \
                    -mode passive
        ]
        set deployFTPPath [dict get $websiteConfig deployFTP path]

        ::ftp::Type $conn binary

        foreach file [::fileutil::find $outputDir {file isfile}] {
            set destFile [utils::replace-path-root $file \
                                                   $outputDir \
                                                   $deployFTPPath]
            set path [file split [file dirname $destFile]]
            set partialPath {}

            foreach dir $path {
                set partialPath [file join $partialPath $dir]
                if {[::ftp::Cd $conn $partialPath]} {
                    ::ftp::Cd $conn /
                } else {
                    log::info "creating directory [list $partialPath]"
                    ::ftp::MkDir $conn $partialPath
                }
            }
            log::info "uploading [list $file] as [list $destFile]"
            if {![::ftp::Put $conn $file $destFile]} {
                error "upload error: [list $errorInfo]"
            }
        }
        ::ftp::Close $conn
    }

    proc open {inputDir outputDir {debugDir {}} {options {}}} {
        set websiteConfig [config::load $inputDir]

        package require tclssg::vendor::browse
        ::browse::url [file rootname [file join $outputDir index.md]].html
    }

    proc serve {inputDir outputDir {debugDir {}} {options {}}} {
        allow-options {--browse --verbose} $options

        set websiteConfig [config::load $inputDir]
        set host [utils::dict-default-get localhost \
                                          $websiteConfig \
                                          server \
                                          host]
        set port [utils::dict-default-get 8080 \
                                          $websiteConfig \
                                          server \
                                          port]
        set verbose [expr {{--verbose} in $options}]

        package require dmsnit 0.14

        set httpd [::dmsnit::httpd create %AUTO%]
        $httpd configure \
                -root $outputDir \
                -host $host \
                -port $port \
                -verbose $verbose

        $httpd add-handler /bye {
            socketChannel {
                upvar 1 self self
                puts "shutting down"
                puts $socketChannel {HTTP/1.0 204 No Content}
                puts $socketChannel {}
                $self clean-up $socketChannel
                set [$self wait-var-name] 1
            }
        }
        $httpd serve
        if {{--browse} in $options} {
            package require tclssg::vendor::browse
            ::browse::url "http://$host:$port/"
        }
        vwait [$httpd wait-var-name]
    }

    proc version {inputDir outputDir {debugDir {}} {options {}}} {
        allow-options {} $options
        puts $::tclssg::version
    }

    proc help {{inputDir ""} {outputDir ""} {debugDir ""} {options ""}} {
        allow-options {} $options
        global argv0

        # Format: {command description {option optionDescription ...} ...}.
        set commandHelp [list {*}{
            init {create a new project by cloning the default project\
                  skeleton} {}
            build {build the static website} {
                --debug {dump the results of intermediate stages of content\
                         processing to disk}
                --local {build with the value of the website setting "url"\
                         replaced with a URL derived from the "server" settings}
                --plugins {enable Tcl code plugins in the project directory\
                           (security risk)}
            }
            clean {delete all files in outputDir} {}
            update {update the inputDir for a new version of Tclssg by\
                    copying the static files (e.g., CSS) of the project\
                    skeleton over the static files in inputDir and having\
                    the user confirm replacement} {
                --yes       {assume the answer to all questions to be "yes"\
                             (replace all)}
            }
            deploy-copy {copy the output to the file system path set\
                         in the config file} {}
            deploy-custom {run the custom deployment commands specified in\
                           the config file on the output} {}
            deploy-ftp  {upload the output to the FTP server set in the\
                         config file} {}
            open {open the index page in the default web browser over\
                  file://} {}
            serve {start a local web server serving outputDir} {
                --browse {open the website in the default web browser}
                --verbose {log every request to standard output}
            }
            version {print the version number} {}
            help {show this message}
        }]

        set commandHelpText {}
        foreach {command description options} $commandHelp {
            append commandHelpText \
                   [utils::text-columns "" 4 \
                                        $command 15 \
                                        $description 43]
            foreach {option optionDescr} $options {
                append commandHelpText \
                       [utils::text-columns "" 8 \
                                            $option 12 \
                                            $optionDescr 42]
            }
        }

        puts [format [
                utils::trim-indentation {
                    usage: %s <command> [options] [inputDir [outputDir]]

                    Possible commands are:
                    %s

                    inputDir defaults to "%s"
                    outputDir defaults to "%s"
                }
            ] \
            $argv0 \
            $commandHelpText \
            input \
            output]
    }

    proc unknown args {
        return ::tclssg::cli::command::help
    }
} ;# namespace command

package provide tclssg::cli 0
