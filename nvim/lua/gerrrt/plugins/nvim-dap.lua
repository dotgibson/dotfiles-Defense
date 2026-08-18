-- ================================================================================================
-- TITLE : nvim-dap (+ nvim-dap-python) | debugging
-- LINKS :
--   > dap        : https://github.com/mfussenegger/nvim-dap
--   > dap-python : https://github.com/mfussenegger/nvim-dap-python
-- ABOUT : Breakpoints, stepping, and variable inspection via the Debug Adapter Protocol. Python is
--         wired through nvim-dap-python (debugpy); Rust already had adapter config waiting in
--         plugins/rustaceanvim.lua, which was DEAD CODE until now — rustaceanvim's `dap` block
--         needs nvim-dap present to do anything, and nvim-dap was never installed. It works now.
--
-- NO dap-ui, ON PURPOSE : nvim-dap-ui is the heavy part of the usual stack (it pulls nvim-nio, owns
--         a multi-window layout, and hooks session events to build/tear it down). nvim-dap ships
--         `dap.repl` and `dap.ui.widgets` — a scopes/frames/expression viewer — which covers
--         inspection without the extra plugin and window management. <leader>dw / <leader>ds below
--         open those. If you later want the full panel layout, add rcarriga/nvim-dap-ui and its
--         nvim-nio dependency and hook them in `config` here.
--
-- LAZY  : keys + cmd ONLY. Nothing about debugging is needed until you actually start a session, so
--         this costs exactly zero at startup and zero on file open — unlike the LSP/lint stack it
--         does not even load on `User FilePost`. Note <leader>db must load the plugin to set a
--         breakpoint, which is why the keys are declared here rather than in config/keymaps.lua.
-- ================================================================================================

-- Resolve the interpreter that has debugpy available, most-preferred first. This is the ADAPTER's
-- python, not the debuggee's — nvim-dap-python resolves the program being debugged separately
-- (VIRTUAL_ENV / CONDA_PREFIX / a .venv near the file), so a project venv still wins for your code.
--
-- Mason's debugpy is preferred WHEN PRESENT because it is already installed and works offline —
-- but it is deliberately NOT in mason-tool-installer's ensure_installed. Mason's PyPI installer
-- always runs `python -m venv` then pip, which needs python3-venv on Debian/Kali and py3-pip on
-- Alpine; listing it would fail the install pass on every startup on those hosts. `uv` is therefore
-- the portable path (and is what Core already assumes for the Astral stack — ty/ruff are
-- `uv tool install`ed), with bare python3 as the last resort. Install Mason's copy by hand with
-- `:MasonInstall debugpy` on a box where you want it; this function picks it up automatically.
local function debugpy_python()
	local mason = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python"
	if vim.fn.has("win32") == 1 then
		mason = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/Scripts/python.exe"
	end
	if vim.fn.executable(mason) == 1 then
		return mason
	end
	if vim.fn.executable("uv") == 1 then
		return "uv" -- dap-python knows this provider and fetches debugpy on demand
	end
	return "python3" -- last resort; works if debugpy is installed into the ambient interpreter
end

