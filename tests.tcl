#!/usr/bin/env tclsh
# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

package require fileutil
package require struct
package require tcltest

namespace eval ::tclssg::tests {
    variable path [file dirname [file dirname [file normalize $argv0/___]]]
    
    lappend ::auto_path [file join $path lib]
    namespace eval ::tclssg [list variable path $path]

    package require http

    package require tclssg::cli
    package require tclssg::db
    package require tclssg::debugger
    package require tclssg::interpreter
    package require tclssg::pipeline
    package require tclssg::templates
    package require tclssg::utils

    namespace import ::tclssg::utils::*

    if {[llength $argv] > 0} {
        tcltest::configure -match $argv
    }

    proc tcl args {
        exec [info nameofexecutable] {*}$args
    }

    proc http-get url {
        set token [::http::geturl $url]
        set result [::http::data $token]
        ::http::cleanup $token
        return $result
    }

    # Find a random unused port.
    proc unused-port {} {
        for {set i 0} {$i < 5} {incr i} {
            set port [expr {10000 + int(50000*rand())}]
            if {![catch {
                set ch [socket -server {} $port]
            }]} {
                close $ch
                return $port
            }
        }
        error "couldn't find an unused port after $i attempts"
    }

    tcltest::testConstraint diff [apply {{} {
        set testPath [::fileutil::tempfile]
        file delete $testPath
        file mkdir $testPath
        set error [catch {
            exec diff -r $testPath $testPath
        }]
        file delete -force $testPath
        return [expr { !$error }]
    }}]

    set correctSeconds [clock scan {2014-06-26-20-10} \
            -format {%Y-%m-%d-%H-%M}]
    set correctSecondsShort [clock scan {2014-01-01-00-00-00} \
            -format {%Y-%m-%d-%H-%M-%S}]

    # Unit tests.

    tcltest::test incremental-clock-scan-1.1 {incremental-clock-scan} \
                -body {
        incremental-clock-scan {2014-06-26 20:10}
    } -result [list $correctSeconds %Y-%m-%dT%H:%M]

    tcltest::test incremental-clock-scan-1.2 {incremental-clock-scan} \
                -body {
        incremental-clock-scan {2014-06-26T20:10}
    } -result [list $correctSeconds %Y-%m-%dT%H:%M]

    tcltest::test incremental-clock-scan-1.3 {incremental-clock-scan} \
                -body {
        incremental-clock-scan {2014 06 26 20 10}
    } -result [list $correctSeconds {%Y-%m-%dT%H:%M}]

    tcltest::test incremental-clock-scan-1.4 {incremental-clock-scan} \
                -body {
        incremental-clock-scan {2014/06/26 20:10}
    } -result [list $correctSeconds {%Y-%m-%dT%H:%M}]

    tcltest::test incremental-clock-scan-2.1 {incremental-clock-scan 2} \
                -body {
        incremental-clock-scan {2014}
    } -result [list $correctSecondsShort %Y]

    tcltest::test incremental-clock-scan-2.2 {incremental-clock-scan 2} \
                -body {
        incremental-clock-scan {2014-01}
    } -result [list $correctSecondsShort %Y-%m]

    tcltest::test incremental-clock-scan-2.3 {incremental-clock-scan 2} \
                -body {
        incremental-clock-scan {2014-01-01 00:00:00}
    } -result [list $correctSecondsShort {%Y-%m-%dT%H:%M:%S}]

    tcltest::test slugify-1.1 {slugify} \
                -body {
        slugify {Hello, World!}
    } -result hello-world

    tcltest::test slugify-1.2 {slugify} \
                -body {
        slugify {hello world}
    } -result hello-world

    tcltest::test replace-path-root-1.1 {replace-path-root} \
                -body {
        replace-path-root ./a/b/c/d/e/f ./a ./x
    } -result x/b/c/d/e/f

    tcltest::test replace-path-root-1.2 {replace-path-root} \
                -body {
        replace-path-root ./a/b/c/d/e/f ./a/b/c ./x/b/c
    } -result x/b/c/d/e/f

    tcltest::test replace-path-root-1.3 {replace-path-root} \
                -body {
        replace-path-root a/b/c/d/e/f a x
    } -result x/b/c/d/e/f

