#!/usr/bin/env bash
# omarchy-todo helper script
cmd="$1"

if [ "$cmd" = "copy" ]; then
    printf "%s" "$2" | wl-copy
    exit 0
fi

if [ "$cmd" = "read" ]; then
    jsonP="$2"
    if [ -f "$jsonP" ]; then
        cat "$jsonP"
    else
        echo "{}"
    fi
    exit 0
fi

if [ "$cmd" = "write" ]; then
    jsonP="$2"
    mdP="$3"
    notes_json="$4"
    tasks_json="$5"
    
    umask 0077
    mkdir -p "$(dirname "$jsonP")"
    
    jq -n -c --argjson n "$notes_json" --argjson t "$tasks_json" '{version: 1, notes: $n, tasks: $t}' > "$jsonP"
    
    jq -r -n --argjson n "$notes_json" --argjson t "$tasks_json" '
    def fmt_human(sec):
        if (sec == null or sec <= 0) then "0s"
        else
            (sec / 3600 | floor) as $h
            | ((sec % 3600) / 60 | floor) as $m
            | (sec % 60) as $s
            | if $h > 0 then "\($h)h" + (if $m > 0 then " \($m)m" else "" end)
              elif $m > 0 then "\($m)m" + (if $s > 0 then " \($s)s" else "" end)
              else "\($s)s" end
        end;

    "# 📋 Tasks & Time Log\n\n" +
    
    (if ($n | length) > 0 then
        "## 📝 Notes & Checklists\n" +
        ($n | map("- [" + (if .done then "x" else " " end) + "] " + .text + " <!-- id:" + .id + " -->\n") | join("")) +
        "\n"
    else "" end) +

    "## 📋 To-Do\n" +
    (
        ($t | map(select(.status == "todo"))) as $todos
        | if ($todos | length) == 0 then "_No tasks_\n"
          else ($todos | map("- [ ] " + .title + " <!-- id:" + .id + " -->\n") | join("")) end
    ) +

    "\n## ⚡ Progress\n" +
    (
        ($t | map(select(.status == "in_progress"))) as $inprogs
        | if ($inprogs | length) == 0 then "_No tasks_\n"
          else ($inprogs | map("- [/] " + .title + " (spent: " + fmt_human(.timeSpentSeconds // 0) + ") <!-- id:" + .id + " -->\n") | join("")) end
    ) +

    "\n## ✅ Done\n" +
    (
        ($t | map(select(.status == "done"))) as $dones
        | if ($dones | length) == 0 then "_No completed tasks_\n"
          else ($dones | map("- [x] " + .title + " (completed in " + fmt_human(.timeSpentSeconds // 0) + ") <!-- id:" + .id + " -->\n") | join("")) end
    )
    ' > "$mdP"
    
    exit 0
fi