return {
	"mfussenegger/nvim-dap",
	dependencies = {
		{
			"mfussenegger/nvim-dap-python",
			-- Configured from the parent's `config` below so ordering is explicit and a failure to
			-- set up Python debugging can never prevent nvim-dap itself from loading.
			lazy = true,
		},
	},
	cmd = {
		"DapContinue",
		"DapToggleBreakpoint",
		"DapStepOver",
		"DapStepInto",
		"DapStepOut",
		"DapTerminate",
		"DapNew",
	},
	keys = {
		{
			"<leader>db",
			function()
				require("dap").toggle_breakpoint()
			end,
			desc = "Breakpoint: toggle",
		},
		{
			"<leader>dB",
			function()
				vim.ui.input({ prompt = "Breakpoint condition: " }, function(cond)
					if cond and cond ~= "" then
						require("dap").set_breakpoint(cond)
					end
				end)
			end,
			desc = "Breakpoint: conditional",
		},
		{
			"<leader>dc",
			function()
				require("dap").continue()
			end,
			desc = "Continue / start session",
		},
		{
			"<leader>di",
			function()
				require("dap").step_into()
			end,
			desc = "Step into",
		},
		{
			"<leader>do",
			function()
				require("dap").step_over()
			end,
			desc = "Step over",
		},
		{
			"<leader>dO",
			function()
				require("dap").step_out()
			end,
			desc = "Step out",
		},
		{
			"<leader>dr",
			function()
				require("dap").repl.toggle()
			end,
			desc = "REPL toggle",
		},
		{
			"<leader>dl",
			function()
				require("dap").run_last()
			end,
			desc = "Run last configuration",
		},
		{
			"<leader>dt",
			function()
				require("dap").terminate()
			end,
			desc = "Terminate session",
		},
		{
			-- The dap-ui substitute: a floating, focusable scopes/variables viewer.
			"<leader>ds",
			function()
				local w = require("dap.ui.widgets")
				w.centered_float(w.scopes)
			end,
			desc = "Scopes (variables)",
		},
		{
			"<leader>df",
			function()
				local w = require("dap.ui.widgets")
				w.centered_float(w.frames)
			end,
			desc = "Frames (call stack)",
		},
		{
			-- Inspect the expression under the cursor / visual selection.
			"<leader>dw",
			function()
				require("dap.ui.widgets").hover()
			end,
			mode = { "n", "v" },
			desc = "Hover value under cursor",
		},
		{
			-- Python-specific: debug just the test function under the cursor.
			"<leader>dm",
			function()
				local ok, dp = pcall(require, "dap-python")
				if ok then
					dp.test_method()
				else
					vim.notify("nvim-dap-python is not available", vim.log.levels.WARN, { title = "DAP" })
				end
			end,
			ft = "python",
			desc = "Debug test method (python)",
		},
	},
	config = function()
		local dap = require("dap")

		-- Breakpoint signs, matching the diagnostic glyph vocabulary used by utils/diagnostics.lua,
		-- lualine and bufferline so every surface in this config agrees. Escapes rather than raw
		-- glyphs for the same reason as everywhere else — private-use codepoints get stripped in
		-- transit. Highlight groups are palette-driven via ui-highlights.lua's DapBreakpoint*.
		vim.fn.sign_define("DapBreakpoint", {
			text = "\u{f111}", -- f111 nf-fa-circle
			texthl = "DapBreakpoint",
			numhl = "",
		})
		vim.fn.sign_define("DapBreakpointCondition", {
			text = "\u{f059}", -- f059 nf-fa-question_circle
			texthl = "DapBreakpointCondition",
			numhl = "",
		})
		vim.fn.sign_define("DapStopped", {
			text = "\u{f0da}", -- f0da nf-fa-caret_right
			texthl = "DapStopped",
			linehl = "DapStoppedLine",
			numhl = "",
		})
		vim.fn.sign_define("DapLogPoint", {
			text = "\u{f05a}", -- f05a nf-fa-info_circle
			texthl = "DapLogPoint",
			numhl = "",
		})

		-- Python. pcall'd so a box without nvim-dap-python (or without any debugpy provider) still
		-- gets a working nvim-dap for every other language rather than an error on first <leader>dc.
		local ok, dap_python = pcall(require, "dap-python")
		if ok then
			pcall(dap_python.setup, debugpy_python())
		end

		-- Close the REPL automatically when a session ends, so a stale REPL split doesn't linger.
		dap.listeners.before.event_terminated["gerrrt_dap"] = function()
			pcall(function()
				dap.repl.close()
			end)
		end
		dap.listeners.before.event_exited["gerrrt_dap"] = function()
			pcall(function()
				dap.repl.close()
			end)
		end
	end,
}
