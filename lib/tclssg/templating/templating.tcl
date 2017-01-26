# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

# Procedures that are used for conversion of templates and Markdown into
# HTML data.
namespace eval ::tclssg::templating {
    namespace export *
    namespace ensemble create

    # Convert raw Markdown to HTML.
    proc markdown-to-html {markdown} {
        set markdownProcessor $::tclssg::config(markdownProcessor)
        if {$markdownProcessor eq ":internal:"} {
            ::Markdown::convert $markdown
        } else {
            exec -- {*}$markdownProcessor << $markdown
        }
    }

    proc inline-markdown-to-html {text} {
        set html [markdown-to-html $text]
        # strip paragraph wrapping, we assume to be in an inline context.
        regexp {<p>(.*)</p>} $html -> html
        return $html
    }

    # Make HTML out of rawContent (remove frontmatter, if any; expand macros
    # if enableMacrosInPages is enabled in websiteConfig; convert Markdown
    # to HTML).
    proc prepare-content {rawContent id {extraVariables {}}} {
        set choppedContent \
                [lindex [::tclssg::utils::get-page-settings $rawContent] 1]
        # Macroexpand content if needed then convert it from Markdown to
        # HTML.
        if {[tclssg pages get-website-config-setting \
                    enableMacrosInPages 0]} {
            set choppedContent [join [list \
                    [::tclssg::utils::trim-indentation \
                            [tclssg pages get-setting $id pagePrelude ""]] \
                    $choppedContent] "\n"]

            tclssg debugger save-intermediate-id \
                    $id content-1-toexpand $choppedContent
            set choppedContent [interpreter render \
                    $choppedContent \
                    $id \
                    $extraVariables]
        }

        set cookedContent [markdown-to-html $choppedContent]

        tclssg debugger save-intermediate-id \
                $id content-2-markdown $choppedContent
        tclssg debugger save-intermediate-id \
                $id content-3-html $cookedContent

        return $cookedContent
    }

    # Render template substituting in (already HTMLized) content from
    # cookedContent according to the settings in pageData. This is just
    # a wrapper for [interpreter render] for now.
    proc apply-template {template cookedContent id {extraVariables {}}} {
        set result [interpreter render \
                $template \
                $id \
                [list content $cookedContent {*}$extraVariables]]
        return $result
    }

    # Convert a template into Tcl code.
    # Inspired by tmpl_parser by Kanryu KATO (http://tcl.wiki/20363).
    proc parse {template} {
        set result {}
        lassign $::tclssg::config(templateBrackets) leftBracket rightBracket
        set regExpr [format {^(.*?)%s(.*?)%s(.*)$} $leftBracket $rightBracket]
        set listing "set _output {}\n"
        while {[regexp $regExpr $template \
                match preceding token template]} {
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
} ;# namespace templating
