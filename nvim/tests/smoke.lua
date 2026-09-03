-- Smoke test for the F4/F5/F6 floaterm + code-runner keymaps
-- (nvim/lua/config/keymaps.lua).
--
-- Runs against whatever is actually deployed and installed (~/.config/nvim
-- + ~/.local/share/nvim/lazy), so it catches breaking changes shipped by a
-- plugin update — not just bugs in this repo's own Lua. Run this after any
-- `:Lazy sync`/`:Lazy update` (or `./install.sh --update`), before trusting
-- the keymaps again:
--
--   nvim --headless -c "luafile nvim/tests/smoke.lua"
--
-- Exits 0 with "All checks passed." if everything is fine, or exits 1 and
-- prints [FAIL] lines naming what broke.

local failures = {}

local function check(name, ok, detail)
  if ok then
    print('[PASS] ' .. name)
  else
    print('[FAIL] ' .. name .. (detail and (' -- ' .. detail) or ''))
    table.insert(failures, name)
  end
end

-- 1. The keymaps themselves are still registered.
local expected = {
  { mode = 'n', lhs = '<F4>' },
  { mode = 'n', lhs = '<S-F4>' },
  { mode = 'n', lhs = '<S-C-F4>' },
  { mode = 'n', lhs = '<F5>',     desc_contains = 'Run file' },
  { mode = 'n', lhs = '<S-F5>',   desc_contains = 'Run file' },
  { mode = 'n', lhs = '<S-C-F5>', desc_contains = 'Run file' },
  { mode = 'n', lhs = '<F6>',     desc_contains = 'interactive' },
  { mode = 'n', lhs = '<S-F6>',   desc_contains = 'interactive' },
  { mode = 'n', lhs = '<S-C-F6>', desc_contains = 'interactive' },
}
for _, m in ipairs(expected) do
  local map = vim.fn.maparg(m.lhs, m.mode, false, true)
  local exists = map and map.lhs ~= nil and map.lhs ~= ''
  check(string.format('%s is mapped (mode %s)', m.lhs, m.mode), exists)
  if exists and m.desc_contains then
    check(
      string.format('%s description mentions "%s"', m.lhs, m.desc_contains),
      map.desc ~= nil and map.desc:find(m.desc_contains, 1, true) ~= nil,
      map.desc
    )
  end
end

-- 2. RunCode actually runs code end-to-end for all three layouts (vsplit,
--    split, float) -- no argument-validation error from vim-floaterm (this
--    is what broke when --autoinsert=false/--autoclose=0, and separately
--    --wintype=floating, stopped being accepted after a plugin update), and
--    the program's output really reaches the floaterm buffer. RunCode always
--    reuses/kills the single 'runterm' floaterm, so it's safe to check right
--    after each call.
local function output_reached_floaterm(marker)
  return vim.wait(3000, function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].filetype == 'floaterm' then
        for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
          if line:find(marker, 1, true) then return true end
        end
      end
    end
    return false
  end, 100)
end

local tmp = vim.fn.tempname() .. '.py'
vim.cmd.edit(tmp)

for _, layout in ipairs({ 'v', 'h', 'f' }) do
  local marker = 'smoke-test-ok-' .. layout
  vim.fn.writefile({ string.format('print("%s")', marker) }, tmp)
  vim.cmd('edit!')

  local ok, call_err = pcall(RunCode, layout, false)
  check(string.format("RunCode('%s', false) does not error", layout), ok, ok and nil or tostring(call_err))

  if ok then
    check(
      string.format("RunCode('%s', false) output reached the floaterm", layout),
      output_reached_floaterm(marker)
    )
  end
end

pcall(vim.cmd, 'FloatermKill!')

-- 3. Ctrl+Shift+F4's floating floaterm toggle (a separate code path from
--    RunCode/ft_layouts -- shares only the --wintype=float flag, which is
--    exactly what broke here).
local ok_f4, err_f4 = pcall(toggleFT, 'smoke_test_f4_float',
  '--title= --titleposition=left --position=center --wintype=float --height=0.9 --width=0.9')
check('toggleFT floating (Ctrl+Shift+F4) does not error', ok_f4, ok_f4 and nil or tostring(err_f4))
pcall(vim.cmd, 'FloatermKill! smoke_test_f4_float')

-- Switch away before deleting the tmp file, otherwise quitting the buffer
-- whose file just vanished triggers an E211 hit-enter prompt that would
-- hang headless mode forever.
vim.cmd('enew!')
vim.fn.delete(tmp)

print('')
if #failures > 0 then
  print(string.format('%d check(s) failed.', #failures))
  vim.cmd('cquit! 1')
else
  print('All checks passed.')
  vim.cmd('quitall!')
end
