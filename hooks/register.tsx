import type { Register } from 'claude-code'

import { menardSaid } from './said'

export const register: Register = on => {
  // the calls a click opened to what Claude Code draws, and the menard calls a row was drawn for
  // (a result's own props do not say what a shell command ran)
  const opened = new Set<string>()
  const ours = new Set<string>()
  // VS Code and mobile draw a call their own way
  const draws = (surface: string) => surface === 'terminal' || surface === 'desktop'

  // A menard call is a line saying what it did, in place of the call as it was typed (an edit's
  // heredoc is a page) and its JSON reply. A click on the line opens both, and folds them again.
  on('ui.render', { component: 'ToolUse' }, async ($, e, next) => {
    if (!draws(e.surface) || e.props.isExpanded) return next(e)
    const said = menardSaid(e.props)
    if (said === null) return next(e)
    const { Box, Text, Button } = $.ui.resolve(e)
    const id = e.props.tool_use_id
    ours.add(id)
    const isOpen = opened.has(id)
    const toggle = () => {
      if (!opened.delete(id)) opened.add(id)
      $.ui.invalidate('ui.render')
    }
    const state = e.props.isRunning ? ' …' : e.props.isErrored || e.props.isInterrupted ? ' (failed)' : ''
    return (
      <Box flexDirection="column">
        <Button plain key={`menard-${id}`} onPress={toggle}>
          <Text color={e.props.isErrored ? 'error' : 'remember'}>menard</Text> {said}
          {state}
          <Text dimColor>{isOpen ? '  ▾' : '  ▸'}</Text>
        </Button>
        {isOpen ? await next(e) : null}
      </Box>
    )
  })

  on('ui.render', { component: 'ToolResult' }, async ($, e, next) => {
    const id = e.props.tool_use_id
    if (!draws(e.surface) || e.props.isExpanded || !ours.has(id) || opened.has(id)) return next(e)
    const { Box } = $.ui.resolve(e)
    return <Box />
  })

  // A folded run of calls says only how many there were ("Called plugin:menard:menard 2 times"):
  // menard's are named by what each did. A click on one unfolds the run into its rows.
  on('ui.render', { component: 'ToolGroup' }, async ($, e, next) => {
    if (!draws(e.surface) || e.props.isExpanded) return next(e)
    const said = e.props.calls.map(menardSaid).filter((line): line is string => line !== null)
    if (said.length === 0) return next(e)
    const { Box, Text, Button } = $.ui.resolve(e)
    const id = `group-${e.props.calls[0]?.tool_use_id ?? ''}`
    const toggle = () => {
      if (!opened.delete(id)) opened.add(id)
      $.ui.invalidate('ui.render')
    }
    if (opened.has(id)) {
      return (
        <Box flexDirection="column">
          <Button plain dimColor key={`menard-${id}`} onPress={toggle}>
            <Text color="remember">menard</Text> {said.length} call{said.length === 1 ? '' : 's'}  ▾
          </Button>
          {await next({ ...e, props: { ...e.props, isExpanded: true } })}
        </Box>
      )
    }
    const isAllSaid = said.length === e.props.calls.length && e.props.isCallsOnly === true
    return (
      <Box flexDirection="column">
        {isAllSaid ? null : await next(e)}
        {said.map((line, index) => (
          <Button plain dimColor key={`menard-${id}-${index}`} onPress={toggle}>
            {isAllSaid ? '  ' : '  ⎿  '}
            <Text color="remember">menard</Text> {line}
          </Button>
        ))}
      </Box>
    )
  })
}
