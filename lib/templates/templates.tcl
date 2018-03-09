# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017, 2018 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

# Procedures that are used for conversion of templates and Markdown into
# HTML data.
set procs {
    # Convert raw Markdown to HTML.
    proc markdown-to-html {markdown} {
        ::Markdown::convert $markdown
    }

    proc inline-markdown-to-html {text} {
        set html [markdown-to-html $text]
        # strip paragraph wrapping, we assume to be in an inline context.
        regexp {<p>(.*)</p>} $html -> html
        return $html
    }

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
        set blogDefaults [db settings get config blogDefaults {}]
        set pageDefaults [db settings get config pageDefaults {}]
        set value [db settings get $file $key]
        if {$value ne {%NULL%}} {
            return $value
        }
        if {[db settings get $file blogPost 0]} {
            set value [dict-default-get %NULL% $blogDefaults $key]
            if {$value ne {%NULL%}} {
                return $value
            }
        }
        return [dict-default-get $default $pageDefaults $key]
    }

    proc input-to-output-path {input args} {
        set n [dict-default-get 1 $args -n]
        set includeIndexHtml [dict-default-get 1 $args -includeIndexHtml]

        set output [file rootname $input]
        if {[db settings get config prettyURLs 0]} {
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

    proc template-proc {name arguments template} {
        uplevel 1 [list proc $name $arguments [parse $template]]
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
