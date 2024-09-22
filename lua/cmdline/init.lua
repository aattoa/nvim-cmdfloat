local M = {}

---@class CmdlineOptions
---@field width?  number
---@field border? string

---@type string?
local omnifunc_lead

function vim.g.nvim_cmdline_omnifunc(findstart)
    if findstart == 1 then
        omnifunc_lead = vim.api.nvim_get_current_line():sub(2, vim.fn.col('.') - 1)
        return vim.fn.col('.') - #omnifunc_lead:match('([a-zA-Z_]*)$') - 1
    else
        return vim.fn.getcompletion(omnifunc_lead, 'cmdline')
    end
end

---@param options? CmdlineOptions
function M.open(options)
    if not options then options = {} end

    local buffer = vim.api.nvim_create_buf(false --[[listed]], true --[[scratch]])
    vim.bo[buffer].filetype = 'vim'
    vim.bo[buffer].buftype = 'prompt'
    vim.bo[buffer].bufhidden = 'delete'
    vim.bo[buffer].omnifunc = 'v:lua.vim.g.nvim_cmdline_omnifunc'

    vim.keymap.set('n', '<esc>', '<cmd>bdelete!<cr>', { buffer = buffer, desc = 'cmdline: Close' })
    vim.keymap.set('i', '<tab>', 'pumvisible() ? "<c-n>" : "<c-x><c-o>"', { buffer = buffer, expr = true })
    vim.keymap.set('i', '<s-tab>', 'pumvisible() ? "<c-p>" : "<s-tab>"', { buffer = buffer, expr = true })

    local width = options.width or 0.6
    local window = vim.api.nvim_open_win(buffer, true --[[enter]], {
        relative = 'editor',
        border   = options.border,
        row      = math.floor(vim.o.lines * 0.4),
        col      = math.floor(vim.o.columns * (1 - width) / 2),
        width    = math.floor(vim.o.columns * width),
        height   = 1,
    })
    vim.wo[window].number = false
    vim.wo[window].relativenumber = false
    vim.wo[window].cursorline = false

    vim.fn.prompt_setprompt(buffer, ':')
    vim.fn.prompt_setcallback(buffer, function (command)
        vim.api.nvim_buf_delete(buffer, { force = true })
        vim.schedule(function () vim.cmd(command) end)
    end)

    vim.cmd.startinsert()
end

return M
