import type { Register } from 'claude-code'

import { menardSaid } from './said'

export const register: Register = on => {
  // A folded run of calls says only how many there were ("Called plugin:menard:menard 2 times"):
  // menard's are named by what each did.
  on('ui.render', { component: 'ToolGroup' }, async ($, e, next) => {
    // VS Code and mobile draw the group their own way
    if ((e.surface !== 'terminal' && e.surface !== 'desktop') || e.props.isExpanded) return next(e)
    const said = e.props.calls.map(menardSaid).filter((line): line is string => line !== null)
    if (said.length === 0) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const isAllSaid = said.length === e.props.calls.length && e.props.isCallsOnly === true
    return (
      <Box flexDirection="column">
        {isAllSaid ? null : await next(e)}
        {said.map(line => (
          <Text dimColor wrap="truncate-end">
            {isAllSaid ? '  ' : '  ⎿  '}
            <Text color="remember">menard</Text> {line}
          </Text>
        ))}
      </Box>
    )
  })
}
