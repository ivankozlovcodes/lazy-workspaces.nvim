PLENARY ?= ~/.local/share/nvim/lazy/plenary.nvim

.PHONY: test

test:
	PLENARY_PATH=$(PLENARY) nvim --headless \
		-u tests/minimal.init.lua \
		-c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal.init.lua'}" \
		-c "qa!"
