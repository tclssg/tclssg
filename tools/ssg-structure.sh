#!/bin/sh
set -e
temp_file=$(mktemp)
trap "rm -f \"$temp_file\"" 0 1 2 3 15
grep -n proc      ssg.tcl  > $temp_file
grep -n namespace ssg.tcl >> $temp_file
cat $temp_file \
| grep -v 'namespace export' \
| grep -v 'namespace ensemble' \
| grep -v 'namespace current' \
| grep -v 'namespace parent' \
| sed -e 's| ;#| #|' -e 's|#.*$||g' -e 's|[ 	]*$||g' \
| grep -v '^[0-9]*:$' \
| awk 'BEGIN{FS=OFS=":"} {$1 = sprintf("%4d", $1); print}' \
| sort -n \
| tee ssg.txt
exit
