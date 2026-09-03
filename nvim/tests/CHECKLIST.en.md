# Post-update checklist

*[Versão em português](CHECKLIST.pt-br.md)*

Run this after any `:Lazy sync`/`:Lazy update`, `./install.sh --update`, or a
Neovim upgrade itself — before assuming the keymaps still work. Every item
here comes from a real regression caused by a plugin update (mostly
`vim-floaterm`); see `git log -- nvim/lua/config/keymaps.lua` for the history
behind each one.

## 1. Automated (run this first)

```bash
nvim/tests/smoke.sh
```

Checks: F4–F6 keymaps are registered, `RunCode` runs without error and its
output actually reaches the floaterm in all three layouts (vsplit/split/
float), and the floating `toggleFT` doesn't raise an argument error. If this
fails, it already points at which `[FAIL]` to investigate before moving on to
the manual checks below.

Not covered: anything that depends on a real UI being attached (redraw,
`getchar()`, Terminal-mode) — headless doesn't reproduce that class of bug
reliably (learned this the hard way). That's what the manual checklist is
for.

## 2. Manual — Floaterm (F4)

Open any file and test across different terminals if you can (local Konsole,
and whatever other session type you use):

- [ ] `F4` → opens a vertical vsplit terminal
- [ ] `F4` again → closes (toggle)
- [ ] `Shift+F4` → opens a horizontal split terminal
- [ ] `Shift+F4` again → closes
- [ ] `Ctrl+Shift+F4` → opens a floating terminal (taking up most of the screen)
- [ ] `Ctrl+Shift+F4` again → closes
- [ ] Inside the terminal (Terminal-mode), the same shortcuts also close it
      (not just from outside)

If any of these fail to open/close: suspect `--wintype=` or `--autoinsert=`/
`--autoclose=` being passed a value the current `vim-floaterm` no longer
accepts — run `:messages` to check for an `Argument Error`.

## 3. Manual — Run code, non-interactive (F5)

Use `nvim/tests/hello.c` (or a simple `.py`) to rule out issues specific to an
external library (e.g. `-lgmp`):

- [ ] `F5` → compiles/runs in a vsplit, shows the output (not blank/black)
- [ ] `Shift+F5` → same, horizontal split
- [ ] `Ctrl+Shift+F5` → same, floating window
- [ ] Once `[Process exited N]` shows up, pressing **any key** closes the
      floaterm on its own and returns to the code
- [ ] If you switch to another window before pressing a key, that key is NOT
      "stolen" (the floaterm stays open until you go back and press something)
- [ ] Also test with a program that fails to compile — the error should
      show up normally (not a blank screen)

## 4. Manual — Run code, interactive (F6)

Use a simple `.py`:

- [ ] `F6` → compiles/runs and drops straight into Python's `>>>` prompt
      (cursor already in Terminal-mode, ready to type — like pressing `i`)
- [ ] `Shift+F6` / `Ctrl+Shift+F6` → same for the other layouts
- [ ] Typing at the prompt works normally (not stuck in Normal mode)

If you have to press `i` manually to reach the prompt: do **not** add an
explicit `--autoinsert=smart` to the `FloatermNew` call — passing that flag
did not work in practice (tested live). Leaving it unset, so `vim-floaterm`
falls back to its own global default (`'smart'`), is what actually works.

## 5. Manual — `:checkhealth` / `:LazyHealth`

- [ ] `dap` → the `gdb` adapter shows `OK is executable`, no
      `Missing required command property` error
- [ ] `lazyvim` → `lazygit` found
- [ ] `grug-far` → `ast-grep` found
- [ ] `vim.provider` → Node.js provider shows the `neovim` npm package installed
- [ ] `which-key` → no duplicate on `<leader>w` (it should be `<leader>W` for
      save; `<leader>w` is LazyVim's windows group)

## 6. Manual — Dark/light theme

- [ ] Opening Neovim normally → theme matches the current system theme
      (KDE light → `wbs`; KDE dark → `catppuccin-mocha`)
- [ ] `<leader>tt` or `:ToggleTheme` → toggles between the two

## If something breaks

1. Check `git log --oneline -- nvim/lua/config/keymaps.lua` for similar
   commits (a floaterm flag change has already happened twice).
2. `:messages` right after the shortcut fails — `vim-floaterm`'s own error
   messages show up there, not as a Lua error.
3. `nvim --headless` with `nvim/tests/smoke.sh` only rules out pure logic
   bugs — rendering bugs (black screen, cursor not moving, etc.) only show
   up with a real UI attached; don't waste time trying to debug those via
   `--headless`.
