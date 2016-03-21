#!/usb/bin/env tarantool

box.cfg {
    log_level = 10,
}

local log = require('log')
local conn = require('mysql').connect({ host = localhost, user = 'root', password = '11', db = 'tempdb' })

--

local function get_posts_handler(json_request)
    log.info('_handler')
    return {
        code = 0,
        request = json_request,
        response = conn:execute('select * from post where 1')
    }
end

--

local server = require('http.server').new('*', 8081)

server:route({ path = '/db/api/', method = 'GET' }, get_posts_handler)

server:hook('before_dispatch', function(self, request)
    log.info('_hook: before_dispatch')
    return pcall(request.json)
end)
server:hook('after_dispatch', function(self, request, request_override, response_data)
    log.info('_hook: after_dispatch')
    return request:render({ json = response_data })
end)

server:start()
