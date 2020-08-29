#!/usr/bin/env tclsh
# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

package require fileutil  1
package require struct    2
package require tcltest   2

namespace eval ::tclssg::tests {
    variable path [file dirname [file dirname [file normalize $argv0/___]]]

    lappend ::auto_path $path
    namespace eval ::tclssg [list variable path $path]

    package require http     2
    package require logger   0-2
    package require sqlite3  3
    package require try      1

    package require tclssg::cli
    package require tclssg::config
    package require tclssg::converters
    package require tclssg::db
    package require tclssg::debugger
    package require tclssg::interpreter
    package require tclssg::pipeline
    package require tclssg::templates
    package require tclssg::utils

    package require tclssg::vendor::Markdown

    namespace path ::tclssg
    namespace import ::tclssg::utils::*

    ::logger::initNamespace ::tclssg error

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
            try {
                socket -server {} $port
            } on ok ch {
                close $ch
                return $port
            } on error {} {}
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
    tcltest::testConstraint cmark [expr {
        ![catch {exec cmark --version}] &&
        [regexp {CommonMark converter} [exec cmark --version]]
    }]

    tclssg::db::init



    ### Unit tests.

    set correctSeconds [clock scan {2014-06-26-20-10} \
            -format {%Y-%m-%d-%H-%M}]
    set correctSecondsShort [clock scan {2014-01-01-00-00-00} \
            -format {%Y-%m-%d-%H-%M-%S}]
    set correctSecondsUTC [clock scan {2014-06-26-20-10} \
            -format {%Y-%m-%d-%H-%M} -gmt 1]

    tcltest::test incremental-clock-scan-1.1 {incremental-clock-scan} \
    -body {
        incremental-clock-scan {2014-06-26 20:10}
    } \
    -result [list $correctSeconds %Y-%m-%dT%H:%M]

    tcltest::test incremental-clock-scan-1.2 {incremental-clock-scan} \
    -body {
        incremental-clock-scan {2014-06-26T20:10}
    } \
    -result [list $correctSeconds %Y-%m-%dT%H:%M]

    tcltest::test incremental-clock-scan-1.3 {incremental-clock-scan} \
    -body {
        incremental-clock-scan {2014 06 26 20 10}
    } \
    -result [list $correctSeconds {%Y-%m-%dT%H:%M}]

    tcltest::test incremental-clock-scan-1.4 {incremental-clock-scan} \
    -body {
        incremental-clock-scan {2014/06/26 20:10}
    } \
    -result [list $correctSeconds {%Y-%m-%dT%H:%M}]

    tcltest::test incremental-clock-scan-2.1 {incremental-clock-scan 2} \
    -body {
        incremental-clock-scan {2014}
    } \
    -result [list $correctSecondsShort %Y]

    tcltest::test incremental-clock-scan-2.2 {incremental-clock-scan 2} \
    -body {
        incremental-clock-scan {2014-01}
    } \
    -result [list $correctSecondsShort %Y-%m]

    tcltest::test incremental-clock-scan-2.3 {incremental-clock-scan 2} \
    -body {
        incremental-clock-scan {2014-01-01 00:00:00}
    } \
    -result [list $correctSecondsShort {%Y-%m-%dT%H:%M:%S}]

    tcltest::test incremental-clock-scan-3.1 {incremental-clock-scan with TZ} \
    -body {
        incremental-clock-scan {2014-06-26 20:10:00Z}
    } \
    -result [list $correctSecondsUTC {%Y-%m-%dT%H:%M:%S%z}]

    tcltest::test incremental-clock-scan-3.2 {incremental-clock-scan with TZ} \
    -body {
        incremental-clock-scan {2014-06-26 20:10:00+00}
    } \
    -result [list $correctSecondsUTC {%Y-%m-%dT%H:%M:%S%z}]

    tcltest::test incremental-clock-scan-3.3 {incremental-clock-scan with tz} \
    -body {
        incremental-clock-scan {2014-06-26 20:10:00-2400}
    } \
    -result [list [clock add $correctSecondsUTC 1 day] {%Y-%m-%dT%H:%M:%S%z}]

    tcltest::test incremental-clock-scan-3.4 {incremental-clock-scan with tz} \
    -body {
        incremental-clock-scan {2014-06-26 20:10:00-24:00}
    } \
    -result [list [clock add $correctSecondsUTC 1 day] {%Y-%m-%dT%H:%M:%S%z}]

