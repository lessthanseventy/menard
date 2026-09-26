Last: `console/lib/console/cockpit.ex` has grown to about 1,800 lines, and it is time to split it.
Pull its parts out into modules of their own, each one coherent (the mouse and wheel handling, the
context menus, lazygit, the effects, or whatever seams you find are real), so that cockpit.ex keeps
the GenServer and what ties the parts together. Behaviour stays exactly the same: every public
function of `Console.Cockpit` keeps working as it does now, and the console's tests stay green.