    tcltest::test replace-path-root-1.4 {replace-path-root} \
                -body {
        replace-path-root a/b/./c/d/e/f a/b/c x/b/c
    } -result x/b/c/d/e/f

    tcltest::test replace-path-root-1.5 {replace-path-root} \
                -body {
        replace-path-root /././././././././b / /a
    } -result /a/b

    tcltest::test dict-default-get-1.1 {dict-default-get} \
                -body {
        dict-default-get testValue {} someKey
    } -result testValue

    tcltest::test dict-default-get-1.2 {dict-default-get} \
                -body {
        dict-default-get -1 {someKey testValue} someKey
    } -result testValue

    tcltest::test dict-default-get-1.3 {dict-default-get} \
                -body {
        dict-default-get -1 {someKey {anotherKey testValue}} \
                         someKey anotherKey
    } -result testValue

    tcltest::test add-number-before-extension-1.1 {add-number-before-extension}\
                -body {
        add-number-before-extension "filename.ext" 0
    } -result filename.ext

    tcltest::test add-number-before-extension-1.2 {add-number-before-extension}\
                -body {
        add-number-before-extension "filename.ext" 0 "-%d" 1
    } -result filename-0.ext

    tcltest::test add-number-before-extension-1.3 {add-number-before-extension}\
                -cleanup {unset result} \
                -body {
        set result {}

        for {set i 1} {$i < 11} {incr i} {
            lappend result [add-number-before-extension "filename.ext" $i]
        }

        return $result
    } -result [list filename-1.ext filename-2.ext filename-3.ext filename-4.ext \
            filename-5.ext filename-6.ext filename-7.ext filename-8.ext \
            filename-9.ext filename-10.ext]

    tcltest::test add-number-before-extension-1.4 {add-number-before-extension}\
                -cleanup {unset result} \
                -body {
        set result {}

        for {set i 1} {$i < 11} {incr i} {
            lappend result [add-number-before-extension "filename.ext" \
                    $i "%03d"]
        }

        return $result
    } -result [list filename001.ext filename002.ext filename003.ext \
            filename004.ext filename005.ext filename006.ext filename007.ext \
            filename008.ext filename009.ext filename010.ext]

    tcltest::test add-number-before-extension-1.5 {add-number-before-extension}\
                -cleanup {unset result} \
                -body {
        set result {}

        for {set i 1} {$i < 11} {incr i} {
            lappend result [add-number-before-extension "filename.ext" \
                    $i "%03d" -1]
        }

        return $result
    } -result [list filename001.ext filename002.ext filename003.ext \
            filename004.ext filename005.ext filename006.ext filename007.ext \
            filename008.ext filename009.ext filename010.ext]

    tcltest::test separate-frontmatter-1.1 separate-frontmatter \
                -cleanup {unset result first elem} \
                -body {
        set prased {}
        lappend prased [separate-frontmatter {{hello world} Hello, world!}]
        lappend prased [separate-frontmatter {{ hello world } Hello, world!}]
        lappend prased [separate-frontmatter {{hello world} Hello, world!}]
        lappend prased [separate-frontmatter {{hello world}

            Hello, world!}]
        lappend prased [separate-frontmatter {{
                hello world
            }

            Hello, world!}]

        set result {}
        set first [lindex $prased 0]
        foreach elem [lrange $prased 1 end] {
            lappend result [::struct::list equal $first $elem]
        }

        return [lsort -unique $result]
    } -result 1

    tcltest::test group-by-1.1 group-by \
                -cleanup {unset i result} \
                -body {
        set result {}
        for {set i 1} {$i < 7} {incr i} {
            lappend result [group-by $i {a b c d e f}]
        }
        return $result
    } -result [list \
        {a b c d e f} \
        {{a b} {c d} {e f}} \
        {{a b c} {d e f}} \
        {{a b c d} {e f}} \
        {{a b c d e} f} \
        {{a b c d e f}} \
    ]

