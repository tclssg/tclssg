# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2019
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

# Procedures that are used for conversion of templates into HTML data.
set procs {
    # Convert a template into Tcl code.
    # Inspired by tmpl_parser by Kanryu KATO (http://wiki.tcl-lang.org/20363).
    proc parse {template} {
        set result {}
        lassign {<% %>} leftBracket rightBracket
        set regExpr [format {^(.*?)%s(.*?)%s(.*)$} $leftBracket $rightBracket]
        set listing "set _output {}\n"
        while {[regexp $regExpr $template _ preceding token template]} {
            append listing [list append _output $preceding]\n
            # Process <%= ... %> (expression), <%! ... %> (command)
            # and <% ... %> (raw code) syntax.
            switch -exact -- [string index $token 0] {
                = {
                    append listing \
                           [format {append _output [expr %s]} \
                                   [list [string range $token 1 end]]]
                }
                ! {
                    append listing \
                           [format {append _output [%s]} \
                                   [string range $token 1 end]]
                }
                default {
                    append listing $token
                }
            }
            append listing \n
        }
        append listing [list append _output $template]\n
        return $listing
    }

    proc entities text {
        return [string map {
            & &amp
            < &lt;
            > &gt;
            \" &quot;
            ' &#039;
        } $text]
    }

    proc file-setting {file key {default %NULL%}} {
        return [db settings preset-get $file $key $default]
    }

    proc input-to-output-path {input args} {
        named-args {
            -n                 {n 1}
            -includeIndexHtml  {includeIndexHtml 1}
        }

        set output [file rootname $input]
        if {[db config get prettyURLs 0]} {
            regexp {^(.*?)/?index$} $output _ output 
            if {$n > 1} {
                append output /page/$n
            }
            append output /
            if {$includeIndexHtml} {
                append output index.html
            }
            set output [string trimleft $output /]
        } else {
            if {$n > 1} {
                append output -$n
            }
            append output .html
        }
        return $output
    }

    proc output-to-input-path output {
        foreach input [db eval {
            SELECT input.file FROM input
        }] {
            if {[input-to-output-path $input] eq $output} {
                return [list $input $output]
            }
        }

        return {%NULL% %NULL%}
    }

    proc blog-index {} {
        # Find the blog index by the output rather than the input to account for
        # the possible differences in the file extension and to allow the index
        # to be generated at an earlier stage of the pipeline.
        set blogIndexOutput [input-to-output-path blog/index.foo]
        return [output-to-input-path $blogIndexOutput]
    }

    proc template-proc {name namedArgs template} {
        uplevel 1 [list proc \
                        $name \
                        args \
                        "named-args [list $namedArgs]\n[parse $template]"]
    } 
}

# Make this file usable both in the main project and in a safe interpreter.
if {[namespace exists ::tclssg]} {
    namespace eval ::tclssg::templates {
        namespace export *
        namespace ensemble create
        namespace eval ::tclssg::utils {}
        namespace path {::tclssg ::tclssg::utils}

        set paths [list [file join $::tclssg::path \
                                   lib/templates/templates.tcl] \
                        [file join $::tclssg::path \
                                   lib/templates]]
    }
    namespace eval ::tclssg::templates $procs
    package provide tclssg::templates 0
} else {
    eval $procs
}
unset procs
