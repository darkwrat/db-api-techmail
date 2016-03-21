#!/usb/bin/env tarantool

box.cfg {
    log_level = 10,
}

local log = require('log')
local conn = require('mysql').connect({ host = localhost, user = 'root', password = '11', db = 'tempdb' })

--

local function get_forums_handler(req)
    log.info('What the hell is going on with our equipment?')

    local response_data = {
        code = 0,
        response = {
            hello = 'World!'
        }
    }

--    return response_data
    return req:render({ json = response_data })
end

local function hook_before_routes(self, req)
    log.info('Halo, Welt!')
    log.info(req)
end

local function hook_after_dispatch(req, resp)
    log.info('Auf wieder sehen, Welt!')
    resp.body = 'Stinky gremlin stole my json!'
end
--

local server = require('http.server').new('*', 8081)

server:route({ path = '/', method = 'GET' }, get_forums_handler)
server:hook('before_routes', hook_before_routes)
server:hook('after_dispatch', hook_after_dispatch)

server:start()
