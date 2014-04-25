#!/bin/sh
# Tcl ignores the next line -*- tcl -*- \
exec wish "$0" -- "$@"

# TODO:
# * controls in note windows (which?)
#  * delete, local search
# + copy, paste, basic undo
# + title
# * saving
#   * locking
# * cli
# * search through all
# * use?
# * tree structure of notes
# * advanced undo (without losses)
# * search through undo
# * proper undo log

package require Tk 8.5

proc main {} {
    init_globals
    init_events
    make_tray
    make_main
    wm withdraw .
}

proc init_events {} {
    event add <<Copy>> <Control-c>
    event add <<Copy>> <Control-Insert>
    event add <<Cut>> <Control-x>
    event add <<Cut>> <Shift-Delete>
    event add <<Paste>> <Control-v>
    event add <<Paste>> <Shift-Insert>

    event delete <<Paste>> <Control-y>
    event add <<Redo>> <Control-y>
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
    text $note_name.text -yscrollcommand [list $note_name.yscroll set] -undo 1
    if {[info exists notes(${note_name}_text)]} {
        # FIXME: extra newline
        $note_name.text insert 1.0 $notes(${note_name}_text)
    }
    if {[info exists notes(${note_name}_title)]} {
        wm title $note_name "Note: $notes(${note_name}_title)"
    }
    bind $note_name.text <<Modified>> [list handle_textModified $note_name]

    pack $note_name.text -expand 1 -fill both

    wm protocol $note_name WM_DELETE_WINDOW [list close_note $note_name]
    bind $note_name <Escape> [list close_note $note_name]

    focus $note_name.text
}

proc handle_textModified {note_name} {
    if {![$note_name.text edit modified]} {
        return
    }

    global notes
    set title [$note_name.text get 1.0 1.end]
    if {$title eq ""} {
        set title [string replace $note_name 0 5]
    }
    set notes(${note_name}_title) $title
    wm title $note_name "Note: $notes(${note_name}_title)"
    $note_name.text edit modified 0
}

proc handle_titleChanged {note_id notes_name note_title_idx write} {
    if {$notes_name ne "notes" || $write ne "write"} {
        return
    }
    global notes

    set note_name ".note_$note_id"
    if {[winfo exists $note_name]} {
        wm title $note_name "Note: $notes($note_title_idx)"
    }
    .n.button_$note_id configure -text "$notes($note_title_idx)"
}

proc close_note {note_name} {
    global notes
    set notes(${note_name}_text) [$note_name.text get 1.0 end]
    destroy $note_name
}

proc new_note {} {
    global next_note_id notes
    set note_name ".note_$next_note_id"
    create_note $note_name
    button .n.button_$next_note_id -command [list show_note $note_name]
    trace add variable notes(${note_name}_title) write [list handle_titleChanged $next_note_id]
    set notes(${note_name}_title) $next_note_id
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
