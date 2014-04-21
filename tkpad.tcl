#!/bin/sh
# Tcl ignores the next line -*- tcl -*- \
exec wish "$0" -- "$@"

package require Tk 8.5

scrollbar .yscroll
pack .yscroll -side right -expand 0 -fill y
text .text -yscrollcommand {.yscroll set}
pack .text -expand 1 -fill both