    tcltest::test group-by-1.2 group-by \
                -cleanup {unset i result} \
                -body {
        set result {}
        for {set i 1} {$i < 7} {incr i} {
            lappend result [group-by $i {{} {} {} {} {} {}}]
        }
        return $result
    } -result [list \
        {{{}} {{}} {{}} {{}} {{}} {{}}} \
        {{{} {}} {{} {}} {{} {}}} \
        {{{} {} {}} {{} {} {}}} \
        {{{} {} {} {}} {{} {}}} \
        {{{} {} {} {} {}} {{}}} \
        {{{} {} {} {} {} {}}} \
    ]

    tcltest::test group-by-2.1 error \
                -body {
        group-by 0 {}
    } -returnCodes error -result {expected an integer >= 1 but got "0"}

    # Integration tests.

    proc make-temporary-project {} {
        set tempProjectDir [::fileutil::tempfile]
        # Remove the temporary file so that Tclssg can replace it with
        # a temporary project directory.
        file delete $tempProjectDir
        tcltest::makeDirectory $tempProjectDir

        tcl ssg.tcl init $tempProjectDir
        return $tempProjectDir
    }

    variable project [make-temporary-project]

    tcltest::test command-line-1.1 {Tclssg command line commands} \
                -body {
        tcl ssg.tcl version
        tcl ssg.tcl help
    } -match glob -result {*usage: ssg.tcl*}

    tcltest::test command-line-1.2 {Tclssg command line commands} \
                -cleanup {unset result configFile config} \
                -constraints diff \
                -body {
        variable project
        set tclssgArguments [list $project]

        # Set deployment options in the website config.
        set configFile $project/website.conf
        set config [::fileutil::cat $configFile]
        dict set config deployCopy path $project/deploy-copy-test
        dict set config deployCustom [dict create \
            start "cp -r \"\$outputDir\"\
                   \"$project/deploy-custom-test\"" \
            file {} \
            end {} \
        ]
        set port [unused-port]
        dict set config server [dict create \
            host localhost \
            port $port \
        ]
        ::fileutil::writeFile $configFile $config

        tcl ssg.tcl build {*}$tclssgArguments
        tcl ssg.tcl update --templates --yes {*}$tclssgArguments
        tcl ssg.tcl build {*}$tclssgArguments
        tcl ssg.tcl deploy-copy {*}$tclssgArguments
        tcl ssg.tcl deploy-custom {*}$tclssgArguments
        tcl ssg.tcl clean {*}$tclssgArguments

        set result [exec diff -r \
                $project/deploy-copy-test \
                $project/deploy-custom-test]
        return $result
    } -result {}

    tcltest::test command-line-1.3 {serve command} \
                -cleanup {close $ch; unset ch i foundServerInfo indexPage} \
                -body {
        variable project
        tcl ssg.tcl build $project $project/output
        set ch [open |[list [info nameofexecutable] ssg.tcl serve \
                                                            -verbose $project]]
        set foundServerInfo 0
        fconfigure $ch -blocking 0
        set i 0
        while 1 {
            if {[gets $ch line] > 0} {
                if {[regexp {serving path .* on ([^ ]+) port ([0-9]+)} \
                            $line _ host port]} {
                    set foundServerInfo 1
                    break
                }
            } else {
                after 10
                incr i
            }
            # Give the server approximately one second to start up.
            if {$i > 100} {
                break
            }
        }
        if {!$foundServerInfo} {
            error {can't determine the server host/port from its output}
        }
        if {[eof $ch]} {
            error {the server has quit}
        }
        set indexPage [http-get http://$host:$port/]
        set result \
            [regexp {Powered by <a.*?>Tclssg</a> and <a.*?>Bootstrap</a>} \
                    $indexPage]
        http-get http://$host:$port/bye
        return $result
    } -result 1

    tcltest::test tclssg-library-1.1 {Tclssg as a library} \
                -cleanup {unset project result file} \
                -body {
        set project [make-temporary-project]
        set file [file join $project libtest.tcl]
        fileutil::writeFile $file [
            subst {
                source [file join $path ssg.tcl]
                tclssg configure $path
                tclssg command build $project $project/output
                puts done
            }
        ]
        set result [tcl $file]
        return [lindex $result end]
    } -result done

    # Exit with a nonzero status if there are failed tests.
    set failed [expr {$tcltest::numTests(Failed) > 0}]

    tcltest::cleanupTests
    if {$failed} {
        exit 1
    }
}
