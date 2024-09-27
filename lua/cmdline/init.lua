local M = {}

---@class CmdlineOptions
---@field position?    number Between 0.0 and 1.0
---@field width?       number Between 0.0 and 1.0
---@field border?      string Border around the cmdline window.
---@field on_window?   fun(window: integer) Invoked on the cmdline window.
---@field on_buffer?   fun(buffer: integer) Invoked on the cmdline buffer.
---@field completeopt? string[] Local value for 'completeopt'.

---@class CmdlineState
---@field omnifunc_lead   string
---@field working_command string
---@field history_index   integer
---@field return_window   integer

---@type CmdlineOptions
M.default_options = {}

---@type table<integer, CmdlineState>
M.instances = {}

---@type integer?
local current_instance_buffer

---@return CmdlineState
local function current_instance()
    return M.instances[assert(current_instance_buffer)]
end

---@return string
local function current_line()
    return vim.api.nvim_buf_call(assert(current_instance_buffer), vim.api.nvim_get_current_line)
end

---@return string
local function current_prompt()
    return vim.fn.prompt_getprompt(assert(current_instance_buffer))
end

---@type fun(findstart: integer): integer|string[]
function vim.g.nvim_cmdline_omnifunc(findstart)
    local instance = current_instance()
    if findstart == 1 then
        local cursor = vim.fn.col('.') - 1
        instance.omnifunc_lead = current_line():sub(#current_prompt() + 1, cursor)
        return cursor - #instance.omnifunc_lead:match('([a-zA-Z_]*)$')
    else
        return vim.fn.getcompletion(instance.omnifunc_lead, 'cmdline')
    end
end

---@return string
function M.get_command()
    return current_line():sub(#current_prompt() + 1)
end

---@param command string
function M.set_command(command)
    vim.api.nvim_buf_call(assert(current_instance_buffer), function ()
        vim.api.nvim_set_current_line(current_prompt() .. command)
    end)
end

---@param index integer
local function set_history_index(index)
    local instance = current_instance()
    local max = vim.fn.histnr('cmd')
    if instance.history_index == max then
        instance.working_command = M.get_command()
    end
    if index > max then
        instance.history_index = max
    elseif index < 0 then
        instance.history_index = 0
    else
        instance.history_index = index
    end
    if instance.history_index == max then
        M.set_command(instance.working_command)
    else
        M.set_command(vim.fn.histget('cmd', instance.history_index + 1))
    end
end

function M.history_up()
    set_history_index(current_instance().history_index - vim.v.count1)
end

function M.history_down()
    set_history_index(current_instance().history_index + vim.v.count1)
end

function M.history_top()
    set_history_index(0)
end

function M.history_bottom()
    set_history_index(vim.fn.histnr('cmd'))
end

---@type fun(options: CmdlineOptions): vim.api.keyset.win_config
local function cmdline_window_config(options)
    local width = options.width or 0.6
    local position = options.position or 0.4
    return {
        relative = 'editor',
        border   = options.border or 'rounded',
        row      = math.floor(vim.o.lines * position),
        col      = math.floor(vim.o.columns * (1 - width) / 2),
        width    = math.floor(vim.o.columns * width),
        height   = 1,
    }
end

---@param options? CmdlineOptions
function M.open(options)
    if not options then options = M.default_options end

    local buffer = vim.api.nvim_create_buf(false --[[listed]], true --[[scratch]])
    vim.bo[buffer].filetype  = 'vim'
    vim.bo[buffer].buftype   = 'prompt'
    vim.bo[buffer].bufhidden = 'delete'
    vim.bo[buffer].omnifunc  = 'v:lua.vim.g.nvim_cmdline_omnifunc'

    ---@type fun(description: string, override?: vim.keymap.set.Opts): vim.keymap.set.Opts
    local function opts(description, override)
        return vim.tbl_deep_extend('force', { buffer = buffer, desc = 'nvim-cmdline: ' .. description }, override or {})
    end

    vim.keymap.set('n', 'gg', M.history_top, opts('History top'))
    vim.keymap.set('n', 'G', M.history_bottom, opts('History bottom'))
    vim.keymap.set('n', 'k', M.history_up, opts('History up'))
    vim.keymap.set('n', 'j', M.history_down, opts('History down'))
    vim.keymap.set({ 'n', 'i' }, '<up>', M.history_up, opts('History up'))
    vim.keymap.set({ 'n', 'i' }, '<down>', M.history_down, opts('History down'))
    vim.keymap.set('n', ':', ':', opts('Backup native cmdline'))
    vim.keymap.set('n', '<esc>', '<cmd>bwipeout!<cr>', opts('Close'))
    vim.keymap.set('i', '<tab>', 'pumvisible() ? "<c-n>" : "<c-x><c-o>"', opts('Next completion', { expr = true }))
    vim.keymap.set('i', '<s-tab>', 'pumvisible() ? "<c-p>" : "<s-tab>"', opts('Previous completion', { expr = true }))

    vim.fn.prompt_setprompt(buffer, ':')
    vim.fn.prompt_setcallback(buffer, function (command)
        vim.api.nvim_buf_delete(buffer, { force = true })
        vim.fn.histadd('cmd', command)
        vim.schedule(function () vim.cmd(command) end)
    end)

    local window = vim.api.nvim_open_win(buffer, false --[[enter]], cmdline_window_config(options))
    vim.wo[window].number = false
    vim.wo[window].relativenumber = false
    vim.wo[window].cursorline = false

    ---@type fun(event: string, description: string, callback: fun())
    local function autocmd(event, description, callback)
        vim.api.nvim_create_autocmd(event, {
            callback = callback,
            buffer   = buffer,
            desc     = 'nvim-cmdline: ' .. description,
        })
    end

    local previous_completeopt = vim.opt.completeopt
    autocmd('BufEnter', 'Set cmdline instance', function ()
        current_instance_buffer = buffer
        if options.completeopt then vim.opt.completeopt = options.completeopt end
    end)
    autocmd('BufLeave', 'Reset cmdline instance', function ()
        current_instance_buffer = nil
        if options.completeopt then vim.opt.completeopt = previous_completeopt end
    end)
    autocmd('BufWipeout', 'Clean up cmdline instance', function ()
        vim.api.nvim_set_current_win(M.instances[buffer].return_window)
        M.instances[buffer] = nil
    end)
    autocmd('VimResized', 'Resize cmdline window', function ()
        vim.api.nvim_win_set_config(window, cmdline_window_config(options))
    end)

    M.instances[buffer] = {
        omnifunc_lead   = '',
        working_command = '',
        history_index   = vim.fn.histnr('cmd'),
        return_window   = vim.api.nvim_get_current_win(),
    }

    vim.api.nvim_set_current_win(window)

    if options.on_buffer then options.on_buffer(buffer) end
    if options.on_window then options.on_window(window) end

    vim.cmd.startinsert()
end

return M
