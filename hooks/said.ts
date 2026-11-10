export type Call = { tool: string; input: unknown; output?: unknown }

const MENARD_TOOL = /^mcp__plugin_menard_menard__(\w+)$/
// menard's verbs (`menard help`), and a command that starts with the call (after a `cd X &&`):
// one that only mentions menard, in a commit message's words or a quoted string, is not a call,
// and neither is one that ran something else first
export const VERBS = 'edit rename find outline clause stmt block attr directive module write deps run map where version'
const MENARD_SHELL = new RegExp(`^\\s*(?:cd\\s+\\S+\\s*&&\\s*)?(?:\\S*/)?menard\\s+(?:--frozen\\s+)?(${VERBS.replaceAll(' ', '|')})\\b([^\\n;&|<>]*)`)
const MAX_SAID = 100

// What a menard call did, in menard's own words: a write's reply carries `did`, a run's `ok`.
// Before the reply, and for a read, it is the verb and what it was pointed at. null: not menard's.
export const menardSaid = ({ tool, input, output }: Call): string | null => {
  const fields = (input ?? {}) as Record<string, unknown>
  const command = tool === 'Bash' && typeof fields.command === 'string' ? fields.command : ''
  const shell = MENARD_SHELL.exec(command)
  const verb = MENARD_TOOL.exec(tool)?.[1] ?? shell?.[1]
  if (!verb) return null
  // the reply is JSON, itself quoted inside the tool's own result
  const reply = (typeof output === 'string' ? output : JSON.stringify(output ?? '')).replace(/\\+"/g, '"')
  const did = /"did":"([^"]*)"/.exec(reply)?.[1]
  if (did) return did.slice(0, MAX_SAID)
  const edits = Array.isArray(fields.edits) ? (fields.edits as { file?: unknown }[]).map(edit => edit.file) : []
  // from the shell, what follows the verb on its line: the command's other fields describe it
  // (less a redirect's descriptor, `2>&1`)
  const given = shell ? shell[2]!.replace(/\s\d$/, '').trim().split(/\s+/) : [...edits, ...Object.values(fields).flat()]
  const targets = given.filter(
    (v): v is string => typeof v === 'string' && v.length <= 60 && !v.includes('\n'),
  )
  const ok = /"ok":(true|false)/.exec(reply)?.[1]
  const said = [verb, ...new Set(targets)].join(' ').slice(0, MAX_SAID)
  return ok === undefined ? said : `${said}: ${ok === 'true' ? 'ok' : 'failed'}`
}

const MAX_LINES = 30

const lines = (text: string): string[] => {
  const all = text.replace(/\n+$/, '').split('\n')
  return all.length > MAX_LINES ? [...all.slice(0, MAX_LINES), `… +${all.length - MAX_LINES} lines`] : all
}

// a reply as its text: a shell's stdout, an MCP tool's text blocks, else the value as JSON
const replyText = (output: unknown): string => {
  if (typeof output === 'string') return output
  if (Array.isArray(output)) return output.map(block => (typeof block?.text === 'string' ? block.text : JSON.stringify(block))).join('\n')
  const shell = output as { stdout?: unknown; stderr?: unknown } | null
  if (typeof shell?.stdout === 'string') return [shell.stdout, typeof shell.stderr === 'string' ? shell.stderr : ''].filter(Boolean).join('\n')
  return output === undefined ? '' : JSON.stringify(output, null, 2)
}

// A call as it was made and answered, for a line that was clicked open: the command or the
// tool's arguments, then the reply, each cut to a screen's worth.
export const callText = ({ input, output }: Call): string[] => {
  const fields = (input ?? {}) as Record<string, unknown>
  const made = typeof fields.command === 'string' ? `$ ${fields.command}` : JSON.stringify(input ?? {}, null, 2)
  const reply = replyText(output)
  return reply === '' ? lines(made) : [...lines(made), ...lines(reply)]
}
