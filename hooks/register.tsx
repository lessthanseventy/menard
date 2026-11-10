import type { Register } from 'claude-code'

import { callText, menardSaid } from './said'
import type { Call } from './said'

type Ui = { ui: { resolve: (e: never) => Record<string, any>; invalidate: (event: string) => void } }

// One call's line, and under it, once clicked, the call as it was made and answered.
function row($: Ui, e: unknown, opened: Set<string>, id: string, call: Call, said: string, lead: string) {
  const { Box, Text, Button } = $.ui.resolve(e as never)
  const isOpen = opened.has(id)
  const toggle = () => {
    if (!opened.delete(id)) opened.add(id)
    $.ui.invalidate('ui.render')
  }
  return (
    <Box flexDirection="column" key={`row-${id}`}>
      <Button plain key={`menard-${id}`} onPress={toggle}>
        {lead}
        <Text color="remember">menard</Text> {said}
        <Text dimColor>{isOpen ? '  ▾' : '  ▸'}</Text>
      </Button>
      {isOpen ? callText(call).map(line => <Text dimColor wrap="truncate-end">{`    ${line}`}</Text>) : null}
    </Box>
  )
}

export const register: Register = on => {
  // the calls a click opened, and the menard calls a row was drawn for (a result's own props do
  // not say what a shell command ran)
  const opened = new Set<string>()
  const ours = new Set<string>()
  const replies = new Map<string, unknown>()
  // VS Code and mobile draw a call their own way
  const draws = (surface: string) => surface === 'terminal' || surface === 'desktop'

  // A menard call is a line saying what it did, in place of the call as it was typed (an edit's
  // heredoc is a page) and its JSON reply. A click on the line opens that one call, as it was
  // made and answered, and folds it again. A run of calls Claude Code folds into one count
  // can only be unfolded whole, so an opened call is drawn here, the same in a run as alone.
  on('ui.render', { component: 'ToolUse' }, async ($, e, next) => {
    if (!draws(e.surface) || e.props.isExpanded) return next(e)
    const said = menardSaid(e.props)
    if (said === null) return next(e)
    ours.add(e.props.tool_use_id)
    const state = e.props.isRunning ? ' …' : e.props.isErrored || e.props.isInterrupted ? ' (failed)' : ''
    const call = { ...e.props, output: e.props.output ?? replies.get(e.props.tool_use_id) }
    return row($, e, opened, e.props.tool_use_id, call, `${said}${state}`, '')
  })

  on('ui.render', { component: 'ToolResult' }, async ($, e, next) => {
    if (!draws(e.surface) || e.props.isExpanded || !ours.has(e.props.tool_use_id)) return next(e)
    replies.set(e.props.tool_use_id, e.props.output)
    const { Box } = $.ui.resolve(e)
    return <Box />
  })

  on('ui.render', { component: 'ToolGroup' }, async ($, e, next) => {
    if (!draws(e.surface) || e.props.isExpanded) return next(e)
    const calls = e.props.calls
      .map((call, index) => ({ call, id: call.tool_use_id ?? `group-${index}`, said: menardSaid(call) }))
      .filter((one): one is { call: (typeof e.props.calls)[number]; id: string; said: string } => one.said !== null)
    if (calls.length === 0) return next(e)
    const { Box } = $.ui.resolve(e)
    const isAllSaid = calls.length === e.props.calls.length && e.props.isCallsOnly === true
    return (
      <Box flexDirection="column">
        {isAllSaid ? null : await next(e)}
        {calls.map(({ call, id, said }) => row($, e, opened, id, call, said, isAllSaid ? '' : '  ⎿  '))}
      </Box>
    )
  })
}
