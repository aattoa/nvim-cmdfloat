local M = {}

---@class CmdfloatOptions
---@field position?      number Between 0.0 and 1.0
---@field width?         number Between 0.0 and 1.0
---@field border?        string Border around the cmdfloat window.
---@field window_config? vim.api.keyset.win_config
---@field on_window?     fun(window: integer) Invoked on the cmdfloat window.
---@field on_buffer?     fun(buffer: integer) Invoked on the cmdfloat buffer.
---@field completeopt?   string[] Local value for 'completeopt'.

---@type CmdfloatOptions
M.default_options = {}

---@class Cmdfloat
---@field omnifunc_lead   string
---@field working_command string
---@field history_index   integer
---@field prompt_buffer   integer
---@field return_window   integer
local Cmdfloat = {}

---@type table<integer, Cmdfloat>
M.instances = {}

---@type integer?
M.current_instance_buffer = nil

---@return Cmdfloat
function Cmdfloat.current()
    return M.instances[assert(M.current_instance_buffer)]
end

---@type fun(prompt_buffer: integer, return_window: integer): Cmdfloat
function Cmdfloat.new(prompt_buffer, return_window)
    return setmetatable({
        omnifunc_lead   = '',
        working_command = '',
        history_index   = vim.fn.histnr('cmd'),
        prompt_buffer   = prompt_buffer,
        return_window   = return_window,
    }, { __index = Cmdfloat })
end

---@return string
function Cmdfloat:prompt()
    return vim.fn.prompt_getprompt(self.prompt_buffer)
end

---@return string
function Cmdfloat:current_line()
    return vim.api.nvim_buf_call(self.prompt_buffer, vim.api.nvim_get_current_line)
end

