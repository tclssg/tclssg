#!/bin/sh
markdown="perl scripts/Markdown_1.0.1/Markdown.pl"
header="templates/header.html"
footer="templates/footer.html"
pages="content/pages"
static="content/static"
output="output"

rm -r $output/*

mkdir -p $pages
mkdir -p $static
mkdir -p $output

markdown_to_html() {
    output_file=$output/$(basename $1 | sed -e "s/.md$//").html
    echo Processing $1 into $output_file
    cat $header > $output_file
    $markdown $1 | sed -e "s/^/            /" >> $output_file
    cat $footer >> $output_file
}

for file in $pages/*.md; do
    markdown_to_html $file
done

cp -vR content/static/* output/