    tcltest::test incremental-clock-scan-4.0 {incremental-clock-scan with tz} \
    -body {
        incremental-clock-scan nope
    } \
    -returnCodes error -result {no known format matches date-time string nope}

    tcltest::test incremental-clock-scan-5.0 {with options} \
    -body {
        incremental-clock-scan {2014-05-06 17:08} {-timezone Europe/Kiev}
    } \
    -result {1399385280 %Y-%m-%dT%H:%M}

    tcltest::test incremental-clock-scan-5.1 {with options} \
    -body {
        incremental-clock-scan {2014-06-26 20:10:00} {-timezone Europe/Kiev}
    } \
    -result [list [clock add $correctSecondsUTC -3 hours] %Y-%m-%dT%H:%M:%S]

    tcltest::test incremental-clock-scan-5.2 {with options} \
    -body {
        incremental-clock-scan {2014-06-26 20:10:00Z} {-timezone Europe/Kiev}
    } \
    -result [list $correctSecondsUTC %Y-%m-%dT%H:%M:%S%z]


    tcltest::test slugify-1.1 {slugify} \
    -body {
        slugify {Hello, World!}
    } \
    -result hello-world

    tcltest::test slugify-1.2 {slugify} \
    -body {
        slugify {hello world}
    } \
    -result hello-world

    tcltest::test slug-compare-1.1 {} -body {
        slug-compare {Hello, World!} {hello world}
    } \
    -result 0

    tcltest::test slug-compare-1.2 {} -body {
        slug-compare {HELLO      WORLD     } {    hello world}
    } \
    -result 0

    tcltest::test slug-compare-2.1 {} -body {
        slug-compare foo bar
    } \
    -result 1

    tcltest::test slug-compare-2.2 {} -body {
        slug-compare bar foo
    } \
    -result -1

    tcltest::test replace-path-root-1.1 {replace-path-root} \
    -body {
        replace-path-root ./a/b/c/d/e/f ./a ./x
    } \
    -result x/b/c/d/e/f

    tcltest::test replace-path-root-1.2 {replace-path-root} \
    -body {
        replace-path-root ./a/b/c/d/e/f ./a/b/c ./x/b/c
    } \
    -result x/b/c/d/e/f

    tcltest::test replace-path-root-1.3 {replace-path-root} \
    -body {
        replace-path-root a/b/c/d/e/f a x
    } \
    -result x/b/c/d/e/f

    tcltest::test replace-path-root-1.4 {replace-path-root} \
    -body {
        replace-path-root a/b/./c/d/e/f a/b/c x/b/c
    } \
    -result x/b/c/d/e/f

    tcltest::test replace-path-root-1.5 {replace-path-root} \
    -body {
        replace-path-root /././././././././b / /a
    } \
    -result /a/b

    tcltest::test dict-default-get-1.1 {dict-default-get} \
    -body {
        dict-default-get testValue {} someKey
    } \
    -result testValue

    tcltest::test dict-default-get-1.2 {dict-default-get} \
    -body {
        dict-default-get -1 {someKey testValue} someKey
    } \
    -result testValue

    tcltest::test dict-default-get-1.3 {dict-default-get} \
    -body {
        dict-default-get -1 {someKey {anotherKey testValue}} \
                         someKey anotherKey
    } \
    -result testValue

    tcltest::test add-number-before-extension-1.1 {add-number-before-extension}\
    -body {
        add-number-before-extension "filename.ext" 0
    } \
    -result filename.ext

    tcltest::test add-number-before-extension-1.2 {add-number-before-extension}\
    -body {
        add-number-before-extension "filename.ext" 0 "-%d" 1
    } \
    -result filename-0.ext

    tcltest::test add-number-before-extension-1.3 {add-number-before-extension}\
    -cleanup {unset result} \
    -body {
        set result {}

        for {set i 1} {$i < 11} {incr i} {
            lappend result [add-number-before-extension "filename.ext" $i]
        }

        return $result
    } \
    -result [list \
        filename-1.ext filename-2.ext filename-3.ext filename-4.ext \
        filename-5.ext filename-6.ext filename-7.ext filename-8.ext \
        filename-9.ext filename-10.ext \
    ]