---@return string
function Cmdfloat:command()
    return self:current_line():sub(#self:prompt() + 1)
end

---@param command string
function Cmdfloat:set_command(command)
    vim.api.nvim_buf_call(self.prompt_buffer, function ()
        vim.api.nvim_set_current_line(self:prompt() .. command)
    end)
end

---@param index integer
function Cmdfloat:set_history_index(index)
    local max = vim.fn.histnr('cmd')
    if self.history_index == max then
        self.working_command = self:command()
    end
    if index > max then
        self.history_index = max
    elseif index < 0 then
        self.history_index = 0
    else
        self.history_index = index
    end
    if self.history_index == max then
        self:set_command(self.working_command)
    else
        self:set_command(vim.fn.histget('cmd', self.history_index + 1))
    end
end

function M.history_up()
    Cmdfloat.current():set_history_index(Cmdfloat.current().history_index - vim.v.count1)
end

function M.history_down()
    Cmdfloat.current():set_history_index(Cmdfloat.current().history_index + vim.v.count1)
end

function M.history_top()
    Cmdfloat.current():set_history_index(0)
end

function M.history_bottom()
    Cmdfloat.current():set_history_index(vim.fn.histnr('cmd'))
end

---@type fun(findstart: integer): integer|string[]
function vim.g.nvim_cmdfloat_omnifunc(findstart)
    local instance = Cmdfloat.current()
    if findstart == 1 then
        local cursor = vim.fn.col('.') - 1
        instance.omnifunc_lead = instance:current_line():sub(#instance:prompt() + 1, cursor)
        return cursor - #instance.omnifunc_lead:match('([a-zA-Z_]*)$')
    else
        return vim.fn.getcompletion(instance.omnifunc_lead, 'cmdline')
    end
end

---@type fun(options: CmdfloatOptions): vim.api.keyset.win_config
local function cmdfloat_window_config(options)
    local width = options.width or 0.6
    local position = options.position or 0.4
    return vim.tbl_deep_extend('keep', options.window_config or {}, {
        relative = 'editor',
        border   = options.border or 'rounded',
        row      = math.floor(vim.o.lines * position),
        col      = math.floor(vim.o.columns * (1 - width) / 2),
        width    = math.floor(vim.o.columns * width),
        height   = 1,
    })
end

---@param command string
local function execute_command(command)
    local ok, result = pcall(vim.api.nvim_exec2, command, { output = true })
    if ok then
        local lines = vim.split(result.output, '\r\n', { plain = true })
        local chunks = vim.tbl_map(function (line) return { line } end, lines)
        vim.api.nvim_echo(chunks, false --[[history]], {})
    else
        ---@diagnostic disable-next-line: param-type-mismatch
        vim.notify(result, vim.log.levels.ERROR)
    end
end

---@param options CmdfloatOptions
---@return integer buffer, integer window
local function create_cmdfloat_buffer_and_window(options)
    local buffer = vim.api.nvim_create_buf(false --[[listed]], true --[[scratch]])
    vim.bo[buffer].filetype  = 'vim'
    vim.bo[buffer].buftype   = 'prompt'
    vim.bo[buffer].bufhidden = 'delete'
    vim.bo[buffer].omnifunc  = 'v:lua.vim.g.nvim_cmdfloat_omnifunc'

    local window = vim.api.nvim_open_win(buffer, false --[[enter]], cmdfloat_window_config(options))
    vim.wo[window].number         = false
    vim.wo[window].relativenumber = false
    vim.wo[window].cursorline     = false

    vim.fn.prompt_setprompt(buffer, ':')
    vim.fn.prompt_setcallback(buffer, function (command)
        vim.api.nvim_buf_delete(buffer, { force = true })
        vim.fn.histadd('cmd', command)
        vim.schedule(function ()
            execute_command(command)
        end)
    end)
    return buffer, window
end

---@param options? CmdfloatOptions
function M.open(options)
    if not options then options = M.default_options end

    local buffer, window = create_cmdfloat_buffer_and_window(options)
    M.instances[buffer] = Cmdfloat.new(buffer, vim.api.nvim_get_current_win())

    ---@type fun(description: string, override?: vim.keymap.set.Opts): vim.keymap.set.Opts
    local function opts(description, override)
        return vim.tbl_deep_extend('force', { buffer = buffer, desc = 'nvim-cmdfloat: ' .. description }, override or {})
    end
    vim.keymap.set('n', 'gg', M.history_top, opts('History top'))
    vim.keymap.set('n', 'G', M.history_bottom, opts('History bottom'))
    vim.keymap.set('n', 'k', M.history_up, opts('History up'))
    vim.keymap.set('n', 'j', M.history_down, opts('History down'))
    vim.keymap.set({ 'n', 'i' }, '<up>', M.history_up, opts('History up'))
    vim.keymap.set({ 'n', 'i' }, '<down>', M.history_down, opts('History down'))
    vim.keymap.set('n', ':', ':', opts('Backup native command line'))
    vim.keymap.set('n', '<esc>', '<cmd>bwipeout!<cr>', opts('Close'))
    vim.keymap.set('i', '<tab>', 'pumvisible() ? "<c-n>" : "<c-x><c-o>"', opts('Next completion', { expr = true }))
    vim.keymap.set('i', '<s-tab>', 'pumvisible() ? "<c-p>" : "<s-tab>"', opts('Previous completion', { expr = true }))

    ---@type fun(event: string, description: string, callback: fun())
    local function autocmd(event, description, callback)
        vim.api.nvim_create_autocmd(event, {
            callback = callback,
            buffer   = buffer,
            desc     = 'nvim-cmdfloat: ' .. description,
        })
    end
    local previous_completeopt = vim.opt.completeopt
    autocmd('BufEnter', 'Set cmdfloat instance', function ()
        M.current_instance_buffer = buffer
        if options.completeopt then vim.opt.completeopt = options.completeopt end
    end)
    autocmd('BufLeave', 'Reset cmdfloat instance', function ()
        M.current_instance_buffer = nil
        if options.completeopt then vim.opt.completeopt = previous_completeopt end
    end)
    autocmd('BufWipeout', 'Clean up cmdfloat instance', function ()
        vim.api.nvim_set_current_win(M.instances[buffer].return_window)
        M.instances[buffer] = nil
    end)
    autocmd('VimResized', 'Resize cmdfloat window', function ()
        vim.api.nvim_win_set_config(window, cmdfloat_window_config(options))
    end)

    if options.on_buffer then options.on_buffer(buffer) end
    if options.on_window then options.on_window(window) end

    vim.api.nvim_set_current_win(window)
    vim.cmd.startinsert()
end

return M
