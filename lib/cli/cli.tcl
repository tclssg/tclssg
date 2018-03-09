# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017, 2018 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

# Commands that can be given to Tclssg on the command line.
namespace eval ::tclssg::command {
    namespace export *
    namespace ensemble create \
            -prefixes 0 \
            -unknown ::tclssg::command::unknown
    namespace path ::tclssg

    proc init {inputDir outputDir {debugDir {}} {options {}}} {
        utils::copy-files skeleton $inputDir ask
    }

    proc build {inputDir outputDir {debugDir {}} {options {}}} {
        set websiteConfig [load-config $inputDir]

        if {"debug" in $options} {
            debugger enable
        }

        if {"local" in $options} {
            set host [utils::dict-default-get localhost \
                                              $websiteConfig \
                                              server \
                                              host]
            set port [utils::dict-default-get 8080 \
                                              $websiteConfig \
                                              server \
                                              port]
            dict set websiteConfig url "http://$host:$port/"
        }

        if {[file isdir $inputDir]} {
            compile-website $inputDir \
                            $outputDir \
                            $debugDir \
                            $websiteConfig
        } else {
            error "couldn't access directory \"$inputDir\""
        }
    }

    proc clean {inputDir outputDir {debugDir {}} {options {}}} {
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
        set updateSourceDirs [
            list static {static files}
        ]
        if {"yes" in $options} {
            set overwriteMode always
        } else {
            set overwriteMode ask
        }
        foreach {dir descr} $updateSourceDirs {
            log::info "updating $descr"
            utils::copy-files [file join skeleton $dir] \
                              [file join $inputDir $dir] \
                              $overwriteMode
        }
    }

    proc deploy-copy {inputDir outputDir {debugDir {}} {options {}}} {
        set websiteConfig [load-config $inputDir]

        set deployDest [dict get $websiteConfig deployCopy path]

        utils::copy-files $outputDir $deployDest always
    }

    proc deploy-custom {inputDir outputDir {debugDir {}} {options {}}} {
        proc exec-deploy-command {command substDict} {
            if {$command eq {}} return
            set preparedCommand [::struct::list mapfor x $command {
                expr {
                    [regexp {^\$(.*)$} $x _ key] ?
                    [dict get $substDict $key] :
                    $x
                }
            }]
            log::info "running command [list $preparedCommand]"
            set exitStatus 0
            set error [catch {
                exec -ignorestderr -- {*}$preparedCommand >@ stdout 2>@ stderr
            } msg options]
            if {$error} {
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
        set websiteConfig [load-config $inputDir]
        set deployCustom [dict get $websiteConfig deployCustom]

        log::info deploying...
        set vars [dict create outputDir $outputDir]
        exec-deploy-command [dict get $deployCustom start] $vars
        foreach file [::fileutil::find $outputDir {file isfile}] {
            dict set vars file $file
            dict set vars rel [::fileutil::relative $outputDir $file]
            exec-deploy-command [dict get $deployCustom file] $vars
        }
        exec-deploy-command [dict get $deployCustom end] $vars
        log::info done
    }

    proc deploy-ftp {inputDir outputDir {debugDir {}} {options {}}} {
        set websiteConfig [load-config $inputDir]

        package require ftp
        global errorInfo
        set conn [
            ::ftp::Open \
                    [dict get $websiteConfig deployFtp server] \
                    [dict get $websiteConfig deployFtp user] \
                    [dict get $websiteConfig deployFtp password] \
                    -port [utils::dict-default-get 21 \
                                                   $websiteConfig \
                                                   deployFtp \
                                                   port] \
                    -mode passive
        ]
        set deployFtpPath [dict get $websiteConfig deployFtp path]

        ::ftp::Type $conn binary

        foreach file [::fileutil::find $outputDir {file isfile}] {
            set destFile [utils::replace-path-root $file \
                                                   $outputDir \
                                                   $deployFtpPath]
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
        set websiteConfig [load-config $inputDir]

        package require browse
        ::browse::url [file rootname [file join $outputDir index.md]].html
    }

    proc serve {inputDir outputDir {debugDir {}} {options {}}} {
        set websiteConfig [load-config $inputDir]
        set host [utils::dict-default-get localhost \
                                          $websiteConfig \
                                          server \
                                          host]
        set port [utils::dict-default-get 8080 \
                                          $websiteConfig \
                                          server \
                                          port]
        set verbose [expr {"verbose" in $options}]

        package require dmsnit

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
        if {"browse" in $options} {
            package require browse
            ::browse::url "http://$host:$port/"
        }
        vwait [$httpd wait-var-name]
    }

    proc version {inputDir outputDir {debugDir {}} {options {}}} {
        puts $::tclssg::version
    }

    proc help {{inputDir ""} {outputDir ""} {debugDir ""} {options ""}} {
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
        return ::tclssg::command::help
    }
} ;# namespace command

package provide tclssg::cli 0
