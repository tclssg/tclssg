# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017, 2018 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

# Wrapper for a safe interpreter for templates.
namespace eval ::tclssg::templating::interpreter {
    namespace export *
    namespace ensemble create

    ::safe::interpCreate cleanInterp
    set defaultVars [interp eval cleanInterp {info vars}]
    variable defaultVarValues {}
    variable defaultArrayValues {}
    foreach varName $defaultVars {
        if {[catch {dict set defaultVarValues $varName \
                [interp eval cleanInterp [list set $varName]]}]} {
            dict set defaultArrayValues $varName \
                    [interp eval cleanInterp [list array get $varName]]
        }
    }
    unset defaultVars
    variable defaultNamespaces [interp eval cleanInterp {namespace children ::}]

    # Set variable $key to $value in the template interpreter $interp for each
    # key-value pair in a dictionary.
    proc inject {interp dictionary} {
        dict for {key value} $dictionary {
            interp eval $interp [list set $key $value]
        }
    }

    # Create and set up a new template interpreter $interp or reset an 
    # existing one.
    proc up {interp inputDir} {
        # Create a safe interpreter to use for rendering templates (the
        # template interpreter).
        if {![interp exists $interp]} {
            ::safe::interpCreate $interp
        } else {
            # Reset global variables.
            variable defaultVarValues
            inject $interp $defaultVarValues
            variable defaultArrayValues
            foreach {varName value} $defaultArrayValues {
                interp eval $interp [list array set $varName $value]
            }
        }
        ::safe::interpAddToAccessPath $interp [file join \
                $inputDir \
                $::tclssg::config(templateDirName)]
        ::safe::interpAddToAccessPath $interp [file join \
                $::tclssg::config(skeletonDir) \
                $::tclssg::config(templateDirName)]

        # Alias commands to be used in templates.
        foreach {command alias} {
            ::tclssg::version                   tclssg-version
            ::tclssg::utils::replace-path-root  replace-path-root
            ::tclssg::utils::dict-default-get   dict-default-get
            ::textutil::indent                  ::textutil::indent
            ::tclssg::utils::slugify            slugify
            puts                                puts
            ::tclssg::templating::inline-markdown-to-html
                                                markdown-to-html
            ::tclssg::pages::get-setting        get-page-setting
            ::tclssg::pages::get-data           get-page-data
            ::tclssg::pages::get-website-config-setting
                                            get-website-config-setting
            ::tclssg::pages::get-tag-list       get-tag-list
            ::tclssg::pages::get-link           get-page-link
            ::tclssg::pages::get-tags           get-page-tags
            ::tclssg::pages::get-tag-page       get-tag-page
            ::tclssg::pages::get-output-file    get-output-file
            ::msgcat::mc                        mc
            ::msgcat::mcset                     mcset
            ::msgcat::mclocale                  mclocale
            ::html::html_entities               entities
            ::tclssg::templating::parse         parse-template
            ::tclssg::read-data-file            read-data-file

            ::csv::iscomplete                   ::csv::iscomplete
            ::csv::split                        ::csv::split
            ::json::json2dict                   ::json::json2dict
        } {
            interp alias $interp $alias {} {*}$command
        }

        interp alias \
                $interp with-cache-for-filename \
                {} ::tclssg::templating::interpreter::with-cache $interp

        interp alias $interp get-rss-file {} apply {{callback id} {
            return [$callback [tclssg pages get-data $id inputFile]]
        }} $::tclssg::pages::rssFileCallback

        # Allow templates to read and source files from the templates
        # subdirectory with path failover.
        interp alias $interp read-template-file \
                {} ::tclssg::read-template-file-literal $inputDir
        interp alias $interp resolve-template-file-path \
                {} ::tclssg::resolve-template-file-path $inputDir

        interp eval $interp {
            proc interp-source {filename} {
                uplevel #0 [list source [resolve-template-file-path $filename]]
            }
            proc include {filename} {
                uplevel #0 [list eval \
                        [parse-template [read-template-file $filename]]]
            }
        }
        return $interp
    }

    # Render template for page pageData.
    proc render {template id {extraVariables {}}} {
        up templateInterp [tclssg pages get-website-config-setting inputDir ""]]
        interp eval templateInterp [list set currentPageId $id]
        inject templateInterp $extraVariables
        set listing [tclssg templating parse $template]
        set result [interp eval templateInterp $listing]
        if {![tclssg pages get-website-config-setting \
                reuseTemplateInterpreter 0]} {
            interp delete templateInterp
        }

        return $result
    }

    # Run $script and cache the result. Return that result immediately
    # if the script has already been run for $filename.
    proc with-cache {interp filename script} {
        set cache [namespace parent]::cache
        if {[$cache exists $filename $script]} {
            set result [$cache get $filename $script]
        } else {
            set result [interp eval $interp $script]
            $cache set $filename $script $result
        }
        return $result
    }
} ;# namespace interpreter
