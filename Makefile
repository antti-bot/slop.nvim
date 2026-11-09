NVIM ?= nvim
GITSIGNS_RTP ?= ../gitsigns.nvim

.PHONY: test
test:
	GITSIGNS_RTP="$(GITSIGNS_RTP)" $(NVIM) --headless -u NONE -i NONE -l tests/run.lua
