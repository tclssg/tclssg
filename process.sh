#!/bin/sh
markdown="perl scripts/Markdown_1.0.1/Markdown.pl"
header="templates/header.html"
footer="templates/footer.html"
content="content"
pages="$content/pages"
static="$content/static"
output="$content/output"

markdown_to_html() {
    output_file=$output/$(basename $1 | sed -e "s/.md$//").html
    echo processing $1 into $output_file
    cat $header > $output_file
    $markdown $1 | sed -e "s/^/            /" >> $output_file
    cat $footer >> $output_file
}

init() {
    echo Creating directories...
    mkdir -p $content
    mkdir -p $pages
    mkdir -p $static
    mkdir -p $output
    cd $content
    if [ ! -d .git ]; then
        echo output/\* > .gitignore
        git init
    fi
    exit 0
}

compile_website() {
    # If $output is not empty...
    if [ "$(ls -A $output)" ]; then
        rm -vr $output/*
    fi

    for file in $pages/*.md; do
        markdown_to_html $file
    done

    cp -vR $static/* $output/
}

if [ "$1" == "init" ]; then
    init
fi


if [ ! -d $pages -o ! -d $static -o ! -d $output ]; then
    echo Error. Run $0 init first.
    exit 1
fi

compile_website