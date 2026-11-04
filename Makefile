.PHONY: deps test test_file

NVIM ?= nvim

deps: deps/mini.nvim deps/lualine.nvim

deps/mini.nvim:
	git clone --depth 1 https://github.com/echasnovski/mini.nvim $@

deps/lualine.nvim:
	git clone --depth 1 https://github.com/nvim-lualine/lualine.nvim $@

test: deps
	$(NVIM) --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run()"

test_file: deps
	$(NVIM) --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"
