#!/usr/bin/env tclsh
# A static website generator in Tcl.
# Copyright (C) 2013, 2014 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

package require fileutil
package require textutil::expander

# Returns the content of file fname.
proc read-file {fname {binary 0}} {
    set fpvar [open $fname r]
    if {$binary} {
        fscriptConfigure $fpvar -translation binary
    }
    set content [read $fpvar]
    close $fpvar
    return $content
}

# Save content to file fname.
proc write-file {fname content {binary 0}} {
    set fpvar [open $fname w]
    if {$binary} {
        fscriptConfigure $fpvar -translation binary
    }
    puts -nonewline $fpvar $content
    close $fpvar
}

# Transform a path relative to fromDir into the same path relative to toDir.
proc replace-path-root {path fromDir toDir} {
    file join $toDir \
              [::fileutil::relative $fromDir [file dirname $path]] \
              [file tail $path]
}

# Set up template interpreter and expander.
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

# Tear down template interpreter.
proc interp-down {} {
    interp delete templateInterp
}

# Convert raw Markdown to HTML using an external Markdown processor.
proc markdown-to-html {markdown} {
    upvar 1 scriptConfig scriptConfig

    exec -- {*}$scriptConfig(markdownProcessor) << $markdown
}

proc template-subst {template rawContent websiteConfig} {
    upvar 1 scriptConfig scriptConfig

    interp-up $websiteConfig

    # Macroexpand content then convert it from Markdown to HTML.
    set content [markdown-to-html [::exp expand $rawContent]]
    # Expand template with content substituted in.
    interp eval templateInterp [format {set {%s} {%s}} content $content]
    set result [::exp expand $template]

    interp-down

    return $result
}

# Process the page inputFile (a file containing Markdown + template code).
# put its rendered content into a template under the same path relative to
# outputDir that inputFile is relative to inputDir.
proc page-file-to-html {inputFile \
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

# Process input files in inputDir to produce static website in outputDir.
proc compile-website {inputDir outputDir websiteConfig} {
    upvar 1 scriptConfig scriptConfig

    # Process page files.
    foreach file [fileutil::findByPattern $inputDir -glob *.md] {
        page-file-to-html $file \
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
    set scriptConfig(markdownProcessor) \
        {perl scripts/Markdown_1.0.1/Markdown.pl}

    set scriptConfig(contentDirName) pages
    set scriptConfig(templateDirName) templates
    set scriptConfig(staticDirName) static
    set scriptConfig(templateFileName) default.thtml
    set scriptConfig(websiteConfigFileName) website.conf

    set scriptConfig(templateBrackets) {<% %>}

    set sourceDir [lindex $argv 1]
    set destDir [lindex $argv 2]

    set websiteConfig \
        [read-file \
            [file join $sourceDir $scriptConfig(websiteConfigFileName)]]
    puts "Loaded config file:\n$websiteConfig\n"
    # init command.
    switch -exact -- [lindex $argv 0] {
        init {
            foreach dir [list $scriptConfig(contentDirName) \
                              $scriptConfig(templateDirName) \
                              $scriptConfig(staticDirName)] {
                file mkdir [file join $scriptConfig(sourceDir) $dir]
            }
            file mkdir $scriptConfig(destDir)
            exit 0
        }
        upload-copy {
            set uploadDest [dict get $websiteConfig uploadDestCopy]

            foreach file [fileutil::find $destDir {file isfile}] {
                set destFile [replace-path-root $file $destDir $uploadDest]
                puts "copying $file to $destFile"
                if {![file isdir [file dirname $destFile]]} {
                    file mkdir [file dirname $destFile]
                }
                file copy -force $file $destFile
            }
            exit 0
        }
        upload-ftp {
            puts "not implemented"
            exit 1
        }
        build {
            if {[file isdir $sourceDir]} {
                compile-website \
                    $sourceDir \
                    $destDir \
                    $websiteConfig
            } else {
                puts "couldn't access directory \"$sourceDir\""
                exit 1
            }
        }
    }
}

main $argv