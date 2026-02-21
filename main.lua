--- gcs-yazi: Browse, preview, and navigate Google Cloud Storage from yazi.
---
--- Features:
---   entry()  - Browse GCS buckets/objects (keybinding: g s)
---   peek()   - Preview GCS file content in the preview pane
---   setup()  - Header path indicator + auto-populate on cd
---
--- Requires: gcloud CLI (google-cloud-sdk)

local KEYS = "1234567890abcdefghijklmnopqrstuvwxyz"
local M = {}

local GCS_TMP = "/tmp/yazi-gcs"

-- Default gcloud path; overridden by setup({ gcloud_path = "..." })
M._gcloud = "gcloud"

-- Sync helpers
local get_cwd = ya.sync(function()
	return cx.active.current.cwd
end)

local function gcloud(args)
	return Command(M._gcloud):arg(args):stdout(Command.PIPED):stderr(Command.PIPED):output()
end

local function parse_lines(stdout)
	local lines = {}
	for line in (stdout or ""):gmatch("[^\r\n]+") do
		local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
		if #trimmed > 0 then
			lines[#lines + 1] = trimmed
		end
	end
	return lines
end

--- Check if a path is inside the GCS temp directory.
local function is_gcs_dir(path)
	return #path > #GCS_TMP and path:sub(1, #GCS_TMP) == GCS_TMP
end

--- Derive gs:// directory path from local temp directory path.
--- /tmp/yazi-gcs/bucket-name/folder -> gs://bucket-name/folder/
local function to_gcs_path(local_path)
	local rel = local_path:sub(#GCS_TMP + 2) -- strip "/tmp/yazi-gcs/"
	local gs = "gs://" .. rel
	if gs:sub(-1) ~= "/" then
		gs = gs .. "/"
	end
	return gs
end

--- Derive gs:// file path (no trailing /).
--- /tmp/yazi-gcs/bucket-name/file.txt -> gs://bucket-name/file.txt
local function to_gcs_path_file(local_path)
	return "gs://" .. local_path:sub(#GCS_TMP + 2)
end

local function pick_bucket(buckets)
	if #buckets == 0 then return nil end
	if #buckets == 1 then return buckets[1] end

	local cands = {}
	for i, b in ipairs(buckets) do
		if i > #KEYS then break end
		local name = b:match("^gs://(.-)/?$") or b
		cands[#cands + 1] = { on = KEYS:sub(i, i), desc = name }
	end

	ya.sleep(0.1)
	local idx = ya.which({ cands = cands })
	if idx and idx >= 1 and idx <= #buckets then
		return buckets[idx]
	end
	return nil
end

--- Populate a local temp directory with one level of GCS listing.
--- Creates real subdirectories and empty files matching the GCS structure.
local function populate(local_dir, gs_path)
	ya.err("gcs-yazi: populate " .. local_dir .. " <- " .. gs_path)
	local out = gcloud({ "storage", "ls", gs_path })

	if not out then
		ya.notify({ title = "GCS", content = "gcloud failed to run", timeout = 5, level = "error" })
		return false
	end
	if not out.status.success then
		local msg = (out.stderr or ""):sub(1, 100):gsub("%s+$", "")
		ya.notify({ title = "GCS", content = msg, timeout = 5, level = "error" })
		return false
	end

	local lines = parse_lines(out.stdout)
	if #lines == 0 then
		ya.notify({ title = "GCS", content = "Empty: " .. gs_path, timeout = 3, level = "warn" })
		return true
	end

	local cmds = {}
	local count = 0
	for _, line in ipairs(lines) do
		local child = line:sub(#gs_path + 1)
		if #child > 0 then
			local is_dir = child:sub(-1) == "/"
			if is_dir then
				child = child:sub(1, -2)
			end

			local escaped = child:gsub("'", "'\\''")
			local full = local_dir .. "/" .. escaped

			if is_dir then
				cmds[#cmds + 1] = "mkdir -p '" .. full .. "'"
			else
				cmds[#cmds + 1] = "touch '" .. full .. "'"
			end
			count = count + 1
		end
	end

	if #cmds > 0 then
		Command("sh"):arg({ "-c", table.concat(cmds, " && ") }):output()
	end

	ya.err("gcs-yazi: created " .. count .. " items in " .. local_dir)
	return true
end

---------------------------------------------------------------------------
-- setup(): Header indicator + auto-populate on cd
-- Called from init.lua: require("gcs-yazi"):setup()
---------------------------------------------------------------------------

function M:setup(opts)
	opts = opts or {}

	-- Allow overriding gcloud path (e.g. "/opt/homebrew/bin/gcloud")
	if opts.gcloud_path then
		M._gcloud = opts.gcloud_path
	end

	-- Feature 1: Header shows cloud gs://bucket/path/ when in GCS temp dir
	Header:children_add(function()
		local cwd = tostring(cx.active.current.cwd)
		if not is_gcs_dir(cwd) then return ui.Line({}) end
		return ui.Line { ui.Span(" \u{2601} " .. to_gcs_path(cwd)):style(ui.Style():fg("blue"):bold()) }
	end, 500, Header.LEFT)

	-- Feature 3: Auto-populate GCS subdirectories on cd
	ps.sub("cd", function()
		local cwd = tostring(cx.active.current.cwd)
		if is_gcs_dir(cwd) then
			ya.emit("plugin", { self._id, ya.quote(cwd, true) })
		end
	end)
end

---------------------------------------------------------------------------
-- entry(): Browser — triggered by gs keybinding or cd hook
---------------------------------------------------------------------------

function M:entry(job)
	-- Called from cd hook with a path argument -> auto-populate
	if job and job.args and job.args[1] then
		local auto_dir = job.args[1]
		if is_gcs_dir(auto_dir) then
			ya.err("gcs-yazi: auto-populate " .. auto_dir)
			local gs_path = to_gcs_path(auto_dir)
			if populate(auto_dir, gs_path) then
				ya.emit("cd", { Url(auto_dir) })
			end
			return
		end
	end

	ya.err("gcs-yazi: === entry ===")
	local cwd_url = get_cwd()
	local cwd = tostring(cwd_url)

	if is_gcs_dir(cwd) then
		-- Already inside GCS temp dir — populate current directory
		local gs_path = to_gcs_path(cwd)
		ya.notify({ title = "GCS", content = "Loading " .. gs_path, timeout = 2 })

		if populate(cwd, gs_path) then
			ya.emit("cd", { Url(cwd) })
		end
		return
	end

	-- Fresh GCS browse — pick bucket
	local out = gcloud({ "storage", "ls" })
	if not out or not out.status.success then
		ya.notify({ title = "GCS", content = "gcloud failed", timeout = 5, level = "error" })
		return
	end

	local buckets = parse_lines(out.stdout)
	if #buckets == 0 then
		ya.notify({ title = "GCS", content = "No GCS buckets found", timeout = 5, level = "warn" })
		return
	end

	local bucket_path = pick_bucket(buckets)
	if not bucket_path then return end

	local bucket_name = bucket_path:match("^gs://(.-)/?$") or bucket_path
	local local_dir = GCS_TMP .. "/" .. bucket_name

	-- Clean slate for fresh browse
	Command("sh"):arg({ "-c", "rm -rf '" .. local_dir .. "' && mkdir -p '" .. local_dir .. "'" }):output()

	if populate(local_dir, bucket_path) then
		ya.emit("cd", { Url(local_dir) })
		ya.notify({ title = "GCS", content = "Browsing: " .. bucket_path, timeout = 3 })
	end

	ya.err("gcs-yazi: === done ===")
end

---------------------------------------------------------------------------
-- Feature 4: peek() / seek() — GCS file preview
---------------------------------------------------------------------------

function M:peek(job)
	local path = tostring(job.file.url)
	if not is_gcs_dir(path) then
		return require("code"):peek(job)
	end

	local gs_path = to_gcs_path_file(path)
	local out = Command(M._gcloud)
		:arg({ "storage", "cat", "-r", "0-800", gs_path })
		:stdout(Command.PIPED):stderr(Command.PIPED):output()

	if not out or not out.status.success then
		local msg = (out and out.stderr) or "gcloud failed"
		ya.preview_widget(job, { ui.Text("\u{26a0} " .. msg):area(job.area) })
		return
	end

	ya.preview_widget(job, { ui.Text(out.stdout):area(job.area):wrap(ui.Wrap.YES) })
end

function M:seek(job)
	require("code"):seek(job)
end

return M
