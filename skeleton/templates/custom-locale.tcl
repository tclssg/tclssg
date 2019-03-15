# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2019
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

apply {{} {
    foreach {text translation} {
        {Published %1$s}
        {Choyvfurq %1$s}
        
        {Published %1$s, updated %2$s}
        {Choyvfurq %1$s, hcqngrq %2$s}
        
        {Tagged: <ul>%1$s</ul>}
        {Gnttrq: <ul>%1$s</ul>}
    } {
        localization set en_US_rot13 ::article $text $translation   
    }

    foreach {text translation} {
        {Tag RSS} {Gnt EFF}

        RSS EFF

        {Posts tagged "%1$s"} {Cbfgf gnttrq "%1$s"}

        {page %1$s} {cntr %1$s}

        Posts Cbfgf

        {« Newer posts} {« Arjre cbfgf}

        {Older posts »} {Byqre cbfgf »}

        Tags Gntf
    } {
        localization set en_US_rot13 ::document $text $translation   
    }
}}
