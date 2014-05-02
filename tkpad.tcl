#!/bin/sh
# Tcl ignores the next line -*- tcl -*- \
exec wish "$0" -- "$@"

# TODO:
# + copy, paste, basic undo
# + title
# + saving
# + loading
# + fallback when no tray is available
# + warn and continue if tray library not available
# * controls in note window (opens by single ~Alt~Control?)
#   * bar button hiding
# * note deletion
# * tree structure of notes
# * cli. Functionality:
#   * point to the directory
#   * theme
#   * else?
# * search through all
# * lock in save directory
# * advanced undo (without losses)
# * proper undo log
# * search through undo

package require Tk 8.5

proc main {} {
    init_globals
    init_fs
    init_events
    make_tray
    make_main
    load_notes
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
    global save_path env
    set save_path [file join $env(HOME) ".tkpad"]
}

proc init_fs {} {
    global save_path
    file mkdir $save_path
}

proc load_notes {} {
    global save_path
    foreach note_path [glob -nocomplain -directory $save_path "text.note_*"] {
        set note_basename [file tail $note_path]
        if ([regexp {^text\.note_([0-9]+)$} $note_basename _ note_idx]) {
            set in [open $note_path r]
            set note_content [read $in]
            close $in
            restore_note $note_idx $note_content
        }
    }
}

proc note_text_tk {idx} {
    return .note_${idx}.main.text
}

proc note_window_tk {idx} {
    return .note_${idx}
}

proc create_note {idx} {
    global notes
    set note_window ".note_$idx"
    set note_text $note_window.main.text

    toplevel $note_window

    frame $note_window.buttons
    button $note_window.buttons.new_note -text "New" -command new_note
    button $note_window.buttons.main_window -text "Main Window" -command {wm state . normal}
    entry $note_window.buttons.search
    pack $note_window.buttons.new_note $note_window.buttons.main_window -side left
    pack $note_window.buttons.search -expand 1 -fill x

    frame $note_window.main
    scrollbar $note_window.main.yscroll -takefocus 0
    pack $note_window.main.yscroll -side right -expand 0 -fill y
    text $note_text -yscrollcommand [list $note_window.main.yscroll set] -undo 1
    if {[info exists notes($idx,text)]} {
        # FIXME: extra newline
        $note_text insert 1.0 $notes($idx,text)
    }
    if {[info exists notes($idx,title)]} {
        wm title $note_window "Note: $notes($idx,title)"
    }
    pack $note_text -expand 1 -fill both

    pack $note_window.buttons $note_window.main -expand 1 -fill both -side top

    $note_text edit modified 0
    bind $note_text <<Modified>> [list handle_textModified $idx]
    bind $note_window.buttons.search <Return> [list search_note $idx $note_window.buttons.search]
    bind $note_window <F3> [list search_note $idx $note_window.buttons.search]
    bind $note_window <Shift-F3> [list search_note $idx $note_window.buttons.search backward]
    bind $note_window <Control-n> [list focus $note_window.buttons.new_note]
    bind $note_window <Control-m> [list focus $note_window.buttons.main_window]
    bind $note_window <Control-f> [list focus $note_window.buttons.search]
    wm protocol $note_window WM_DELETE_WINDOW [list close_note $idx]
    bind $note_window <Escape> [list close_note $idx]

    focus $note_text
}

proc search_note {idx search_widget {dir "forward"}} {
    set pattern [$search_widget get]
    if {$pattern eq ""} {
        return
    }

    if {$dir eq "forward"} {
        set where "-forwards"
        set from "insert + 1 chars"
    } else {
        set where "-backwards"
        set from "insert - 1 chars"
    }

    set found [[note_text_tk $idx] search $where $pattern $from]

    if {$found ne ""} {
        [note_text_tk $idx] mark set insert $found
        [note_text_tk $idx] see insert
        focus [note_text_tk $idx]
    }
}

proc handle_textModified {idx} {
    if {![[note_text_tk $idx] edit modified]} {
        return
    }

    global notes
    set notes($idx,text) [[note_text_tk $idx] get 1.0 end]
    set title [[note_text_tk $idx] get 1.0 1.end]
    if {$title eq ""} {
        set title $idx
    }
    set notes($idx,title) $title
    wm title [note_window_tk $idx] "Note: $notes($idx,title)"
    [note_text_tk $idx] edit modified 0

    global save_path
    set note_path [file join $save_path "text.note_$idx"]
    set f [open $note_path w]
    puts -nonewline $f $notes($idx,text)
    close $f
}

proc handle_titleChanged {idx notes_name note_title_idx write} {
    if {$notes_name ne "notes" || $write ne "write"} {
        return
    }
    global notes

    set note_name [note_window_tk $idx]
    if {[winfo exists $note_name]} {
        wm title $note_name "Note: $notes($note_title_idx)"
    }
    .n.button_$idx configure -text "$notes($note_title_idx)"
}

proc close_note {idx} {
    global notes
    destroy [note_window_tk $idx]
}

proc new_note {} {
    global next_note_id notes
    set idx $next_note_id
    incr next_note_id
    create_note $idx
    button .n.button_$idx -command [list show_note $idx]
    trace add variable notes($idx,title) write [list handle_titleChanged $idx]
    set notes($idx,title) $idx
    pack .n.button_$idx
}

proc restore_note {idx content} {
    global next_note_id notes
    button .n.button_$idx -command [list show_note $idx]
    pack .n.button_$idx
    trace add variable notes($idx,title) write [list handle_titleChanged $idx]
    set notes($idx,text) $content
    set first_newline [string first "\n" $content]
    if {$first_newline > 0} {
        set notes($idx,title) [string range $content 0 [expr $first_newline - 1]]
    } elseif {$content ne ""} {
        set notes($idx,title) $content
    } else {
        set notes($idx,title) $idx
    }
    if {$next_note_id <= $idx} {
        set next_note_id [expr $idx + 1]
    }
}

proc show_note {idx} {
    set note_name [note_window_tk $idx]
    if {[winfo exists $note_name]} {
        wm state $note_name normal
        focus -force [note_text_tk $idx]
    } else {
        create_note $idx
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
    global has_tray
    if {![catch {package require tktray}]} {
        # apt-get install tk-tktray
        make_tray_tktray
        set has_tray 1
    } elseif {![catch {package require Winico}]} {
        # install Winico from http://sourceforge.net/projects/tktable/files/winico/0.6/
        make_tray_winico
        set has_tray 1
    } else {
        tk_messageBox -type ok -message "Tray support not found"
        set has_tray 0
    }
}

proc make_main {} {
    frame .n
    frame .b
    button .b.quit -text Quit -command {destroy .}
    pack .b.quit -side left
    button .b.new -text New -command new_note
    pack .b.new -side left
    pack .n .b -side top

    global has_tray
    if {$has_tray} {
        wm protocol . WM_DELETE_WINDOW {wm withdraw .}
        bind . <Escape> {wm withdraw .}
        bind . <FocusOut> {if {%W eq "."} {wm withdraw .}}
        wm withdraw .
    } else {
        wm protocol . WM_DELETE_WINDOW {wm iconify .}
        bind . <Escape> {wm iconify .}
        bind . <FocusOut> {if {"%W" eq "."} {wm iconify .}}
        wm iconify .
    }
}

main
