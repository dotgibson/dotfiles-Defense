-- ================================================================================================
-- TITLE : nvim-dap (+ dap-ui, virtual-text, mason-nvim-dap)
-- ABOUT : Debug Adapter Protocol — set breakpoints, step through code, inspect variables.
-- LINKS :
--   > nvim-dap          : https://github.com/mfussenegger/nvim-dap
--   > nvim-dap-ui       : https://github.com/rcarriga/nvim-dap-ui
--   > mason-nvim-dap    : https://github.com/jay-babu/mason-nvim-dap.nvim
--   > dap-virtual-text  : https://github.com/theHamsta/nvim-dap-virtual-text
-- LEARNING NOTES :
--   Cursor on a line, <leader>db to set a breakpoint, <leader>dc to launch. Execution pauses
--   at the breakpoint; dap-ui shows scopes/variables/call-stack and virtual text shows each
--   variable's value inline. Step with <leader>do (over) / <leader>di (into) / <leader>du (out).
-- ASTRAL/uv :
--   The Python config below runs YOUR code with the project's uv virtualenv interpreter:
--   it prefers $VIRTUAL_ENV, then ./.venv/bin/python (uv's default), then system python.
--   debugpy itself runs from its isolated Mason env, separate from your project venv.
-- ICONS :
--   The breakpoint/stopped signs use \u{XXXX} escapes (Nerd Font codepoints) so the glyphs
--   survive transfer — raw private-use glyphs get silently stripped. Requires a Nerd Font.
-- ================================================================================================
return {
	"rcarriga/nvim-dap-ui",
	dependencies = {
		"mfussenegger/nvim-dap",
		"nvim-neotest/nvim-nio",
		"theHamsta/nvim-dap-virtual-text",
		{ "jay-babu/mason-nvim-dap.nvim", dependencies = { "mason-org/mason.nvim" } },
	},
	keys = {
		{
			"<leader>db",
			function()
				require("dap").toggle_breakpoint()
			end,
			desc = "DAP: toggle breakpoint",
		},
		{
			"<leader>dB",
			function()
				require("dap").set_breakpoint(vim.fn.input("Condition: "))
			end,
			desc = "DAP: conditional breakpoint",
		},
		{
			"<leader>dc",
			function()
				require("dap").continue()
			end,
			desc = "DAP: continue / start",
		},
		{
			"<leader>do",
			function()
				require("dap").step_over()
			end,
			desc = "DAP: step over",
		},
		{
			"<leader>di",
			function()
				require("dap").step_into()
			end,
			desc = "DAP: step into",
		},
		{
			"<leader>du",
			function()
				require("dap").step_out()
			end,
			desc = "DAP: step out",
		},
		{
			"<leader>dr",
			function()
				require("dap").repl.open()
			end,
			desc = "DAP: open REPL",
		},
		{
			"<leader>dl",
			function()
				require("dap").run_last()
			end,
			desc = "DAP: run last",
		},
		{
			"<leader>dx",
			function()
				require("dap").terminate()
			end,
			desc = "DAP: terminate",
		},
		{
			"<leader>dt",
			function()
				require("dapui").toggle()
			end,
			desc = "DAP: toggle UI",
		},
		{
			"<leader>de",
			function()
				require("dapui").eval()
			end,
			mode = { "n", "v" },
			desc = "DAP: evaluate expression",
		},
	},
	config = function()
		local dap, dapui = require("dap"), require("dapui")

		dapui.setup()
		require("nvim-dap-virtual-text").setup({})

		require("mason-nvim-dap").setup({
			ensure_installed = { "python", "codelldb" },
			-- No auto-download of debug adapters on engagement boxes (DOTFILES_OFFLINE=1). See globals.lua.
			automatic_installation = not vim.g.dotfiles_offline,
			handlers = {}, -- sensible defaults; Python is overridden below to be uv-aware
		})

		-- ── uv-aware Python debugging ────────────────────────────────────────────
		-- Windows venvs put the interpreter at \Scripts\python.exe (not /bin/python) and ship
		-- only `python` on PATH (no `python3`), so the interpreter paths below branch on OS.
		local is_win = vim.fn.has("win32") == 1
		local venv_python = is_win and "\\Scripts\\python.exe" or "/bin/python"
		local function uv_python()
			if vim.env.VIRTUAL_ENV and vim.env.VIRTUAL_ENV ~= "" then
				return vim.env.VIRTUAL_ENV .. venv_python
			end
			local venv = vim.fn.getcwd() .. (is_win and "/.venv\\Scripts\\python.exe" or "/.venv/bin/python")
			if vim.fn.executable(venv) == 1 then
				return venv
			end
			local sys = vim.fn.exepath(is_win and "python" or "python3")
			return sys ~= "" and sys or "python"
		end

		local debugpy_python = vim.fn.stdpath("data")
			.. (is_win and "/mason/packages/debugpy/venv\\Scripts\\python.exe" or "/mason/packages/debugpy/venv/bin/python")

		dap.adapters.python = function(cb, config)
			if config.request == "attach" then
				local c = config.connect or config
				cb({ type = "server", host = c.host or "127.0.0.1", port = c.port or 5678 })
			else
				cb({
					type = "executable",
					command = vim.fn.executable(debugpy_python) == 1 and debugpy_python or (is_win and "python" or "python3"),
					args = { "-m", "debugpy.adapter" },
					options = { source_filetype = "python" },
				})
			end
		end

		dap.configurations.python = {
			{
				type = "python",
				request = "launch",
				name = "Launch file (uv .venv)",
				program = "${file}",
				pythonPath = uv_python,
				console = "integratedTerminal",
			},
			{
				type = "python",
				request = "launch",
				name = "Launch module",
				module = function()
					return vim.fn.input("Module: ")
				end,
				pythonPath = uv_python,
				console = "integratedTerminal",
			},
		}

		dap.listeners.before.attach.dapui_config = function()
			dapui.open()
		end
		dap.listeners.before.launch.dapui_config = function()
			dapui.open()
		end
		dap.listeners.before.event_terminated.dapui_config = function()
			dapui.close()
		end
		dap.listeners.before.event_exited.dapui_config = function()
			dapui.close()
		end

		-- Signs (Nerd Font glyphs as escapes so they don't get stripped):
		vim.fn.sign_define("DapBreakpoint", { text = "\u{f111}", texthl = "DiagnosticError", linehl = "", numhl = "" }) -- f111 nf-fa-circle
		vim.fn.sign_define(
			"DapStopped",
			{ text = "\u{f061}", texthl = "DiagnosticWarn", linehl = "Visual", numhl = "" }
		) -- f061 nf-fa-arrow_right
	end,
}
