#!/bin/sh
# Tcl ignores the next line -*- tcl -*- \
exec wish "$0" -- "$@"

# TODO:
# * controls in note windows (which?)
#  * delete, local search
# * copy, paste, basic undo
# * title
# * saving
# * tree structure of notes
# * search
# * advanced undo (without losses)
# * search through undo
# * proper undo log

package require Tk 8.5

proc main {} {
    make_tray
    make_main
    wm withdraw .
    init_globals
}

proc init_globals {} {
    global notes
    array set notes {}
    global next_note_id
    set next_note_id 1
}

proc create_note {note_name} {
    global notes
    toplevel $note_name
    scrollbar $note_name.yscroll
    pack $note_name.yscroll -side right -expand 0 -fill y
    text $note_name.text -yscrollcommand [list $note_name.yscroll set]
    if {[info exists notes(${note_name}_text)]} {
        # FIXME: extra newline
        $note_name.text insert 1.0 $notes(${note_name}_text)
    }
    pack $note_name.text -expand 1 -fill both
    focus $note_name.text

    wm protocol $note_name WM_DELETE_WINDOW [list close_note $note_name]
    bind $note_name <Escape> [list close_note $note_name]
}

proc close_note {note_name} {
    global notes
    set notes(${note_name}_text) [$note_name.text get 1.0 end]
    destroy $note_name
}

proc new_note {} {
    global next_note_id
    set note_name ".note_$next_note_id"
    create_note $note_name
    button .n.button_$next_note_id -text "Note $next_note_id" -command [list show_note $note_name]
    pack .n.button_$next_note_id
    incr next_note_id
}

proc show_note {note_name} {
    if {[winfo exists $note_name]} {
        wm state $note_name normal
        focus -force $note_name
    } else {
        create_note $note_name
    }
}

proc make_tray_tktray {} {
    set icon_data {
    #define icon_width 16
    #define icon_height 16
    static unsigned char icon_bits[] = {
       0x00, 0x00, 0x00, 0x00, 0xe0, 0x3f, 0x10, 0x20, 0x08, 0x20, 0x04, 0x20,
       0x04, 0x20, 0x04, 0x20, 0x04, 0x20, 0x04, 0x20, 0x04, 0x20, 0x04, 0x20,
       0x04, 0x20, 0xfc, 0x3f, 0x00, 0x00, 0x00, 0x00};
    }
    set icon_mask_data {
    #define mask_width 16
    #define mask_height 16
    static unsigned char mask_bits[] = {
       0x00, 0x00, 0x00, 0x00, 0xe0, 0x3f, 0xf0, 0x3f, 0xf8, 0x3f, 0xfc, 0x3f,
       0xfc, 0x3f, 0xfc, 0x3f, 0xfc, 0x3f, 0xfc, 0x3f, 0xfc, 0x3f, 0xfc, 0x3f,
       0xfc, 0x3f, 0xfc, 0x3f, 0x00, 0x00, 0x00, 0x00};
    }

    tktray::icon .tray -image [image create bitmap -data $icon_data -maskdata $icon_mask_data -background yellow -foreground black] -docked 1
    # TODO: make it appear near, or warp mouse
    bind .tray <Button-3> {wm state . normal}
    bind .tray <Button-1> new_note
}

proc make_tray_winico {} {
    global argv0
    set ico_path [file join [file dirname $argv0] note.ico]
    set ico_name [winico createfrom $ico_path]
    winico taskbar add $ico_name -text note -callback {winico_callback %m}
}

proc winico_callback {event} {
    if {$event eq "WM_LBUTTONUP"} {
        new_note
    } elseif {$event eq "WM_RBUTTONUP"} {
        # TODO:
        # * fix focus issues
        # * make it appear near, or warp mouse
        wm state . normal
    }
}

proc make_tray {} {
    if {![catch {package require tktray}]} {
        # apt-get install tk-tktray
        make_tray_tktray
    } elseif {![catch {package require Winico}]} {
        # install Winico from http://sourceforge.net/projects/tktable/files/winico/0.6/
        make_tray_winico
    } else {
        # TODO: graceful degradation
        error "No tray plugin"
    }
}

proc make_main {} {
    frame .n
    frame .b
    button .b.quit -text Quit -command {destroy .}
    pack .b.quit -side left
    pack .n .b -side top

    wm protocol . WM_DELETE_WINDOW {wm withdraw .}
    bind . <Escape> {wm withdraw .}
    bind . <FocusOut> {wm withdraw .}
}

main
