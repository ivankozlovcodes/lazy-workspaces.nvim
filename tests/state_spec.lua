local H = require("tests.helpers")
local state = require("lazy-workspaces.state")

describe("state", function()
	local tmp_path

	before_each(function()
		tmp_path = vim.fn.tempname() .. ".json"
		state._set_path(tmp_path)
	end)

	after_each(function()
		if vim.fn.filereadable(tmp_path) == 1 then
			vim.fn.delete(tmp_path)
		end
		state._reset_path()
	end)

	-- ── state.read() ────────────────────────────────────────────────────────────

	describe("read()", function()
		it("returns {} when file does not exist", function()
			assert.are.same({}, state.read())
		end)

		it("returns parsed table for valid nested JSON", function()
			vim.fn.writefile({ '{"ivan":{"common":true,"work":false}}' }, tmp_path)
			local result = state.read()
			assert.is_true(result.ivan.common)
			assert.is_false(result.ivan.work)
		end)

		it("returns {} and emits WARN for malformed JSON", function()
			vim.fn.writefile({ "not valid json {{" }, tmp_path)
			local warned = false
			local orig = vim.notify
			vim.notify = function(_, level)
				if level == vim.log.levels.WARN then
					warned = true
				end
			end
			local result = state.read()
			vim.notify = orig
			assert.are.same({}, result)
			assert.is_true(warned)
		end)

		it("returns {} and emits WARN when JSON root is not a table", function()
			vim.fn.writefile({ '"just a string"' }, tmp_path)
			local warned = false
			local orig = vim.notify
			vim.notify = function(_, level)
				if level == vim.log.levels.WARN then
					warned = true
				end
			end
			local result = state.read()
			vim.notify = orig
			assert.are.same({}, result)
			assert.is_true(warned)
		end)
	end)

	-- ── state.write() ───────────────────────────────────────────────────────────

	describe("write()", function()
		it("creates file when it does not exist", function()
			state.write({ ivan = { common = true } })
			assert.is_true(H.file_exists(tmp_path))
		end)

		it("overwrites existing file", function()
			vim.fn.writefile({ '{"old":"data"}' }, tmp_path)
			state.write({ ivan = { common = true } })
			local result = state.read()
			assert.is_nil(result.old)
			assert.is_true(result.ivan.common)
		end)

		it("round-trips boolean true and false correctly", function()
			state.write({ cfg = { ws_a = true, ws_b = false } })
			local result = state.read()
			assert.is_true(result.cfg.ws_a)
			assert.is_false(result.cfg.ws_b)
		end)
	end)

	-- ── state.reconcile() ───────────────────────────────────────────────────────

	describe("reconcile()", function()
		it("returns {} for empty input, writes nothing", function()
			local effective = state.reconcile({})
			assert.are.same({}, effective)
			assert.is_false(H.file_exists(tmp_path))
		end)

		it("auto-includes new config/workspace as true and writes JSON", function()
			local effective = state.reconcile({ ivan = { "common" } })
			assert.is_true(effective.ivan.common)
			assert.is_true(H.file_exists(tmp_path))
			local on_disk = state.read()
			assert.is_true(on_disk.ivan.common)
		end)

		it("keeps existing true value without marking dirty", function()
			state.write({ ivan = { common = true } })
			local effective = state.reconcile({ ivan = { "common" } })
			assert.is_true(effective.ivan.common)
		end)

		it("keeps existing false value (excluded workspace)", function()
			state.write({ ivan = { work = false } })
			local effective = state.reconcile({ ivan = { "work" } })
			assert.is_false(effective.ivan.work)
		end)

		it("emits WARN for stale JSON entry not in input configs", function()
			state.write({ ivan = { ghost = true } })
			local warned = false
			local orig = vim.notify
			vim.notify = function(msg, level)
				if level == vim.log.levels.WARN and msg:match("stale") then
					warned = true
				end
			end
			state.reconcile({ ivan = { "common" } })
			vim.notify = orig
			assert.is_true(warned)
		end)

		it("handles mix: new, true, false, and stale entries", function()
			state.write({ ivan = { existing_true = true, existing_false = false, ghost = true } })
			local warned_stale = false
			local orig = vim.notify
			vim.notify = function(msg, level)
				if level == vim.log.levels.WARN and msg:match("stale") then
					warned_stale = true
				end
			end
			local effective = state.reconcile({ ivan = { "new_ws", "existing_true", "existing_false" } })
			vim.notify = orig

			assert.is_true(effective.ivan.new_ws)
			assert.is_true(effective.ivan.existing_true)
			assert.is_false(effective.ivan.existing_false)
			assert.is_nil(effective.ivan.ghost)
			assert.is_true(warned_stale)
		end)

		it("handles multiple configs independently", function()
			local effective = state.reconcile({
				ivan   = { "common", "personal" },
				johnny = { "common", "work" },
			})
			assert.is_true(effective.ivan.common)
			assert.is_true(effective.ivan.personal)
			assert.is_true(effective.johnny.common)
			assert.is_true(effective.johnny.work)
		end)
	end)
end)
