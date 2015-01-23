#!/bin/sh
grep -n proc      ssg.tcl  > $$
grep -n namespace ssg.tcl >> $$
cat $$ | grep -v 'namespace export' \
       | grep -v 'namespace ensemble' \
       | grep -v 'namespace current' \
       | grep -v 'namespace parent' \
       | sed -e 's| ;#| #|' -e 's|#.*$||g' -e 's|[ 	]*$||g' \
       | grep -v '^[0-9]*:$' \
       | sort -n > ssg.txt
rm $$
exit

