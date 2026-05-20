local opts = require("lazy-workspaces.opts")

-- ── parse_source() ────────────────────────────────────────────────────────────

describe("parse_source()", function()
	it("returns source and nil branch for plain string", function()
		local src, branch = opts.parse_source("/tmp/nvim")
		assert.are.equal("/tmp/nvim", src)
		assert.is_nil(branch)
	end)

	it("returns source and branch from table", function()
		local src, branch = opts.parse_source({ source = "git@github.com:user/repo.git", branch = "main" })
		assert.are.equal("git@github.com:user/repo.git", src)
		assert.are.equal("main", branch)
	end)

	it("returns nil branch when not set in table", function()
		local src, branch = opts.parse_source({ source = "https://github.com/user/repo" })
		assert.are.equal("https://github.com/user/repo", src)
		assert.is_nil(branch)
	end)

	it("errors on unsupported type", function()
		assert.has_error(function()
			opts.parse_source(42)
		end)
	end)
end)

-- ── name_from_source() ────────────────────────────────────────────────────────

describe("name_from_source()", function()
	it("returns local path unchanged", function()
		assert.are.equal("/tmp/nvim", opts.name_from_source("/tmp/nvim"))
	end)

	it("derives user/repo from ssh URL with .git suffix", function()
		assert.are.equal("user/repo", opts.name_from_source("git@github.com:user/repo.git"))
	end)

	it("derives user/repo from ssh URL without .git suffix", function()
		assert.are.equal("user/repo", opts.name_from_source("git@github.com:user/repo"))
	end)

	it("derives user/repo from https URL with .git suffix", function()
		assert.are.equal("user/repo", opts.name_from_source("https://github.com/user/repo.git"))
	end)

	it("derives user/repo from https URL without .git suffix", function()
		assert.are.equal("user/repo", opts.name_from_source("https://github.com/user/repo"))
	end)

	it("returns source unchanged for unrecognised scheme", function()
		assert.are.equal("file:///tmp/x", opts.name_from_source("file:///tmp/x"))
	end)
end)

-- ── normalize() ───────────────────────────────────────────────────────────────

describe("normalize()", function()
	it("returns empty list for empty table", function()
		assert.are.same({}, opts.normalize({}))
	end)

	-- array form

	it("handles array of plain string sources", function()
		local result = opts.normalize({ "/tmp/a", "/tmp/b" })
		assert.are.equal(2, #result)
		assert.are.equal("/tmp/a", result[1].source)
		assert.are.equal("/tmp/a", result[1].name)
		assert.is_nil(result[1].branch)
		assert.are.equal("/tmp/b", result[2].source)
	end)

	it("preserves array order", function()
		local result = opts.normalize({ "/tmp/first", "/tmp/second", "/tmp/third" })
		assert.are.equal("/tmp/first", result[1].source)
		assert.are.equal("/tmp/second", result[2].source)
		assert.are.equal("/tmp/third", result[3].source)
	end)

	it("handles array of WorkspaceSource tables", function()
		local result = opts.normalize({
			{ source = "git@github.com:user/repo.git", branch = "main" },
		})
		assert.are.equal(1, #result)
		assert.are.equal("git@github.com:user/repo.git", result[1].source)
		assert.are.equal("user/repo", result[1].name)
		assert.are.equal("main", result[1].branch)
	end)

	it("uses explicit name field when present in array entry", function()
		local result = opts.normalize({
			{ name = "myconf", source = "git@github.com:user/repo.git" },
		})
		assert.are.equal("myconf", result[1].name)
	end)

	it("derives name from source when name absent in array table entry", function()
		local result = opts.normalize({
			{ source = "https://github.com/user/repo" },
		})
		assert.are.equal("user/repo", result[1].name)
	end)

	-- dict form

	it("handles dict with plain string source", function()
		local result = opts.normalize({ myconf = "/tmp/nvim" })
		assert.are.equal(1, #result)
		assert.are.equal("myconf", result[1].name)
		assert.are.equal("/tmp/nvim", result[1].source)
		assert.is_nil(result[1].branch)
	end)

	it("handles dict with WorkspaceSource table", function()
		local result = opts.normalize({
			myconf = { source = "git@github.com:user/repo.git", branch = "dev" },
		})
		assert.are.equal(1, #result)
		assert.are.equal("myconf", result[1].name)
		assert.are.equal("git@github.com:user/repo.git", result[1].source)
		assert.are.equal("dev", result[1].branch)
	end)

	it("uses dict key as name regardless of source URL", function()
		local result = opts.normalize({ custom_name = "https://github.com/user/repo" })
		assert.are.equal("custom_name", result[1].name)
	end)
end)

-- ── local_path_for() ──────────────────────────────────────────────────────────

describe("local_path_for()", function()
	it("returns absolute local path unchanged", function()
		local result = opts.local_path_for({ source = "/tmp/nvim" })
		assert.are.equal("/tmp/nvim", result)
	end)

	it("expands ~ in local path", function()
		local result = opts.local_path_for({ source = "~/nvim" })
		assert.is_false(result:sub(1, 1) == "~")
		assert.is_truthy(result:find("nvim"))
	end)

	it("maps ssh git URL to data dir using repo name", function()
		local result = opts.local_path_for({ source = "git@github.com:user/repo.git" })
		local expected = vim.fn.stdpath("data") .. "/lazy-workspaces/repo"
		assert.are.equal(expected, result)
	end)

	it("maps https git URL to data dir using repo name", function()
		local result = opts.local_path_for({ source = "https://github.com/user/myrepo" })
		local expected = vim.fn.stdpath("data") .. "/lazy-workspaces/myrepo"
		assert.are.equal(expected, result)
	end)

	it("strips .git suffix from repo name", function()
		local result = opts.local_path_for({ source = "https://github.com/user/repo.git" })
		assert.is_falsy(result:find("%.git"))
	end)
end)

-- ── apply_defaults() ──────────────────────────────────────────────────────────

describe("apply_defaults()", function()
	it("fills specs when absent", function()
		local result = opts.apply_defaults({})
		assert.are.same({ "plugins" }, result.specs)
	end)

	it("fills auto_pull = true when absent", function()
		local result = opts.apply_defaults({})
		assert.is_true(result.auto_pull)
	end)

	it("preserves explicit specs", function()
		local result = opts.apply_defaults({ specs = { "plugins", "themes" } })
		assert.are.same({ "plugins", "themes" }, result.specs)
	end)

	it("preserves explicit auto_pull = false", function()
		local result = opts.apply_defaults({ auto_pull = false })
		assert.is_false(result.auto_pull)
	end)

	it("treats nil opts same as empty table", function()
		local result = opts.apply_defaults(nil)
		assert.is_true(result.auto_pull)
		assert.are.same({ "plugins" }, result.specs)
	end)

	it("does not mutate the input table", function()
		local input = {}
		opts.apply_defaults(input)
		assert.is_nil(input.auto_pull)
		assert.is_nil(input.specs)
	end)
end)
