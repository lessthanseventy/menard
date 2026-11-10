import { expect, test } from 'claude-code/testing'

import { menardSaid } from './said'

const EDIT = 'mcp__plugin_menard_menard__edit'

test('a menard call is named by what it did', async () => {
  const reply = [{ type: 'text', text: '{"did":"edit cart.ex: 2 replacements","changed":[]}' }]
  expect(menardSaid({ tool: EDIT, input: { edits: [{ file: 'lib/cart.ex' }] }, output: reply })).toBe('edit cart.ex: 2 replacements')
  expect(menardSaid({ tool: EDIT, input: { edits: [{ file: 'lib/cart.ex', old: 'a', new: 'b' }] } })).toBe('edit lib/cart.ex')
  const shell = { command: "cd x && ~/projects/menard/bin/menard edit - <<'EOF'\n…" }
  expect(menardSaid({ tool: 'Bash', input: shell, output: { stdout: '{"did":"edit a.ts: 1 replacement"}' } })).toBe('edit a.ts: 1 replacement')
  expect(menardSaid({ tool: 'mcp__plugin_menard_menard__run', input: { verb: 'test' }, output: '{"ok":false,"failures":[]}' })).toBe('run test: failed')
  // a run's flags and files are a list
  expect(menardSaid({ tool: 'mcp__plugin_menard_menard__run', input: { verb: 'credo', args: ['--changed', 'lib/a.ex'] }, output: '{"ok":true}' })).toBe('run credo --changed lib/a.ex: ok')
  // from the shell: the verb and what follows it, not the command's description
  const run = { command: 'cd x && bin/menard --frozen run test test/a_test.exs 2>&1', description: 'Run the tests' }
  expect(menardSaid({ tool: 'Bash', input: run, output: { stdout: '{"ok":true,"tests":3}' } })).toBe('run test test/a_test.exs: ok')
  // a command that only mentions menard is not a call
  const commit = { command: `c.sh "plugin: a menard call's line names its arguments"`, description: 'Commit the fix' }
  expect(menardSaid({ tool: 'Bash', input: commit, output: {} })).toBeNull()
  expect(menardSaid({ tool: 'Bash', input: { command: 'ls' }, output: {} })).toBeNull()
  expect(menardSaid({ tool: 'Read', input: { file_path: 'menard edit' } })).toBeNull()
})

const row = (component: 'ToolUse' | 'ToolResult', props: object) =>
  ({ plugin: 'menard', component, surface: 'terminal', requestId: 't1', props: { tool_use_id: 't1', isErrored: false, ...props } }) as never

test('a menard call is its line, and a click opens the call as it was made', async ($, on) => {
  on('ui.render', (_, e) => ({ type: 'Text', props: {}, children: [`the ${(e as { component: string }).component} as drawn`] }) as never)
  const call = { tool: 'Bash', input: { command: "bin/menard edit - <<'EOF'\nlib/a.ex\n…" }, isRunning: false, isInterrupted: false, output: { stdout: '{"did":"edit a.ex: 1 replacement"}' } }
  const use = await $.ui.mount(row('ToolUse', call))
  expect(await use.find({ text: /edit a\.ex: 1 replacement/ })).toBeDefined()
  expect(await use.find({ text: /the ToolUse as drawn/ })).toBeUndefined()
  const result = await $.ui.mount(row('ToolResult', { tool: 'Bash', output: call.output }))
  expect(await result.find({ text: /the ToolResult as drawn/ })).toBeUndefined()

  await use.press({ key: 'menard-t1' } as never)
  expect(await use.find({ text: /the ToolUse as drawn/ })).toBeDefined()
  expect(await result.find({ text: /the ToolResult as drawn/ })).toBeDefined()
})

test('a call that is not menard is drawn as it was', async ($, on) => {
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['ls as drawn'] }) as never)
  const use = await $.ui.mount(row('ToolUse', { tool: 'Bash', input: { command: 'ls' }, isRunning: false, isInterrupted: false }))
  expect(await use.find({ text: /ls as drawn/ })).toBeDefined()
})

const group = (calls: unknown[], isCallsOnly: boolean) =>
  ({ plugin: 'menard', component: 'ToolGroup', surface: 'terminal', props: { calls, isActive: false, isExpanded: false, isCallsOnly } }) as never

test('a folded run of menard calls is a line for each, in place of the count', async ($, on) => {
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['Called plugin:menard:menard 2 times'] }) as never)
  const calls = [
    { tool: EDIT, input: { edits: [{ file: 'lib/cart.ex' }] }, output: '{"did":"edit cart.ex: 2 replacements"}' },
    { tool: 'mcp__plugin_menard_menard__run', input: { verb: 'test' }, output: '{"ok":true}' },
  ]
  const ui = await $.ui.mount(group(calls, true))
  expect(await ui.find({ text: /edit cart\.ex: 2 replacements/ })).toBeDefined()
  expect(await ui.find({ text: /run test: ok/ })).toBeDefined()
  expect(await ui.find({ text: /Called plugin/ })).toBeUndefined()
})

test('among other calls the count stays, and menard is named under it', async ($, on) => {
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['Read 1 file, called menard'] }) as never)
  const calls = [
    { tool: 'Read', input: { file_path: 'a.ex' } },
    { tool: 'mcp__plugin_menard_menard__run', input: { verb: 'check' }, output: '{"ok":false}' },
  ]
  const ui = await $.ui.mount(group(calls, false))
  expect(await ui.find({ text: /Read 1 file/ })).toBeDefined()
  expect(await ui.find({ text: /run check: failed/ })).toBeDefined()
})
