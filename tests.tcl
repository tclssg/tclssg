#!/usr/bin/env tclsh
# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

package require fileutil
package require struct
package require tcltest

namespace eval ::tclssg::tests {
    variable path [file dirname [file dirname [file normalize $argv0/___]]]
    variable setup [list apply {{path} {
        lappend ::auto_path [file join $path lib]
        package require tclssg-lib
        namespace import ::tclssg::utils::*
        cd $path
    }} $path]

    if {[llength $argv] > 0} {
        tcltest::configure -match $argv
    }

    proc tcl args {
        exec [info nameofexecutable] {*}$args
    }

    proc curl-available? {} {
        set error [catch {
            exec curl --version
        }]
        return [expr { !$error }]
    }

    proc diff-available? {} {
        set testPath [::fileutil::tempfile]
        file delete $testPath
        file mkdir $testPath
        set error [catch {
            exec diff -r $testPath $testPath
        }]
        file delete -force $testPath
        return [expr { !$error }]
    }

    tcltest::testConstraint curl [curl-available?]
    tcltest::testConstraint diff [diff-available?]

    tcltest::test test1 {incremental-clock-scan} \
                -setup $setup \
                -cleanup {unset result} \
                -body {
        set result {}
        lappend result [incremental-clock-scan {2014-06-26 20:10}]
        lappend result [incremental-clock-scan {2014-06-26T20:10}]
        lappend result [incremental-clock-scan {2014 06 26 20 10}]
        lappend result [incremental-clock-scan {2014/06/26 20:10}]
        lappend result [incremental-clock-scan {2014/06/26 20:10}]

        lappend result [lindex [incremental-clock-scan {2014}] 0]
        lappend result [lindex [incremental-clock-scan {2014-01}] 0]
        lappend result [lindex [incremental-clock-scan {2014-01-01 00:00:00}] 0]

        return [lsort -unique $result]
    } -result [list \
        [clock scan {2014-01-01} -format {%Y-%m-%d}] \
        [list [clock scan {2014-06-26-20-10} -format {%Y-%m-%d-%H-%M}] \
            {%Y-%m-%dT%H:%M}] \
    ]

    tcltest::test test2 {slugify} \
                -setup $setup \
                -cleanup {unset result} \
                -body {
        set result {}
        lappend result [slugify {Hello, World!}]
        lappend result [slugify {hello world}]

        return [lsort -unique $result]
    } -result hello-world

    tcltest::test test3 {replace-path-root} \
                -setup $setup \
                -cleanup {unset result} \
                -body {
        set result {}
        lappend result [replace-path-root ./a/b/c/d/e/f ./a ./x]
        lappend result [replace-path-root ./a/b/c/d/e/f ./a/b/c ./x/b/c]
        lappend result [replace-path-root a/b/c/d/e/f a x]
        lappend result [replace-path-root a/b/./c/d/e/f a/b/c x/b/c]

        lappend result [replace-path-root /././././././././b / /a]

        return [lsort -unique $result]
    } -result [list /a/b x/b/c/d/e/f]

    tcltest::test test4 {dict-default-get} \
                -setup $setup \
                -cleanup {unset result} \
                -body {
        set result {}
        lappend result [dict-default-get testValue {} someKey]
        lappend result [dict-default-get -1 {someKey testValue} someKey]
        lappend result [dict-default-get -1 {someKey {anotherKey testValue}} \
                         someKey anotherKey]

        return [lsort -unique $result]
    } -result testValue

    tcltest::test test5 {add-number-before-extension} \
                -setup $setup \
                -cleanup {unset result correct} \
                -body {
        set result {}
        set correct {}
        lappend result [add-number-before-extension "filename.ext" 0]
        lappend correct filename.ext
        lappend result [add-number-before-extension "filename.ext" 0 "-%d" 1]
        lappend correct filename-0.ext

        for {set i 1} {$i < 11} {incr i} {
            lappend result [add-number-before-extension "filename.ext" $i]
            lappend correct filename-$i.ext

            lappend result [add-number-before-extension "filename.ext" \
                    $i "%03d"]
            lappend correct [format filename%03d.ext $i]

            lappend result [add-number-before-extension "filename.ext" \
                    $i "%03d" -1]
            lappend correct [format filename%03d.ext $i]
        }

        return [expr {$result eq $correct}]
    } -result 1

    tcltest::test test6 {get-page-settings} \
                -setup $setup \
                -cleanup {unset result first elem} \
                -body {
        set prased {}
        lappend prased [get-page-settings {{hello world} Hello, world!}]
        lappend prased [get-page-settings {{ hello world } Hello, world!}]
        lappend prased [get-page-settings {{hello world} Hello, world!}]
        lappend prased [get-page-settings {{hello world}

            Hello, world!}]
        lappend prased [get-page-settings {{
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

    proc make-temporary-project {} {
        set tempProjectDir [::fileutil::tempfile]
        # Remove the temporary file so that Tclssg can replace it with
        # a temporary project directory.
        file delete $tempProjectDir
        tcltest::makeDirectory $tempProjectDir

        tcl ssg.tcl init $tempProjectDir/input $tempProjectDir/output
        return $tempProjectDir
    }

    tcltest::test test7 {Tclssg command line commands} \
                -setup $setup \
                -cleanup {unset result configFile config} \
                -constraints diff \
                -body {
        set project [make-temporary-project]
        set tclssgArguments [list $project/input $project/output]

        tcl ssg.tcl version
        tcl ssg.tcl help

        # Set deployment options in the website config.
        set configFile $project/input/website.conf
        set config [::fileutil::cat $configFile]
        dict set config deployCopy path $project/deploy-copy-test
        dict set config deployCustom [list \
            start "cp -r \"\$outputDir\"\
                    $project/deploy-custom-test" \
            file {} \
            end {} \
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

    tcltest::test test8 {Tclssg as a library} \
                -setup $setup \
                -cleanup {unset result file} \
                -body {
        set project [make-temporary-project]
        set file [file join $project libtest.tcl]
        fileutil::writeFile $file [
            subst {
                source [file join $path ssg.tcl]
                tclssg configure
                tclssg command build $project/input $project/output
                puts done
            }
        ]
        set result [tcl $file]
        return [lindex $result end]
    } -result done

    tcltest::test test9 {serve command} \
                -setup $setup \
                -cleanup {close $ch; unset ch i foundServerInfo indexPage} \
                -constraints curl \
                -body {
        set project [make-temporary-project]
        tcl ssg.tcl build $project/input $project/output
        set ch [open |[list \
                [info nameofexecutable] ssg.tcl serve -verbose \
                        $project/input $project/output]]
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
        set indexPage [exec curl -s -m 1 http://$host:$port/]
        set result [string match *Tclssg* $indexPage]
        exec curl -s -m 1 http://$host:$port/bye
        return $result
    } -result 1

    # Exit with a nonzero status if there are failed tests.
    set failed [expr {$tcltest::numTests(Failed) > 0}]

    tcltest::cleanupTests
    if {$failed} {
        exit 1
    }
}
