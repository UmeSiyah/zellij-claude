# Prints one JSON line per live Claude Code session found in ~/.claude/sessions.
# Linux only: reads process info from /proc. Never deletes anything: the
# session files belong to Claude Code, and a dead PID here may be a live
# session on another machine sharing the same home.

let dir = ($env.HOME | path join .claude sessions)
if not ($dir | path exists) { exit 0 }

# ZELLIJ_* variables of a process, as a record. Empty when unreadable.
def zellij_env [pid: int] {
    try {
        open --raw $"/proc/($pid)/environ"
        | split row (char nul)
        | where $it starts-with 'ZELLIJ_'
        | parse '{key}={value}'
        | reduce -f {} {|it, acc| $acc | upsert $it.key $it.value }
    } catch { {} }
}

def parent_pid [pid: int] {
    try {
        open --raw $"/proc/($pid)/status"
        | lines
        | where $it starts-with 'PPid:'
        | first
        | split row -r '\s+'
        | get 1
        | into int
    } catch { 1 }
}

# Walks up the process tree until a process carries ZELLIJ_SESSION_NAME.
def find_zellij_env [pid: int] {
    mut p = $pid
    mut z = (zellij_env $p)
    for _ in 1..8 {
        if ($z.ZELLIJ_SESSION_NAME? | is-not-empty) { break }
        $p = (parent_pid $p)
        if $p <= 1 { break }
        $z = (zellij_env $p)
    }
    $z
}

glob ($dir | path join '*.json')
| each {|f|
    let pid = try { $f | path parse | get stem | into int } catch { null }
    let session = try { open $f } catch { null }
    if $pid == null or $session == null or not ($"/proc/($pid)" | path exists) {
        return null
    }
    let status_file = ($dir | path join $"($pid).status")
    let status = if ($status_file | path exists) {
        open --raw $status_file | str trim
    } else {
        $session.status? | default 'unknown'
    }
    let z = (find_zellij_env $pid)
    let row = {
        pid: $pid
        cwd: ($session.cwd? | default '')
        status: $status
        zellij_session: ($z.ZELLIJ_SESSION_NAME? | default '')
    }
    if ($z.ZELLIJ_PANE_ID? | is-not-empty) {
        $row | insert zellij_pane_id ($z.ZELLIJ_PANE_ID | into int)
    } else {
        $row
    }
}
| compact
| each { to json --raw }
| str join (char nl)
