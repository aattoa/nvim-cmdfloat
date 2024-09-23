local M = {}

---@class CmdlineOptions
---@field position?    number Between 0.0 and 1.0
---@field width?       number Between 0.0 and 1.0
---@field border?      string Border around the cmdline window.
---@field on_window?   fun(window: integer) Invoked on the cmdline window.
---@field on_buffer?   fun(buffer: integer) Invoked on the cmdline buffer.
---@field completeopt? string[] Local value for 'completeopt'.

---@type CmdlineOptions
M.default_options = {}

---@type string?
local omnifunc_lead

---@type fun(findstart: integer): integer|string[]
function vim.g.nvim_cmdline_omnifunc(findstart)
    if findstart == 1 then
        local cursor = vim.fn.col('.') - 1
        local prompt = vim.fn.prompt_getprompt(vim.api.nvim_get_current_buf())
        omnifunc_lead = vim.api.nvim_get_current_line():sub(#prompt + 1, cursor)
        return cursor - #omnifunc_lead:match('([a-zA-Z_]*)$')
    else
        return vim.fn.getcompletion(omnifunc_lead, 'cmdline')
    end
end

---@param options? CmdlineOptions
function M.open(options)
    if not options then options = M.default_options end

    local buffer = vim.api.nvim_create_buf(false --[[listed]], true --[[scratch]])
    vim.bo[buffer].filetype  = 'vim'
    vim.bo[buffer].buftype   = 'prompt'
    vim.bo[buffer].bufhidden = 'delete'
    vim.bo[buffer].omnifunc  = 'v:lua.vim.g.nvim_cmdline_omnifunc'

    vim.keymap.set('n', ':', ':', { buffer = buffer, desc = 'nvim-cmdline: Access native cmdline' })
    vim.keymap.set('n', '<esc>', '<cmd>bdelete!<cr>', { buffer = buffer, desc = 'nvim-cmdline: Close' })
    vim.keymap.set('i', '<tab>', 'pumvisible() ? "<c-n>" : "<c-x><c-o>"', { buffer = buffer, expr = true })
    vim.keymap.set('i', '<s-tab>', 'pumvisible() ? "<c-p>" : "<s-tab>"', { buffer = buffer, expr = true })

    vim.fn.prompt_setprompt(buffer, ':')
    vim.fn.prompt_setcallback(buffer, function (command)
        vim.api.nvim_buf_delete(buffer, { force = true })
        vim.schedule(function () vim.cmd(command) end)
    end)

    if options.completeopt then
        local previous_completeopt = vim.opt.completeopt
        vim.api.nvim_create_autocmd('BufEnter', {
            callback = function () vim.opt.completeopt = options.completeopt end,
            buffer   = buffer,
            desc     = 'nvim-cmdline: Set local completeopt',
        })
        vim.api.nvim_create_autocmd('BufLeave', {
            callback = function () vim.opt.completeopt = previous_completeopt end,
            buffer   = buffer,
            desc     = 'nvim-cmdline: Restore global completeopt',
        })
    end

    local width = options.width or 0.6
    local position = options.position or 0.4
    local window = vim.api.nvim_open_win(buffer, true --[[enter]], {
        relative = 'editor',
        border   = options.border or 'rounded',
        row      = math.floor(vim.o.lines * position),
        col      = math.floor(vim.o.columns * (1 - width) / 2),
        width    = math.floor(vim.o.columns * width),
        height   = 1,
    })
    vim.wo[window].number = false
    vim.wo[window].relativenumber = false
    vim.wo[window].cursorline = false

    if options.on_buffer then options.on_buffer(buffer) end
    if options.on_window then options.on_window(window) end

    vim.cmd.startinsert()
end

return M
