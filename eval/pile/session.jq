reduce inputs as $l (
  {ids: {}, models: {}, first: null, last: null, usage: {input:0, output:0, cache_read:0, cache_write:0}, turns: 0,
   bash: 0, edit: 0, read: 0, menard_cli: 0, menard_mcp: 0, python: 0, filtered: 0, denied: 0, uses: {}};
  if $l.type == "assistant" then
    .models[$l.message.model // "?"] += 1
    | .first = (.first // $l.timestamp) | .last = ($l.timestamp // .last)
    | (($l.message.usage // {}) as $u
       | .usage.input += ($u.input_tokens // 0) | .usage.output += ($u.output_tokens // 0)
       | .usage.cache_read += ($u.cache_read_input_tokens // 0) | .usage.cache_write += ($u.cache_creation_input_tokens // 0))
    | .turns += 1
    | reduce (($l.message.content // []) | if type=="array" then .[] else empty end) as $c (.;
        if $c.type == "text" then
          reduce ($c.text | [scan("session_01[A-Za-z0-9]+")][]) as $id (.; .ids[$id] += 1)
        elif $c.type == "tool_use" then
          .uses[$c.id] = $c.name
          | if $c.name == "Bash" then
              .bash += 1
              | (($c.input.command // "") as $cmd
                 | if ($cmd | test("(^|[;&|(\n`]|\\$\\(|\\b(do|then|else)\\s)\\s*(\\S*/)?python3?(\\s|$)")) then .python += 1 else . end
                 | if ($cmd | test("menard ")) then .menard_cli += 1 else . end
                 | if ($cmd | test("menard [^|\n]*\\|\\s*(jq|head|tail|cut|grep|sed|awk)\\b")) then .filtered += 1 else . end)
            elif ($c.name == "Edit" or $c.name == "Write" or $c.name == "MultiEdit") then .edit += 1
            elif $c.name == "Read" then .read += 1
            elif ($c.name | startswith("mcp__plugin_menard_menard__")) then .menard_mcp += 1
            else . end
        else . end)
  elif $l.type == "user" then
    reduce (($l.message.content // []) | if type=="array" then .[] else empty end | select(.type=="tool_result")) as $r (.;
        (($r.content | if type=="string" then . elif type=="array" then (map(.text // "") | join("\n")) else "" end) | .[0:40]) as $txt
        | if ($txt | startswith("PreToolUse:")) then .denied += 1 else . end)
    | reduce (($l.message.content // []) | if type=="array" then .[] else empty end | select(.type=="text")) as $c (.;
        reduce ($c.text | [scan("session_01[A-Za-z0-9]+")][]) as $id (.; .ids[$id] += 1))
    | (if ($l.message.content | type) == "string" then reduce ($l.message.content | [scan("session_01[A-Za-z0-9]+")][]) as $id (.; .ids[$id] += 1) else . end)
  elif $l.type == "attachment" and ($l.attachment.type // "") == "remote_session_change" then
    reduce (($l.attachment.url // "") | [scan("session_01[A-Za-z0-9]+")][]) as $id (.; .ids[$id] += 1000)
  else . end
) | del(.uses) | . + {file: $f, id: ((.ids | to_entries | sort_by(-.value) | .[0].key) // null), model: ((.models | to_entries | sort_by(-.value) | .[0].key) // null)}
