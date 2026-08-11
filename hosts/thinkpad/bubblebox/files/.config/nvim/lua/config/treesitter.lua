-- Treesitter compatibility fix for the archived nvim-treesitter `master`
-- branch on Neovim 0.12. Ported from the nixvim module.

-- `extraConfigLua` (the `do ... end` block) and markdown-highlights.scm.
--
-- Background (see commit history in the nixvim module):
--   * match[id] in query predicates now returns a LIST of nodes on 0.12,
--     not a single node. The archived plugin's handlers don't unwrap, so
--     highlight captures using `is?`/`nth?`/`kind-eq?` error out. We
--     re-register the handlers with force=true to unwrap properly.
--   * The merged markdown highlights query uses `conceal_lines`, which
--     triggers Neovim 0.12 bug #39032. We replace it entirely (read from
--     queries/markdown/highlights.scm in the config dir).
--   * The merged markdown injections query uses set-lang-from-info-string!,
--     which we also re-register below.
--
-- Run BEFORE nvim-treesitter compiles its queries: wired into the
-- nvim-treesitter plugin spec as `init = function() require("config.treesitter") end`.

local query = require("vim.treesitter.query")
local opts = { force = true }

local function unwrap(match, id)
  local val = match[id]
  if not val then return nil end
  if type(val) == "table" then return val[1] end
  return val
end

local function valid_args(name, pred, count, strict_count)
  local arg_count = #pred - 1
  if strict_count then
    if arg_count ~= count then return false end
  elseif arg_count < count then
    return false
  end
  return true
end

query.add_predicate("nth?", function(match, _pattern, _bufnr, pred)
  if not valid_args("nth?", pred, 2, true) then return end
  local node = unwrap(match, pred[2])
  local n = tonumber(pred[3])
  if node and node:parent() and node:parent():named_child_count() > n then
    return node:parent():named_child(n) == node
  end
  return false
end, opts)

query.add_predicate("is?", function(match, _pattern, bufnr, pred)
  if not valid_args("is?", pred, 2) then return end
  local locals = require("nvim-treesitter.locals")
  local node = unwrap(match, pred[2])
  local types = { unpack(pred, 3) }
  if not node then return true end
  local _, _, kind = locals.find_definition(node, bufnr)
  return vim.tbl_contains(types, kind)
end, opts)

query.add_predicate("kind-eq?", function(match, _pattern, _bufnr, pred)
  if not valid_args(pred[1], pred, 2) then return end
  local node = unwrap(match, pred[2])
  local types = { unpack(pred, 3) }
  if not node then return true end
  return vim.tbl_contains(types, node:type())
end, opts)

query.add_directive("set-lang-from-mimetype!", function(match, _pattern, bufnr, pred, metadata)
  local capture_id = pred[2]
  local node = unwrap(match, capture_id)
  if not node then return end
  local type_attr_value = vim.treesitter.get_node_text(node, bufnr)
  local html_script_type_languages = {
    ["importmap"] = "json",
    ["module"] = "javascript",
    ["application/ecmascript"] = "javascript",
    ["text/ecmascript"] = "javascript",
  }
  local configured = html_script_type_languages[type_attr_value]
  if configured then
    metadata["injection.language"] = configured
  else
    local parts = vim.split(type_attr_value, "/", {})
    metadata["injection.language"] = parts[#parts]
  end
end, opts)

query.add_directive("set-lang-from-info-string!", function(match, _pattern, bufnr, pred, metadata)
  local capture_id = pred[2]
  local node = unwrap(match, capture_id)
  if not node then return end
  local injection_alias = vim.treesitter.get_node_text(node, bufnr):lower()
  local non_filetype_aliases = {
    ex = "elixir", pl = "perl", sh = "bash", uxn = "uxntal", ts = "typescript",
  }
  local ft = vim.filetype.match({ filename = "a." .. injection_alias })
  metadata["injection.language"] = ft or non_filetype_aliases[injection_alias] or injection_alias
end, opts)

query.add_directive("make-range!", function() end, opts)

query.add_directive("downcase!", function(match, _pattern, bufnr, pred, metadata)
  local id = pred[2]
  local node = unwrap(match, id)
  if not node then return end
  local text = vim.treesitter.get_node_text(node, bufnr, { metadata = metadata[id] }) or ""
  if not metadata[id] then metadata[id] = {} end
  metadata[id].text = string.lower(text)
end, opts)

-- Replace the merged markdown highlights query (drop conceal_lines that
-- triggers Neovim 0.12 bug #39032). File is shipped alongside this config.
local fixed_path = vim.fn.stdpath("config") .. "/queries/markdown/highlights.scm"
local f = io.open(fixed_path, "r")
if f then
  local content = f:read("*a")
  f:close()
  vim.treesitter.query.set("markdown", "highlights", content)
end

-- Replace the merged markdown injections query (clean built-in style using
-- @injection.language capture — avoids any merge oddities).
vim.treesitter.query.set("markdown", "injections", [=[
(fenced_code_block
  (info_string
    (language) @injection.language)
  (code_fence_content) @injection.content)

((html_block) @injection.content
  (#set! injection.language "html")
  (#set! injection.combined)
  (#set! injection.include-children))

((minus_metadata) @injection.content
  (#set! injection.language "yaml")
  (#offset! @injection.content 1 0 -1 0)
  (#set! injection.include-children))

((plus_metadata) @injection.content
  (#set! injection.language "toml")
  (#offset! @injection.content 1 0 -1 0)
  (#set! injection.include-children))

([
  (inline)
  (pipe_table_cell)
] @injection.content
  (#set! injection.language "markdown_inline"))
]=])
