#!/usr/bin/env tclsh
# Tclssg, a static website generator.
# Copyright (C) 2013, 2014 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

package require control
package require struct
package require fileutil

control::control assert enabled 1

proc assert-all-equal args {
    if {[lindex $args 0] == "-listmode"} {
        set prevArg [lindex $args 1]
        foreach arg [lrange $args 2 end] {
            control::assert [struct::list equal $arg $prevArg]
            set prevArg $arg
        }
    } else {
        set prevArg [lindex $args 0]
        foreach arg [lrange $args 1 end] {
            control::assert [list \"$arg\" eq \"$prevArg\"]
            set prevArg $arg
        }
    }
}

proc main {argv0 argv} {
    puts "running procedure tests..."

    set scriptLocation [file dirname $argv0]

    # Import utility functions.
    source [file join $scriptLocation utils.tcl]
    namespace import ::utils::*

    # incremental-clock-scan
    assert-all-equal [
        incremental-clock-scan {2014-06-26 20:10}
    ] [
        incremental-clock-scan {2014-06-26T20:10}
    ] [
        incremental-clock-scan {2014 06 26 20 10}
    ] [
        incremental-clock-scan {2014/06/26 20:10}
    ] [
        list [clock scan {2014-06-26-20-10} -format {%Y-%m-%d-%H-%M}] \
                {%Y-%m-%dT%H:%M}
    ]

    assert-all-equal [
        lindex [incremental-clock-scan {2014}] 0
    ] [
        lindex [incremental-clock-scan {2014-01}] 0
    ] [
        lindex [incremental-clock-scan {2014-01-01 00:00:00}] 0
    ] [
        clock scan {2014-01-01} -format {%Y-%m-%d}
    ]

    # slugify
    assert-all-equal [
        slugify "Hello, World!"
    ] [
        slugify "hello world"
    ] "hello-world"

    # replace-path-root
    assert-all-equal [
        replace-path-root ./a/b/c/d/e/f ./a ./x
    ] [
        replace-path-root ./a/b/c/d/e/f ./a/b/c ./x/b/c
    ] "x/b/c/d/e/f"

    assert-all-equal [
        replace-path-root a/b/c/d/e/f a x
    ] [
        replace-path-root a/b/./c/d/e/f a/b/c x/b/c
    ] "x/b/c/d/e/f"

    assert-all-equal [
        replace-path-root /././././././././b / /a
    ] "/a/b"

    # dict-default-get
    assert-all-equal [
        dict-default-get testValue {} someKey
    ] [
        dict-default-get -1 {someKey testValue} someKey
    ] [
        dict-default-get -1 {someKey {anotherKey testValue}} \
                         someKey anotherKey
    ] "testValue"

    # add-number-before-extension
    assert-all-equal [
        add-number-before-extension "filename.ext" 0
    ] "filename.ext"

    assert-all-equal [
        add-number-before-extension "filename.ext" 0 "-%d" 1
    ] "filename-0.ext"

    for {set i 1} {$i < 11} {incr i} {
        assert-all-equal [
            add-number-before-extension "filename.ext" $i
        ] "filename-$i.ext"
        assert-all-equal [
            add-number-before-extension "filename.ext" $i "%03d"
        ] [
            add-number-before-extension "filename.ext" $i "%03d" -1
        ] [
            format "filename%03d.ext" $i
        ]
    }

    # get-page-variables
    assert-all-equal -listmode [
        get-page-variables "{hello world} Hello, world!"
    ] [
        get-page-variables "{ hello world } Hello, world!"
    ] [
        get-page-variables "{hello world}

            Hello, world!"
    ] [
        get-page-variables "{
                hello world
            }
            Hello, world!"
    ] [list [list hello world] "Hello, world!"]

    # Tclssg init, build.
    puts "running build tests..."
    set tempProjectDir [::fileutil::tempfile]
    # Remove the temporary file so that Tclssg can replace it with
    # a temporary project directory.
    file delete $tempProjectDir
    set tclssgArguments [
        list [file join $tempProjectDir input] \
             [file join $tempProjectDir output]
    ]
    exec tclsh ssg.tcl version
    exec tclsh ssg.tcl help
    exec tclsh ssg.tcl init {*}$tclssgArguments
    exec tclsh ssg.tcl build {*}$tclssgArguments
    exec tclsh ssg.tcl update --templates --yes {*}$tclssgArguments
    exec tclsh ssg.tcl build {*}$tclssgArguments
    exec tclsh ssg.tcl clean {*}$tclssgArguments

    # Tclssg as library.
    puts "running tclssg library tests..."
    set file [file join $tempProjectDir libtest.tcl]
    fileutil::writeFile $file [
        subst {
            source [file join $scriptLocation ssg.tcl]
            tclssg configure
            tclssg command build {*}$tclssgArguments
        }
    ]
    exec tclsh $file

    file delete -force $tempProjectDir

    puts "done."
}

main $argv0 $argv
