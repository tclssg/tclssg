# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2019
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

# Clean up HTML output. You need to install tidy-html5 from
# https://github.com/htacg/tidy-html5 or your operating system's package
# repository to run this stage. Windows binaries are available from
# http://binaries.html-tidy.org/. The original HTML Tidy without HTML5 support
# won't do.
namespace eval ::tclssg::pipeline::8-tidy-html {
    variable defaultOptions {
        --drop-empty-elements  0
        --indent               1
        --indent-spaces        4
        --show-warnings        0
        --tidy-mark            0
        --quiet                1
        --wrap                 0
    }

    proc transform {} {
        variable defaultOptions
        namespace path ::tclssg

        if {![db config get {tidy enable} 0]} return
        check-version
        set options [db config get {tidy options} $defaultOptions]

        set updated {}
        db transaction {
            db eval {
                SELECT file, content FROM output
                WHERE regexp('\.html?$', file) = 1
            } row {
                log::info "tidying HTML output [list $row(file)]"
                set updated [tidy $options $row(content)]
                db output set $row(file) content $updated
            }
        }
    }

    proc check-version {} {
        set version [tidy -v {}]
        if {![regexp {version ([0-9]+)\.} $version _ major]} {
            error "unrecognized HTML Tidy version: [list $version];\
                   be sure to install tidy-html5, not an older version"
        }
        if {$major < 5} {
            error "HTML Tidy must be version 5.0.0 or newer;\
                   found [list $version]"
        }
    }

    # Execute tidy(1). Ignore exit status 1, which means there were warnings,
    # but return other errors.
    proc tidy {options html} {
        try {
            exec -ignorestderr -- \
                 [db config get {tidy path} tidy] {*}$options << $html
        } trap CHILDSTATUS {result opts} {
            set code [lindex [dict get $opts -errorcode] 2]
            if {$code != 1} {
                return -options $opts $result
            }
            regsub {\nchild process exited abnormally$} $result {} result
        } on ok result {}
        return $result
    }
}