    tcltest::test add-number-before-extension-1.4 {add-number-before-extension}\
    -cleanup {unset result} \
    -body {
        set result {}

        for {set i 1} {$i < 11} {incr i} {
            lappend result [add-number-before-extension "filename.ext" \
                    $i "%03d"]
        }

        return $result
    } \
    -result [list \
        filename001.ext filename002.ext filename003.ext filename004.ext \
        filename005.ext filename006.ext filename007.ext filename008.ext \
        filename009.ext filename010.ext \
    ]

    tcltest::test add-number-before-extension-1.5 {add-number-before-extension}\
    -cleanup {unset result} \
    -body {
        set result {}

        for {set i 1} {$i < 11} {incr i} {
            lappend result [add-number-before-extension "filename.ext" \
                    $i "%03d" -1]
        }

        return $result
    } \
    -result [list \
        filename001.ext filename002.ext filename003.ext filename004.ext \
        filename005.ext filename006.ext filename007.ext filename008.ext \
        filename009.ext filename010.ext \
    ]

    tcltest::test separate-frontmatter-1.1 separate-frontmatter \
    -cleanup {unset prased result first elem} \
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
    } \
    -result 1

    tcltest::test group-by-1.1 group-by \
    -cleanup {unset i result} \
    -body {
        set result {}
        for {set i 1} {$i < 7} {incr i} {
            lappend result [group-by $i {a b c d e f}]
        }
        return $result
    } \
    -result [list \
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
    } \
    -result [list \
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
    } \
    -returnCodes error -result {expected an integer >= 1 but got "0"}

    tcltest::test markdown-1.1 {Built-in Markdown converter} \
    -body {
        db config set {markdown converter} {}
        ::tclssg::converters::markdown::markdown-to-html {* hi}
    } \
    -match regexp \
    -result {<ul>.*?<li>hi</li>.*?</ul>}

    tcltest::test markdown-2.1 cmark \
                -constraints cmark \
    -body {
        db config set {markdown converter} cmark
        ::tclssg::converters::markdown::markdown-to-html {* hi}
    } \
    -match regexp \
    -result {<ul>.*?<li>hi</li>.*?</ul>}

    tcltest::test markdown-3.1 {Tabs in Markdown} \
    -cleanup {unset md} \
    -body {
        set md "```\ntarget:\n\tcommand foo bar\n```"
        list [Markdown::convert $md 0] \
             [Markdown::convert $md 1]
    } \
    -result [list \
        "<pre><code>target:\n    command foo bar</code></pre>" \
        "<pre><code>target:\n\tcommand foo bar</code></pre>" \
    ]

    tcltest::test markdown-4.1 {Fenced code block language 1} \
    -cleanup {unset md} \
    -body {
        set md "```make\ntarget:\n\tcommand foo bar\n```"
        Markdown::convert $md 1
    } \
    -result "<pre><code class=\"language-make\">target:\n\tcommand\
             foo bar</code></pre>"

    tcltest::test markdown-4.2 {Fenced code block language 2} \
    -body {
        Markdown::convert "```!@#$%^&*()\nhi\n```"
    } \
    -result "<pre><code class=\"language-!@#$%^&amp;*()\">hi</code></pre>"

    tcltest::test markdown-4.3 {Fenced code block language 3} \
    -body {
        Markdown::convert "```foo bar baz\nhi\n```"
    } \
    -result "<pre><code class=\"language-foo\">hi</code></pre>"

    tcltest::test markdown-5.1 {Newlines in HTML tag 1} \
    -body {
        Markdown::convert <div>Hello</div>
    } \
    -result <div>Hello</div>\n

    tcltest::test markdown-5.2 {Newlines in HTML tag 2} \
    -body {
        Markdown::convert <div>\nHello\n</div>
    } \
    -result <div>\nHello\n</div>\n

    # The tests markdown-5.{3,4,5} test for the behavior of John Gruber's
    # original Markdown.pl.  An implementation of CommonMark would remove
    # the repeated newlines and wrap the "Hello" in 5.4-5.5 in a <p>.
    tcltest::test markdown-5.3 {Newlines in HTML tag 3} \
    -body {
        Markdown::convert <div>\nHello\n\n\n</div>
    } \
    -result <div>\nHello\n\n\n</div>\n

    tcltest::test markdown-5.4 {Newlines in HTML tag 4} \
    -body {
        Markdown::convert <div>\n\nHello</div>
    } \
    -result <div>\n\nHello</div>\n

    tcltest::test markdown-5.5 {Newlines in HTML tag 5} \
    -body {
        Markdown::convert <div>\n\nHello\n\n\n</div>
    } \
    -result <div>\n\nHello\n\n\n</div>\n

    tcltest::test named-args-1.1 named-args \
    -cleanup {unset args foo bar baz} \
    -body {
        set args {-foo 1 -bar 5}
        utils::named-args {
            -foo  foo
            -bar  bar
            -baz  {baz default}
        }
        return [list $foo $bar $baz]
    } \
    -result {1 5 default}

    tcltest::test named-args-1.2 {named-args missing} \
    -cleanup {unset args foo bar} \
    -body {
        set args {-foo 1 -bar 5}
        utils::named-args {
            -foo  foo
            -bar  bar
            -baz  baz
        }
    } \
    -returnCodes error \
    -result {missing required argument -baz}

    tcltest::test named-args-1.3 {named-args extra} \
    -cleanup {unset args foo bar} \
    -body {
        set args {-foo 1 -bar 5 -qux wat}
        utils::named-args {
            -foo  foo
            -bar  bar
        }
    } \
    -returnCodes error \
    -result {unknown extra arguments: "-qux wat"}

    tcltest::test remove-comments-1.1 remove-comments \
    -body {
        utils::remove-comments {
            foo 1
            # Comment.
            bar 2
            baz 3
                   # Another comment.
        }
    } \
    -match regexp \
    -result {\n\s+foo 1\n\s+bar 2\n\s+baz 3\n\s+}

    tcltest::test remove-comments-1.2 {remove-comments used wrong} \
    -body {
        utils::remove-comments {foo 1 # Not actually a comment.
                                bar 2}
    } \
    -match regexp \
    -result {foo 1 # Not actually a comment.\n\s+bar 2}

    tcltest::test longest-common-list-prefix-1.1 {simple usage} \
    -body {
        list [utils::longest-common-list-prefix {} {}] \
             [utils::longest-common-list-prefix {} foo] \
             [utils::longest-common-list-prefix foo {}] \
             [utils::longest-common-list-prefix foo foo] \
             [utils::longest-common-list-prefix {foo bar baz} {foo}] \
             [utils::longest-common-list-prefix {foo bar baz} {foo bar}] \
             [utils::longest-common-list-prefix {foo bar} {foo bar baz}] \
             [utils::longest-common-list-prefix foo {foo bar baz}] \
    } \
    -result {{} {} {} foo foo {foo bar} {foo bar} foo}


    tcltest::test dict-expand-shorthand-1.1 {} \
    -body {
        return \n[dict-format [utils::dict-expand-shorthand {
            foo {
                bar {
                    baz 1
                }
            }
        }]]
    } \
    -result {
foo {
    bar {
        baz 1
    }
}
}

    tcltest::test dict-expand-shorthand-1.2 {} \
    -body {
        return \n[dict-format [utils::dict-expand-shorthand {
            {foo bar} {
                baz 1
            }
            {foo qux} 2
        }]]
    } \
    -result {
foo {
    bar {
        baz 1
    }
    qux 2
}
}

    tcltest::test dict-expand-shorthand-1.3 {} \
    -body {
        return \n[dict-format [utils::dict-expand-shorthand {
            {foo bar} {
                baz 1
            }
            foo {
                qux 2
            }
        }]]
    } \
    -result {
foo {
    bar {
        baz 1
    }
    qux 2
}
}

    tcltest::test dict-expand-shorthand-1.4 {} \
    -body {
        return \n[dict-format [utils::dict-expand-shorthand {
            {foo bar} {
                baz 1
            }
            {foo qux} 2
        }]]
    } \
    -result {
foo {
    bar {
        baz 1
    }
    qux 2
}
}

    tcltest::test dict-expand-shorthand-1.5 {} \
    -body {
        return \n[dict-format [utils::dict-expand-shorthand {
            {foo bar} {
                baz 1
            }
            {foo qux quux} 2
        }]]
    } \
    -result {
foo {
    bar {
        baz 1
    }
    qux {
        quux 2
    }
}
}

    tcltest::test dict-expand-shorthand-1.6 {} \
    -body {
        return \n[dict-format [utils::dict-expand-shorthand {
            foo {
                bar {
                    baz 1
                }
            }
            {foo bar qux} 2
        }]]
    } \
    -result {
foo {
    bar {
        baz 1
        qux 2
    }
}
}

    tcltest::test dict-expand-shorthand-2.1 {} \
    -body {
        return \n[dict-format [utils::dict-expand-shorthand {
            {foo bar} {
                baz 1
            }
            {foo bar baz} 2
        }]]
    } \
    -returnCodes error \
    -match glob \
    -result {can't merge*}


    tcltest::test trim-indentation-1.1 {empty string} \
    -body {
        utils::trim-indentation {}
    } \
    -result {}

    tcltest::test trim-indentation-1.2 {one level} \
    -body {
        list \
            [utils::trim-indentation " a\n b\n c"] \
            [utils::trim-indentation "    a\n    b\n    c"] \
            [utils::trim-indentation "\ta\n\tb\n\tc" " \t"] \
    } \
    -result [list a\nb\nc a\nb\nc a\nb\nc]

    tcltest::test trim-indentation-1.3 {different levels} \
    -body {
        list \
            [utils::trim-indentation " a\n  b\n c"] \
            [utils::trim-indentation "    a\n            b\n        c"] \
            [utils::trim-indentation "\ta\n\t\tb\n\tc" " \t"] \
    } \
    -result [list "a\n b\nc" "a\n        b\n    c" a\n\tb\nc]

    tcltest::test trim-indentation-1.5 {trailing newlines} \
    -body {
        list \
            [utils::trim-indentation " a\n  b\n c\n"] \
            [utils::trim-indentation "    a\n            b\n        c\n"] \
            [utils::trim-indentation "\ta\n\t\tb\n\tc" " \t\n"] \
    } \
    -result [list "a\n b\nc" "a\n        b\n    c" a\n\tb\nc]

    tcltest::test trim-indentation-1.6 {leading newlines} \
    -body {
        list \
            [utils::trim-indentation "\n a\n  b\n c"] \
            [utils::trim-indentation "\n    a\n            b\n        c"] \
            [utils::trim-indentation "\n\ta\n\t\tb\n\tc" " \t"] \
    } \
    -result [list "a\n b\nc" "a\n        b\n    c" a\n\tb\nc]

    tcltest::test trim-indentation-1.7 {empty lines} \
    -body {
        list \
            [utils::trim-indentation " a\n\n  b\n c"] \
            [utils::trim-indentation "    a\n            b\n\n        c"] \
            [utils::trim-indentation "\ta\n\n\t\tb\n\n\tc" " \t"] \
    } \
    -result [list "a\n\n b\nc" "a\n        b\n\n    c" a\n\n\tb\n\nc]

    tcltest::test trim-indentation-1.8 {non-leading whitespace} \
    -body {
        list \
            [utils::trim-indentation "a  a\nb  b\nc  c"] \
            [utils::trim-indentation " a \n b \n c"] \
            [utils::trim-indentation "a     "] \
    } \
    -result [list "a  a\nb  b\nc  c" "a \nb \nc" "a     "]

    tcltest::test trim-indentation-1.9 {trailing whitespace line} \
    -body {
        utils::trim-indentation {
            foo
            bar
            baz
        }
    } \
    -result foo\nbar\nbaz

    tcltest::test trim-indentation-1.10 {only whitespace} \
    -body {
        list \
            [utils::trim-indentation { }] \
            [utils::trim-indentation " \n "] \
            [utils::trim-indentation x\nxx\nxxxx\nxx\nx x] \
    } \
    -result "{} {} {\nxx\n}"



    ### Tool tests.

    tcltest::test log-search-1.1 {usage message} \
    -body {
        tcl tools/log-search.tcl --help 2>@1
    } \
    -result {usage: log-search.tcl regexp [file [--no-color]]}

    tcltest::test log-search-1.2 {error message} \
    -cleanup {unset result} \
    -body {
        catch {
            tcl tools/log-search.tcl {} /tmp/xyz/this/should/not/exist 2>@1
        } result
        set result
    } \
    -match glob \
    -result {*couldn't open /tmp/xyz/this/should/not/exist*}

    tcltest::test log-search-2.1 {line retention} \
    -body {
        tcl tools/log-search.tcl {} - --no-color \
            << "foo bar baz\n        yup\n    qux hey"
    } \
    -result "foo bar baz\nfoo bar yup\nfoo qux hey"

    tcltest::test log-search-3.1 {regexp match} \
    -body {
        tcl tools/log-search.tcl blo+g - --no-color \
            << "1 foo\n  bar blog.md\n2 hello\n3.\n   qux blog.html\n4 ?\n5 !"
    } \
    -result "1 bar blog.md\n3. qux blog.html"

    tcltest::test log-search-4.1 {braces 1} \
    -body {
        tcl tools/log-search.tcl key - --no-color \
            << "hi \{\n  a b\n    key value\n\}"
    } \
    -result {    key value}

    tcltest::test log-search-4.2 {braces 2} \
    -body {
        tcl tools/log-search.tcl key - --no-color \
            << "\{\n  a b\n    key value\n\}"
    } \
    -result {    key value}

    tcltest::test log-search-5.1 color \
    -constraints unix \
    -body {
        tcl tools/log-search.tcl {} << "a b\n  c"
    } \
    -match regexp \
    -result {(?:\x1b\[2m)a[^\n]+?(?:\x1b\[39m)(?:\x1b\[22m)?c}


    proc flatten-settings settings {
        regsub -all {\n +} $settings \n settings
        regsub -all \n+ $settings \n settings

        return $settings
    }

    tcltest::test migrate-1.1 {migrate v1.0.1 website config} \
    -body {
        source tools/migrate.tcl
        return \n[flatten-settings [dict get [migrate::config {
            websiteTitle {SSG Test}
            url {http://example.com/}
            server {
                host localhost
                port 8080
            }
            sitemap {
                enable 1
            }
            rss {
                enable 1
                tagFeeds 1
            }
            indexPage {index.md}
            blogIndexPage {blog/index.md}
            tagPage {blog/tags/tag.md}
            outputDir {../output}
            blogPostsPerFile 10
            description {This is an example website project for Tclssg.}
            deployCustom {
                start {scp -rp "$outputDir" localhost:/tmp/deployment-test/}
                file {}
                end {}
            }
            enableMacrosInPages 0
            comments {
                engine none
                disqusShortname {}
            }
        }] config]]
    } \
    -result {
# The setting "blogIndexPage" has been removed (was: "blog/index.md").
blogPostsPerFile 10
deployCustom {
start {scp -rp "$outputDir" localhost:/tmp/deployment-test/}
file {}
end {}
}
# The setting "description" has been removed\
  (was: "This is an example website project for Tclssg.").
macros 0
# The setting "indexPage" has been removed (was: "index.md").
outputDir ../output
rss {
enable 1
tagFeeds 1
}
server {
host localhost
port 8080
}
sitemap {
enable 1
}
# The setting "tagPage" has been removed (was: "blog/tags/tag.md").
url http://example.com/
}

    tcltest::test migrate-1.2 {migrate v1.0.1 page settings} \
    -body {
        source tools/migrate.tcl

        return \n[flatten-settings [dict get [migrate::config {
            pageSettings {
                gridClassPrefix col-md-
                contentColumns 8
                locale en_US
                hideUserComments 1
                hideSidebarNote 1
                sidebarPosition right
                navbarItems {
                    Home $indexLink
                    Blog $blogIndexLink
                    Contact {$rootDirPath/contact.html}
                }
                bootstrapTheme\
{$rootDirPath/external/bootstrap-3.3.1-dist/css/bootstrap-theme.min.css}
                customCss {{$rootDirPath/tclssg.css}}
            }
        }] presets default]]
    } \
    -result {
bootstrap {
version 3
contentColumns 8
gridClassPrefix col-md-
theme vendor/bootstrap/css/bootstrap-theme.min.css
}
comments {
enable 0
}
customCSS tclssg.css
locale en_US
navbar {
items {Home / Blog /blog/ Contact /contact.html}
}
sidebar {
note {
enable 0
}
position right
}
}

    tcltest::test migrate-1.3 {migrate v1.0.1 blog post settings} \
    -body {
        source tools/migrate.tcl
        return \n[flatten-settings [dict get [migrate::config {
            blogPostSettings {
                hideUserComments 0
                hideSidebarNote 0
                moreText {(<a href="$link">read more</a>)}
                sidebarNote {
                    <h3>About</h3>
                    This is the blog of the sample Tclssg project.
                }
            }
        }] presets blog]]
    } \
    -result {
comments {
enable 1
}
more {
markup {(<a href="$link">read more</a>)}
}
sidebar {
note {
content {
<h3>About</h3>
This is the blog of the sample Tclssg project.
}
enable 1
}
}
}

    tcltest::test migrate-2.1 {migrate nested page settings} \
    -body {
        source tools/migrate.tcl
        return \n[migrate::page {
            article {
                top foo
            }
            body {
                top bar
                bottom baz
            }
        }]
    } \
    -result {
article {
    top foo
}
body {
    bottom baz
    top bar
}
}

    tcltest::test migrate-3.1 {merge locale page setting} \
    -body {
        source tools/migrate.tcl
        return \n[migrate::page {
            locale foo
            %FROM_CONFIG% {
                locale bar
            }
        }]
    } \
    -result {
locale foo
}

    tcltest::test migrate-3.2 {merge locale page setting} \
    -body {
        source tools/migrate.tcl
        return \n[migrate::page {
            %FROM_CONFIG% {
                locale bar
            }
        }]
    } \
    -result {
locale bar
}
    tcltest::test migrate-3.3 {merge locale page setting} \
    -body {
        source tools/migrate.tcl
        return \n[migrate::page {
            %FROM_CONFIG% {
                locale {}
            }
        }]
    } \
    -result {
}

    tcltest::test migrate-3.1 {empty group} \
    -cleanup {rename migrate::empty-group {}} \
    -body {
        source tools/migrate.tcl

        proc migrate::empty-group settings {
            namespace path dsl

            set acc {}

            group alwaysEmpty {
                id noSuchSetting
            }

            group foo {
                id bar
            }

            drain

            return [join $acc \n]
        }

        return \n[migrate::empty-group {bar 5}]
    } \
    -result {
foo {
    bar 5
}
}



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

    proc modify-config {inputDir updates} {
        set config [config load $inputDir]
        ::fileutil::writeFile $inputDir/website.conf \
                              [dict merge $config $updates]
        return
    }

    tcltest::test command-line-1.1 {Tclssg command line commands} \
    -body {
        tcl ssg.tcl version
        tcl ssg.tcl help
    } \
    -match glob \
    -result {*usage: ssg.tcl*}

    tcltest::test command-line-1.2 {Tclssg command line commands} \
    -constraints {unix diff} \
    -cleanup {unset result} \
    -body {
        variable project
        set tclssgArguments [list $project]

        # Set deployment options in the website config.
        modify-config $project [dict create \
            deployCopy [dict create path $project/deploy-copy-test] \
            deployCustom [dict create \
                start [list cp -r \$outputDir $project/deploy-custom-test] \
                file {} \
                end {} \
            ] \
        ]

        tcl ssg.tcl build {*}$tclssgArguments
        tcl ssg.tcl update --yes {*}$tclssgArguments
        tcl ssg.tcl build {*}$tclssgArguments
        tcl ssg.tcl deploy-copy {*}$tclssgArguments
        tcl ssg.tcl deploy-custom {*}$tclssgArguments
        tcl ssg.tcl clean {*}$tclssgArguments

        set result [exec diff -r \
                $project/deploy-copy-test \
                $project/deploy-custom-test]
        return $result
    } \
    -result {}

    tcltest::test command-line-1.3 {serve command} \
    -cleanup {
        close $ch
        unset ch foundServerInfo i indexPage serveCommand
    } \
    -body {
        variable project

        set port [unused-port]
        modify-config $project [dict create \
            server [dict create \
                host localhost \
                port $port \
            ] \
        ]

        tcl ssg.tcl build $project $project/output
        set serveCommand [list [info nameofexecutable] ssg.tcl serve \
                                                               -verbose \
                                                               $project]
        set ch [open |$serveCommand]
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
            # Give the server approximately two seconds to start up.
            if {$i > 200} {
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
    } \
    -result 1

    tcltest::test tclssg-library-1.1 {Tclssg as a library} \
    -cleanup {unset project result file} \
    -body {
        set project [make-temporary-project]
        set file [file join $project libtest.tcl]
        fileutil::writeFile $file [list \
            apply {{path project} {
                source [file join $path ssg.tcl]
                tclssg configure $path
                tclssg cli command build $project $project/output
                puts done
            }} $path $project \
        ]
        set result [tcl $file]
        return [lindex $result end]
    } \
    -result done



    # Exit with a nonzero status if there are failed tests.
    set failed [expr {$tcltest::numTests(Failed) > 0}]

    tcltest::cleanupTests
    if {$failed} {
        exit 1
    }
}
