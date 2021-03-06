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
# + search through all
#  * fix focus order after search
# * sort alphabetically
# * scrolled button frame
#  * fix the scroll itself
# * tree structure of notes
# * note deletion
# * advanced undo (without losses) - stop losing time! designating features first!
# * proper undo log
# * here is something to show
# * controls in note window (opens by single ~Alt~Control?)
#   * bar button hiding
# * cli. Functionality:
#   * point to the directory
#   * theme
#   * else?
# * lock in save directory
# * search through undo

package require Tk 8.5

proc main {} {
    init_globals
    init_fs
    init_events
    load_config
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
    set icon_photo_base64 {R0lGODlhEAAQAKECAP3/WwAAAP///////yH5BAEKAAIALAAAAAAQABAAAAIqlI+pyxIPoQqg2hoS
vTefzVmeAYbA6JgiUoZoy70qxs5nPb/R/jT+jygAADs=}
    global icon_photo_name
    set icon_photo_name [image create photo -data $icon_photo_base64]
    global global_search_pattern
    set global_search_pattern ""
    global tray_disabled
    set tray_disabled 0
}

proc init_fs {} {
    global save_path
    file mkdir $save_path
}

proc load_config {} {
    global save_path
    set config [file join $save_path "config.tcl"]
    if {[file exists $config]} {
        source $config
    } else {
        set f [open $config w]
        puts $f "# uncomment and edit the following:"
        puts $f ""
        puts $f "# font configure TkFixedFont -family {MS Comic Sans}"
        puts $f ""
        puts $f "# global tray_disabled"
        puts $f "# set tray_disabled 1"
        close $f
    }
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
    ui_update_notes
}

proc note_text_tk {idx} {
    return .note_${idx}.main.text
}

proc note_window_tk {idx} {
    return .note_${idx}
}

proc note_button_tk {idx} {
    return .n.scrolled.buttons.button_${idx}
}

proc create_note {idx} {
    global notes icon_name
    set note_window ".note_$idx"
    set note_text $note_window.main.text

    toplevel $note_window
    # wm iconphoto $note_window $icon_name

    frame $note_window.buttons
    button $note_window.buttons.new_note -text "New" -command new_note
    button $note_window.buttons.main_window -text "Main Window" -command {
        wm state . normal
        focus -force .
    }
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

    pack $note_window.buttons -expand 0 -fill both -side top
    pack $note_window.main -expand 1 -fill both -side top

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

    focus -force $note_text
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
    if {[winfo exists [note_button_tk $idx]]} {
        [note_button_tk $idx] configure -text "$notes($note_title_idx)"
    }
}

proc close_note {idx} {
    global notes
    destroy [note_window_tk $idx]
}

proc new_note {} {
    hide_main
    global next_note_id notes
    set idx $next_note_id
    incr next_note_id
    create_note $idx
    trace add variable notes($idx,title) write [list handle_titleChanged $idx]
    set notes($idx,title) $idx
    set notes($idx,visible) 1
    ui_update_notes
}

proc restore_note {idx content} {
    global next_note_id notes
    trace add variable notes($idx,title) write [list handle_titleChanged $idx]
    set notes($idx,text) $content
    set notes($idx,visible) 1
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
    hide_main
    set note_name [note_window_tk $idx]
    if {[winfo exists $note_name]} {
        wm state $note_name normal
        focus -force [note_text_tk $idx]
    } else {
        create_note $idx
    }
}

proc hide_main {} {
    global has_tray
    if {$has_tray} {
        wm withdraw .
    } else {
        wm iconify .
    }
}

proc make_tray_tktray {} {
    global icon_photo_name
    tktray::icon .tray -image $icon_photo_name -docked 1
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
    global has_tray tray_disabled
    if {$tray_disabled} {
        set has_tray 0
    } elseif {![catch {package require tktray}]} {
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
    global global_search_pattern

    frame .b
    button .b.quit -text Quit -command {destroy .}
    pack .b.quit -side left
    button .b.new -text New -command new_note
    pack .b.new -side left
    entry .b.search -textvariable global_search_pattern
    trace add variable global_search_pattern write handle_global_search_pattern
    pack .b.search -side left -expand 1 -fill x

    frame .n
    scrollbar .n.scroll -takefocus 0
    pack .n.scroll -side right -expand 0 -fill y
    text .n.scrolled -yscrollcommand {.n.scroll set} -height 0 -state disabled
    pack .n.scrolled -expand 1 -fill both
    frame .n.scrolled.buttons
    .n.scrolled window create end -window .n.scrolled.buttons
    .n.scrolled configure -background [.n.scrolled.buttons cget -background]

    pack .n -side top -expand 1 -fill both
    pack .b -side top -expand 0 -fill x

    global has_tray
    if {$has_tray} {
        wm protocol . WM_DELETE_WINDOW hide_main
        bind . <Escape> hide_main
        hide_main
    } else {
        wm protocol . WM_DELETE_WINDOW hide_main
        bind . <Escape> hide_main
        hide_main
    }

    global icon_photo_name
    wm iconphoto . -default $icon_photo_name
    wm geometry . 250x250

    bind . <Control-f> [list focus .b.search]
    bind . <Control-q> [list focus .b.quit]
    bind . <Control-n> [list focus .b.new]
}

proc handle_global_search_pattern {_n _i write} {
    if {$write ne "write"} {
        return
    }

    global next_note_id notes global_search_pattern
    for {set i 0} {$i < $next_note_id} {incr i} {
        if {[catch { set content $notes($i,text) }] != 0} {
            continue
        }
        set btn [note_button_tk $i]

        if {$global_search_pattern eq "" || [string first $global_search_pattern $content] >= 0} {
            set notes($i,visible) 1
        } else {
            set notes($i,visible) 0
        }
    }
    ui_update_notes
}

proc ui_update_notes {} {
    global next_note_id notes
    for {set i 0} {$i < $next_note_id} {incr i} {
        set bname [note_button_tk $i]
        if {[winfo exists $bname] && [winfo ismapped $bname] ne ""} {
            pack forget [note_button_tk $i]
        }
    }
    for {set i 0} {$i < $next_note_id} {incr i} {
        if {[catch { set visible $notes($i,visible) }] != 0} {
            continue
        }
        if {$visible} {
            if {![winfo exists [note_button_tk $i]]} {
                button [note_button_tk $i] -command [list show_note $i] -text $notes($i,title) -padx 0 -pady 0
            }
            pack [note_button_tk $i] -anchor w
        }
    }
}

main
