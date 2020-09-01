# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

# Config file parsing and validation.
namespace eval ::tclssg::config {
    namespace export *
    namespace ensemble create
    namespace path ::tclssg

    variable schema {
        abbreviate
        blogPostsPerFile
        {deployCopy path}
        {deployCustom end}
        {deployCustom file}
        {deployCustom start}
        {deployFTP password}
        {deployFTP path}
        {deployFTP port}
        {deployFTP server}
        {deployFTP user}
        {feeds formats}
        {feeds feedDescription}
        {feeds posts}
        {feeds tagFeeds}
        inputDir
        {markdown converter}
        {markdown tabs}
        macros
        outputDir
        prettyURLs
        {rss enable}
        {rss feedDescription}
        {rss posts}
        {rss tagFeeds}
        {server host}
        {server port}
        {sitemap enable}
        tagPages
        {tidy enable}
        {tidy options}
        {tidy path}
        url
    }

    # Load the website configuration file from the directory inputDir. Return
    # the raw content of the file without validating it. If $verbose is true
    # print the content.
    proc load {inputDir {verbose 1}} {
        set configRaw [utils::read-file \
            -encoding binary \
            -translation auto \
            [file join $inputDir website.conf]]
        set configWithShorthand [utils::remove-comments $configRaw]
        set config [utils::dict-expand-shorthand $configWithShorthand]

        # Show loaded config to user (without the password values).
        if {$verbose} {
            set formatted \
                [utils::dict-format [utils::obscure-password-values $config] \
                                    "%s %s\n" \
                                    {
                                        converter
                                        end
                                        feedDescription
                                        file
                                        host
                                        inputDir
                                        options
                                        outputDir
                                        path
                                        server
                                        start
                                        url
                                        user
                                    }]
            log::info "loaded config file \{"
            log::info [::textutil::indent $formatted {    }]\n\}
        }
        validate $config
        return $config
    }

    # Check the website config for errors that may not be caught elsewhere.
    proc validate config {
        # Check that the website URL ends with a '/'.
        set url [utils::dict-default-get {} $config url]
        if {($url ne {}) && ([string index $url end] ne "/")} {
            error {"url" in the website config does not end with "/"}
        }

        if {[dict exists $config rss enable]
            && [dict exists $config feeds formats]} {

            if {[dict get $config rss enable]
                && {rss} ni [dict get $config feeds formats]} {
                error {website config error: {rss enable} is true\
                       but {feeds formats} does not contain "rss"}
            }

            if {![dict get $config rss enable]
                && {rss} in [dict get $config feeds formats]} {
                error {website config error: {rss enable} is false\
                       but {feeds formats} contains "rss"}
            }
        }
    }

    # Check that the config conforms to the schema. Flatten the config into a
    # {path value ...} dict.
    proc parse-by-schema config {
        variable schema

        set flattened {}
        foreach keyPath $schema {
            if {[dict exists $config {*}$keyPath]} {
                dict set flattened $keyPath [dict get $config {*}$keyPath]
                dict set config {*}$keyPath {}
                while {[llength $keyPath] > 0} {
                    if {[dict get $config {*}$keyPath] eq {}} {
                        dict unset config {*}$keyPath
                    } else {
                        break
                    }
                    set keyPath [lrange $keyPath 0 end-1]
                }
            }
        }
        if {$config ne {}} {
            error "unknown settings in website config: \"$config\""
        }
        return $flattened
    }
}

package provide tclssg::config 0
