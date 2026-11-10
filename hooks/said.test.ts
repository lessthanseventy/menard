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
  expect(menardSaid({ tool: 'Bash', input: { command: 'ls' }, output: {} })).toBeNull()
  expect(menardSaid({ tool: 'Read', input: { file_path: 'menard edit' } })).toBeNull()
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
