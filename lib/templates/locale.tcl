# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2019
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

namespace eval ::localization {
    namespace export *
    namespace ensemble create -map {
        debug   debug
        format  format
        get     get
        set     lcset
    }

    variable msgs {}

    proc lcset {locale scope text {translation %SAME_AS_TEXT%}} {
        variable msgs

        if {$translation eq {%SAME_AS_TEXT%}} {
            set translation $text
        }

        dict set msgs [string tolower $locale] $scope $text $translation
    }

    proc get {locale scope text} {
        variable msgs

        set translation $text
        set path [list [string tolower $locale] $scope $text]
        if {[dict exists $msgs {*}$path]} {
            set translation [dict get $msgs {*}$path]
        }

        return $translation
    }

    proc format {locale scope text args} {
        set translation [get $locale $scope $text]

        if {[llength $args] == 0} {
            return $translation
        }
        return [format $translation {*}$args]
    }
}

localization set en_US ::article {Published %1$s}
localization set en_US ::article {Published %1$s, updated %2$s}
localization set en_US ::article {Tagged: <ul>%1$s</ul>}

localization set en_US ::document {Tag RSS}
localization set en_US ::document RSS
localization set en_US ::document {Posts tagged "%1$s"}
localization set en_US ::document {page %1$s}
localization set en_US ::document Posts
localization set en_US ::document {« Newer posts}
localization set en_US ::document {Older posts »}
localization set en_US ::document Tags
