#!/usr/bin/env tclsh
# Tclssg, a static website generator.
# Copyright (C) 2013, 2014 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

package require control
package require struct
package require fileutil

source utils.tcl

control::control assert enabled 1

proc assertAllEqual args {
    set prevArg [lindex $args 0]
    foreach arg [lrange $args 1 end] {
        control::assert {$arg eq $prevArg}
        set prevArg $arg
    }
}

proc main {argv0 argv} {
    # incremental-clock-scan
    assertAllEqual [
        incremental-clock-scan {2014-06-26 20:10}
    ] [
        incremental-clock-scan {2014-06-26T20:10}
    ] [
        incremental-clock-scan {2014 06 26 20 10}
    ] [
        incremental-clock-scan {2014/06/26 20:10}
    ] [
        clock scan {2014-06-26-20-10} -format {%Y-%m-%d-%H-%M}
    ]

    # slugify
    assertAllEqual [
        slugify "Hello, World!"
    ] [
        slugify "hello world"
    ] "hello-world"

    # replace-path-root
    assertAllEqual [
        replace-path-root ./a/b/c/d/e/f ./a ./x
    ] [
        replace-path-root ./a/b/c/d/e/f ./a/b/c ./x/b/c
    ] "./x/b/c/d/e/f"

    assertAllEqual [
        replace-path-root a/b/c/d/e/f a x
    ] [
        replace-path-root a/b/c/d/e/f a/b/c x/b/c
    ] "x/b/c/d/e/f"

    assertAllEqual [
        replace-path-root /././././././././b / /a
    ] "/a/b"

    # dict-default-get
    assertAllEqual [
        dict-default-get testValue {} someKey
    ] [
        dict-default-get -1 {someKey testValue} someKey
    ] [
        dict-default-get -1 {someKey {anotherKey testValue}} \
                          someKey anotherKey
    ] "testValue"

    # dict-sort
    assertAllEqual [
        dict-sort {a {k 5} b {k 1} c {k 2}} k
    ] [
        dict-sort {a {k 5} b {k 1} c {k 2}} k 0 {} {x {lindex $x}}
    ] {b {k 1} c {k 2} a {k 5}}
}

main $argv0 $argv