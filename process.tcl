#!/usr/bin/env tclsh
# A basic static website generator in shell script
# Copyright (C) 2013, 2014 Danyil Bohdan, see the file LICENSE

package require fileutil
package require textutil::expander

# Helper procs
proc read-file {fname {binary 0}} {
    set fpvar [open $fname r]
    if {$binary} {
        fscriptConfigure $fpvar -translation binary
    }
    set content [read $fpvar]
    close $fpvar
    return $content
}

proc write-file {fname content {binary 0}} {
    set fpvar [open $fname w]
    if {$binary} {
        fscriptConfigure $fpvar -translation binary
    }
    puts -nonewline $fpvar $content
    close $fpvar
}

proc replace-path-root {path fromDir toDir} {
    file join $toDir \
              [::fileutil::relative $fromDir [file dirname $path]] \
              [file tail $path]
}

# Core
proc interp-up {websiteConfig} {
    upvar 1 scriptConfig scriptConfig

    # Create safe interpreter and expander for templates. Those are global.
    interp create -safe templateInterp
    dict for {key value} $websiteConfig {
        interp eval templateInterp [format {set {%s} {%s}} $key $value]
    }
    if {![catch {::textutil::expander exp}]} {
        ::exp evalcmd {interp eval templateInterp}
        ::exp setbrackets {*}$scriptConfig(templateBrackets)
    }
}

proc interp-down {} {
    interp delete templateInterp
}

# Convert raw Markdown to HTML using an external processor.
proc markdown-to-html {markdown} {
    upvar 1 scriptConfig scriptConfig

    exec -- {*}$scriptConfig(markdownProcessor) << $markdown
}

proc template-subst {template rawContent websiteConfig} {
    upvar 1 scriptConfig scriptConfig

    interp-up $websiteConfig

    # Macroexpand content and then convert is from Markdown to HTML.
    set content [markdown-to-html [::exp expand $rawContent]]
    # Expand template with content substituted in.
    interp eval templateInterp [format {set {%s} {%s}} content $content]
    set result [::exp expand $template]

    interp-down

    return $result
}

proc markdown-file-to-html {inputFile \
                            inputDir \
                            templateDir \
                            outputDir \
                            websiteConfig} {
    upvar 1 scriptConfig scriptConfig

    set template \
        [read-file \
            [file join $templateDir $scriptConfig(templateFileName)]]

    set outputFile \
        [file rootname \
            [replace-path-root $inputFile $inputDir $outputDir]].html
    set subdir [file dirname $outputFile]

    if {![file isdir $subdir]} {
        puts "creating directory $subdir"
        file mkdir $subdir
    }

    puts "processing markdown file $inputFile into $outputFile"
    set output [template-subst $template [read-file $inputFile] $websiteConfig]
    write-file $outputFile $output
}

proc compile-website {inputDir outputDir websiteConfig} {
    upvar 1 scriptConfig scriptConfig
    # Del outputDir/*?

    # Process page files.
    foreach file [fileutil::findByPattern $inputDir -glob *.md] {
        markdown-file-to-html $file \
                              [file join $inputDir \
                                         $scriptConfig(contentDirName)] \
                              [file join $inputDir \
                                         $scriptConfig(templateDirName)] \
                              $outputDir \
                              $websiteConfig
    }

    # Copy static files verbatim.
    foreach file [fileutil::find \
                     [file join $inputDir $scriptConfig(staticDirName)]] {
        if {[file isfile $file]} {
            set destFile \
                [replace-path-root $file \
                             [file join $inputDir $scriptConfig(staticDirName)]\
                             $outputDir]
            puts "copying static file $file to $destFile"
            file copy -force $file $destFile
        }
    }
}

proc main {argv} {
    # Configuration.
    set scriptConfig(markdownProcessor) {perl scripts/Markdown_1.0.1/Markdown.pl}

    set scriptConfig(contentDirName) pages
    set scriptConfig(templateDirName) templates
    set scriptConfig(staticDirName) static
    set scriptConfig(templateFileName) template.html

    set scriptConfig(sourceDir) [file join data input]
    set scriptConfig(destDir) [file join data output]

    set scriptConfig(templateBrackets) {<% %>}

    set websiteConfig {websiteTitle {Danyil Bohdan}}

    # init command.
    if {[lindex $argv 0] eq "init"} {
        foreach dir [list $scriptConfig(contentDirName) \
                          $scriptConfig(templateDirName) \
                          $scriptConfig(staticDirName)] {
            file mkdir [file join $scriptConfig(sourceDir) $dir]
        }
        file mkdir $scriptConfig(destDir)
        exit
    }

    compile-website \
        $scriptConfig(sourceDir) \
        $scriptConfig(destDir) \
        $websiteConfig
}

main $argv