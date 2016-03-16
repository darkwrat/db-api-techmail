#!/usb/bin/env tarantool

box.cfg {}

local conn = require('mysql').connect({ host = localhost, user = 'root', password = '11', db = 'tempdb' })

--

local function get_forums_handler(self)
    if self.method ~= 'GET' then
        return { status = 504 }
    end

    local response_data = {
        code = 0,
        response = conn:execute('select * from forum where 1')
    }

    return self:render({ json = response_data })
end

--

local server = require('http.server').new('*', 8081)

server:route({ path = '/' }, get_forums_handler)

server:start()
