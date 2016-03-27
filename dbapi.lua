#!/usr/bin/env tarantool

box.cfg {}

local json = require('json')
local log = require('log')
local conn = require('mysql').connect({ host = localhost, user = 'root', password = '11', db = 'tempdb', raise = true })
local server = require('http.server').new('*', 8081)

-- -- --

local function keys_present(obj, keys)
    if not obj then
        return false
    end
    for _, key in pairs(keys) do
        if obj[key] == nil and obj[key] ~= json.null then
            return false, key
        elseif obj[key] == json.null then
            obj[key] = nil
        end
    end
    return true
end

local ResultCode = { Ok = 0, NotFound = 1, BadRequest = 2, MeaninglessRequest = 3, UnknownError = 4, UserExists = 5 }

local function create_response(response_code, response_data)
    return { code = response_code, response = response_data }
end

local function single_value(obj)
    if type(obj) ~= 'table' or table.getn(obj) ~= 1 then
        return nil
    end
    return obj[1]
end

local function fetch_user_details(user)
    local query = 'select u.email from userfollow uf join user u on '
    user.following = {}
    for _, v in pairs(conn:execute(query .. ' uf.followed_user_id = u.id where uf.follower_user_id = ?', user.id)) do
        table.insert(user.following, v.email)
    end
    user.followers = {}
    for _, v in pairs(conn:execute(query .. ' uf.follower_user_id = u.id where uf.followed_user_id = ?', user.id)) do
        table.insert(user.followers, v.email)
    end
    user.subscriptions = {} -- todo: index
    for _, v in pairs(conn:execute('select thread_id from usersubscription where user_id = ?', user.id)) do
        table.insert(user.subscriptions, v.thread_id)
    end
    return user
end

local function fetch_related(entity, related, foreign_key, other_key, is_single)
    is_single = is_single or false
    local query = 'select * from ' .. related .. ' where ' .. other_key .. ' = ?'
    local query_param = entity[foreign_key]
    if is_single then
        entity[related] = single_value(conn:execute(query, query_param))
    else
        entity[related] = {}
        for _, v in pairs(conn:execute(query, query_param)) do
            table.insert(entity[related], v)
        end
    end
    return entity
end

local function fetch_single_related(entity, related, foreign_key, other_key)
    return fetch_related(entity, related, foreign_key, other_key, true)
end

-- -- --

-- common
local api_common_clear -- https://github.com/andyudina/technopark-db-api/blob/master/doc/clear.md
local api_common_status -- https://github.com/andyudina/technopark-db-api/blob/master/doc/status.md

api_common_clear = function(args)
    conn:begin()
    conn:execute('set foreign_key_checks = 0')
    for _, v in pairs({ 'userfollow', 'usersubscription', 'post', 'thread', 'forum', 'user' }) do
        conn:execute('truncate table ' .. v)
    end
    conn:execute('set foreign_key_checks = 1')
    conn:commit()
    return create_response(ResultCode.Ok, 'OK')
end

api_common_status = function(args)
    -- todo: избавиться от count(*)
    local result = {}
    for _, v in pairs({ 'post', 'thread', 'forum', 'user' }) do
        result[v] = single_value(conn:execute('select count(*) as nrows from ' .. v)).nrows
    end
    return create_response(ResultCode.Ok, result)
end

server:route({ path = '/db/api/clear', method = 'POST' }, api_common_clear)
server:route({ path = '/db/api/status', method = 'GET' }, api_common_status)

-- user
local api_user_create -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/create.md
local api_user_details -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/details.md
local api_user_follow -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/follow.md
local api_user_list_followers -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/listFollowers.md
local api_user_list_following -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/listFollowing.md
local api_user_list_posts -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/listPosts.md
local api_user_unfollow -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/unfollow.md
local api_user_update_profile -- https://github.com/andyudina/technopark-db-api/blob/master/doc/user/updateProfile.md

api_user_create = function(args)
    if not keys_present(args.json, { 'username', 'about', 'name', 'email' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end

    conn:begin()
    if single_value(conn:execute('select 1 from user where email = ? limit 1', args.json.email)) then
        return create_response(ResultCode.UserExists, {})
    end
    conn:execute('insert into user(username, about, name, email, isAnonymous) values (?, ?, ?, ?, ?)',
        args.json.username, args.json.about, args.json.name, args.json.email, args.json.isAnonymous and 1 or 0)
    local inserted_id = single_value(conn:execute('select last_insert_id() as x')).x
    conn:commit()
    return create_response(ResultCode.Ok, single_value(conn:execute('select * from user where id = ?', inserted_id)))
end

api_user_details = function(args)
    if not keys_present(args.query_params, { 'user' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local user = single_value(conn:execute('select * from user where email = ?', args.query_params.user))
    if not user then
        return create_response(ResultCode.NotFound, 'user')
    end
    fetch_user_details(user)
    return create_response(ResultCode.Ok, user)
end

api_user_follow = function(args)
    if not keys_present(args.json, { 'follower', 'followee' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local query = 'select * from user where email = ?'
    local follower_user = single_value(conn:execute(query, args.json.follower))
    local followed_user = single_value(conn:execute(query, args.json.followee))
    if not follower_user or not followed_user then
        return create_response(ResultCode.NotFound, 'follower_user')
    end
    conn:execute('insert into userfollow (follower_user_id, followed_user_id) values (?, ?)', follower_user.id, followed_user.id)
    fetch_user_details(follower_user)
    return create_response(ResultCode.Ok, follower_user)
end

api_user_list_followers = function(args)
    if not keys_present(args.query_params, { 'user' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local followed_user = single_value(conn:execute('select * from user where email = ?', args.query_params.user))
    if not followed_user then
        return create_response(ResultCode.NotFound, 'followed_user')
    end
    local followers_query = 'select * from user where id in ('
    local follower_id_query = 'select follower_user_id from userfollow where followed_user_id = ?'
    local since_id = tonumber(args.query_params.since_id)
    if since_id then
        follower_id_query = follower_id_query .. ' and follower_user_id >= ' .. since_id
    end
    for _, v in pairs(conn:execute(follower_id_query, followed_user.id)) do
        followers_query = followers_query .. v.follower_user_id .. ','
    end
    followers_query = followers_query .. '0)'
    -- fixme: sql injection
    if args.query_params.order then
        followers_query = followers_query .. ' order by name ' .. args.query_params.order
    end
    -- fixme: sql injection
    if args.query_params.limit then
        followers_query = followers_query .. ' limit ' .. args.query_params.limit
    end
--    log.info(followers_query)
    local users = {}
    for _, v in pairs(conn:execute(followers_query)) do
        fetch_user_details(v)
        table.insert(users, v)
    end
    return create_response(ResultCode.Ok, users)
end

api_user_list_following = function(args)
    if not keys_present(args.query_params, { 'user' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local following_user = single_value(conn:execute('select * from user where email = ?', args.query_params.user))
    if not following_user then
        return create_response(ResultCode.NotFound, 'follower_user')
    end
    local followees_query = 'select * from user where id in ('
    local followee_id_query = 'select followed_user_id from userfollow where follower_user_id = ?'
    local since_id = tonumber(args.query_params.since_id)
    if since_id then
        followee_id_query = followee_id_query .. ' and followed_user_id >= ' .. since_id
    end
    for _, v in pairs(conn:execute(followee_id_query, following_user.id)) do
        followees_query = followees_query .. v.followed_user_id .. ','
    end
    followees_query = followees_query .. '0)'
    -- fixme: sql injection
    if args.query_params.order then
        followees_query = followees_query .. ' order by name ' .. args.query_params.order
    end
    -- fixme: sql injection
    if args.query_params.limit then
        followees_query = followees_query .. ' limit ' .. args.query_params.limit
    end
--    log.info(followees_query)
    local users = {}
    for _, v in pairs(conn:execute(followees_query)) do
        fetch_user_details(v)
        table.insert(users, v)
    end
    return create_response(ResultCode.Ok, users)
end

api_user_unfollow = function(args)
    if not keys_present(args.json, { 'follower', 'followee' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local query = 'select * from user where email = ?'
    local follower_user = single_value(conn:execute(query, args.json.follower))
    local followed_user = single_value(conn:execute(query, args.json.followee))
    if not follower_user or not followed_user then
        return create_response(ResultCode.NotFound, { 'follower_user', 'followed_user' })
    end
    conn:execute('delete from userfollow where follower_user_id = ? and followed_user_id = ?', follower_user.id, followed_user.id)
    fetch_user_details(follower_user)
    return create_response(ResultCode.Ok, follower_user)
end

api_user_update_profile = function(args)
    if not keys_present(args.json, { 'about', 'user', 'name' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    conn:execute('update user set about = ?, name = ? where email = ?', args.json.about, args.json.name, args.json.user)
    local user = single_value(conn:execute('select * from user where email = ?', args.json.user))
    if not user then
        return create_response(ResultCode.NotFound, 'user')
    end
    fetch_user_details(user)
    return create_response(ResultCode.Ok, user)
end

api_user_list_posts = function(args)
    if not keys_present(args.query_params, { 'user' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local user = single_value(conn:execute('select id,email from user where email = ?', args.query_params.user))
    if not user then
        return create_response(ResultCode.NotFound, 'user')
    end
    local posts_query = 'select p.*, p.thread_id as thread, p.parent_post_id as parent, '
            .. ' p.likes - p.dislikes as points, u.email as user, f.short_name as forum '
            .. ' from post p join user u on p.user_id = u.id '
            .. ' join forum f on p.forum_id = f.id '
            .. ' where u.id = ? '
    if args.query_params.since then
        posts_query = posts_query .. ' and p.date >= \'' .. conn:quote(args.query_params.since) .. '\' '
    end
    posts_query = posts_query .. ' order by p.date '
    if args.query_params.order then
        posts_query = posts_query .. ' ' .. conn:quote(args.query_params.order) .. ' '
    else
        posts_query = posts_query .. ' desc '
    end
    if args.query_params.limit then
        posts_query = posts_query .. ' limit ' .. conn:quote(args.query_params.limit) .. ' '
    end
    local posts = conn:execute(posts_query, user.id)
    return create_response(ResultCode.Ok, posts)
end

server:route({ path = '/db/api/user/create', method = 'POST' }, api_user_create)
server:route({ path = '/db/api/user/details', method = 'GET' }, api_user_details)
server:route({ path = '/db/api/user/follow', method = 'POST' }, api_user_follow)
server:route({ path = '/db/api/user/listFollowers', method = 'GET' }, api_user_list_followers)
server:route({ path = '/db/api/user/listFollowing', method = 'GET' }, api_user_list_following)
server:route({ path = '/db/api/user/listPosts', method = 'GET' }, api_user_list_posts)
server:route({ path = '/db/api/user/unfollow', method = 'POST' }, api_user_unfollow)
server:route({ path = '/db/api/user/updateProfile', method = 'POST' }, api_user_update_profile)

-- forum
local api_forum_create -- https://github.com/andyudina/technopark-db-api/blob/master/doc/forum/create.md
local api_forum_details -- https://github.com/andyudina/technopark-db-api/blob/master/doc/forum/details.md
local api_forum_list_posts -- https://github.com/andyudina/technopark-db-api/blob/master/doc/forum/listPosts.md
local api_forum_list_threads -- https://github.com/andyudina/technopark-db-api/blob/master/doc/forum/listThreads.md
local api_forum_list_users -- https://github.com/andyudina/technopark-db-api/blob/master/doc/forum/listUsers.md

api_forum_create = function(args)
    if not keys_present(args.json, { 'name', 'short_name', 'user' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end

    conn:begin()
    local forum = single_value(conn:execute('select 1 from forum where short_name = ?', args.json.short_name))
    if forum then
        return create_response(ResultCode.Ok, forum)
    end
    local user = single_value(conn:execute('select id from user where email = ?', args.json.user))
    if not user then
        return create_response(ResultCode.NotFound, 'user')
    end
    conn:execute('insert into forum (name, short_name, user_id) values (?, ?, ?)', args.json.name, args.json.short_name, user.id)
    forum = single_value(conn:execute('select * from forum where id = last_insert_id()'))
    conn:commit()
    forum['user_id'] = nil
    forum['user'] = args.json.user
    return create_response(ResultCode.Ok, forum)
end

api_forum_details = function(args)
    if not keys_present(args.query_params, { 'forum' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end

    local forum = single_value(conn:execute('select * from forum where short_name = ?', args.query_params.forum))
    if not forum then
        return create_response(ResultCode.NotFound, 'forum')
    end
    if args.query_params.related ~= nil then
        local related_keys = {}
        if type(args.query_params.related) == 'string' then
            table.insert(related_keys, args.query_params.related)
        else
            related_keys = args.query_params.related
        end
        for _, v in pairs(related_keys) do
            if v == 'user' then
                fetch_single_related(forum, 'user', 'user_id', 'id')
            else
                return create_response(ResultCode.MeaninglessRequest, {})
            end
        end
    end
    return create_response(ResultCode.Ok, forum)
end

api_forum_list_users = function(args)
    if not keys_present(args.query_params, { 'forum' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local forum = single_value(conn:execute('select id, short_name from forum where short_name = ?', args.query_params.forum))
    if not forum then
        return create_response(ResultCode.NotFound, 'forum')
    end
    local users_query = 'select distinct u.* from post p join forum f on p.forum_id = f.id join user u on p.user_id = u.id where f.id = ? '
    -- fixme: sql injection
    if args.query_params.since_id then
        users_query = users_query .. ' and u.id >= ' .. args.query_params.since_id
    end
    users_query = users_query .. ' order by name '
    -- fixme: sql injection
    if args.query_params.order then
        users_query = users_query .. ' ' .. args.query_params.order .. ' '
    end
    if args.query_params.limit then
        users_query = users_query .. ' limit ' .. args.query_params.limit .. ' '
    end
    local users = conn:execute(users_query, forum.id)
    for _, v in pairs(users) do
        fetch_user_details(v)
    end
    return create_response(ResultCode.Ok, users)
end

api_forum_list_threads = function(args)
    if not keys_present(args.query_params, { 'forum' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local forum = single_value(conn:execute('select id,short_name from forum where short_name = ?', args.query_params.forum))
    if not forum then
        return create_response(ResultCode.NotFound, 'forum')
    end
    local threads_query = ' select t.*, u.email as user, count(*) as posts, f.short_name as forum, cast(t.likes - t.dislikes as signed) as points '
            .. ' from thread t '
            .. ' join user u on t.user_id = u.id '
            .. ' join forum f on t.forum_id = f.id '
            .. ' left join post p on t.id = p.thread_id '
            .. ' where t.forum_id = ? '
    if args.query_params.since then
        threads_query = threads_query .. ' and t.date > \'' .. conn:quote(args.query_params.since) .. '\' '
    end
    threads_query = threads_query .. ' group by t.id order by t.date '
    if args.query_params.order then
        threads_query = threads_query .. ' ' .. conn:quote(args.query_params.order) .. ' '
    else
        threads_query = threads_query .. ' desc '
    end
    if args.query_params.limit then
        threads_query = threads_query .. ' limit ' .. conn:quote(args.query_params.limit)
    end
    log.info(threads_query)
    local threads = conn:execute(threads_query, forum.id)
    if args.query_params.related ~= nil then
        for _, thread in pairs(threads) do
            local related_keys = {}
            if type(args.query_params.related) == 'string' then
                table.insert(related_keys, args.query_params.related)
            else
                related_keys = args.query_params.related
            end
            for _, v in pairs(related_keys) do
                if v == 'user' then
                    fetch_single_related(thread, 'user', 'user_id', 'id')
                    fetch_user_details(thread.user)
                elseif v == 'forum' then
                    fetch_single_related(thread, 'forum', 'forum_id', 'id')
                    -- todo: убрать подпорку
                    thread.forum.user = single_value(conn:execute('select id,email from user where id = ?', thread.forum.user_id)).email
                else
                    return create_response(ResultCode.MeaninglessRequest, {})
                end
            end
        end
    end
    return create_response(ResultCode.Ok, threads)
end

api_forum_list_posts = function(args)
    if not keys_present(args.query_params, { 'forum' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local forum = single_value(conn:execute('select id,short_name from forum where short_name = ?', args.query_params.forum))
    if not forum then
        return create_response(ResultCode.NotFound, 'forum')
    end
    local posts_query = 'select p.*, p.thread_id as thread, p.parent_post_id as parent, '
            .. ' p.likes - p.dislikes as points, u.email as user, f.short_name as forum '
            .. ' from post p join user u on p.user_id = u.id '
            .. ' join forum f on p.forum_id = f.id '
            .. ' where f.id = ? '
    if args.query_params.since then
        posts_query = posts_query .. ' and p.date >= \'' .. conn:quote(args.query_params.since) .. '\' '
    end
    posts_query = posts_query .. ' order by p.date '
    if args.query_params.order then
        posts_query = posts_query .. ' ' .. conn:quote(args.query_params.order) .. ' '
    else
        posts_query = posts_query .. ' desc '
    end
    if args.query_params.limit then
        posts_query = posts_query .. ' limit ' .. conn:quote(args.query_params.limit) .. ' '
    end
    local posts = conn:execute(posts_query, forum.id)
    if args.query_params.related ~= nil then
        for _, post in pairs(posts) do
            local related_keys = {}
            if type(args.query_params.related) == 'string' then
                table.insert(related_keys, args.query_params.related)
            else
                related_keys = args.query_params.related
            end
            for _, v in pairs(related_keys) do
                if v == 'user' then
                    fetch_single_related(post, 'user', 'user_id', 'id')
                    fetch_user_details(post.user)
                elseif v == 'forum' then
                    fetch_single_related(post, 'forum', 'forum_id', 'id')
                    -- todo: убрать подпорку
                    post.forum.user = single_value(conn:execute('select id,email from user where id = ?', post.forum.user_id)).email
                elseif v == 'thread' then
                    fetch_single_related(post, 'thread', 'thread_id', 'id')
                    -- todo: убрать подпорки
                    post.thread.user = single_value(conn:execute('select id,email from user where id = ?', post.thread.user_id)).email
                    post.thread.forum = forum.short_name
                    post.thread.posts = single_value(
                        conn:execute('select count(*) as nposts from post where not isDeleted and thread_id = ?', post.thread.id)
                    ).nposts
                    post.thread.points = post.thread.likes - post.thread.dislikes
                else
                    return create_response(ResultCode.MeaninglessRequest, {})
                end
            end
        end
    end
    return create_response(ResultCode.Ok, posts)
end

server:route({ path = '/db/api/forum/create', method = 'POST' }, api_forum_create)
server:route({ path = '/db/api/forum/details', method = 'GET' }, api_forum_details)
server:route({ path = '/db/api/forum/listPosts', method = 'GET' }, api_forum_list_posts)
server:route({ path = '/db/api/forum/listThreads', method = 'GET' }, api_forum_list_threads)
server:route({ path = '/db/api/forum/listUsers', method = 'GET' }, api_forum_list_users)

-- thread
local api_thread_create -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/create.md
local api_thread_details -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/details.md
local api_thread_close -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/close.md
local api_thread_list -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/list.md
local api_thread_list_posts -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/listPosts.md
local api_thread_open -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/open.md
local api_thread_remove -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/remove.md
local api_thread_restore -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/restore.md
local api_thread_subscribe -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/subscribe.md
local api_thread_unsubscribe -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/unsubscribe.md
local api_thread_update -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/update.md
local api_thread_vote -- https://github.com/andyudina/technopark-db-api/blob/master/doc/thread/vote.md

api_thread_create = function(args)
    local keys_ok, key_missing = keys_present(args.json, { 'forum', 'title', 'isClosed', 'user', 'date', 'message', 'slug' })
    if not keys_ok then
        return create_response(ResultCode.MeaninglessRequest, key_missing)
    end
    conn:begin()
    local user = single_value(conn:execute('select id from user where email = ?', args.json.user))
    if not user then
        conn:rollback()
        return create_response(ResultCode.NotFound, 'user')
    end
    local forum = single_value(conn:execute('select id, short_name from forum where short_name = ?', args.json.forum))
    if not forum then
        conn:rollback()
        return create_response(ResultCode.NotFound, 'forum')
    end
    conn:execute('insert into thread (forum_id, title, isClosed, user_id, date, message, slug, isDeleted) values (?,?,?,?,?,?,?,?)',
        forum.id, args.json.title, args.json.isClosed, user.id, args.json.date, args.json.message,
        args.json.slug, args.json.isDeleted and 1 or 0)
    local thread = single_value(conn:execute('select * from thread where id = last_insert_id()'))
    conn:commit()
    thread.user_id = nil
    thread.user = args.json.email
    thread.forum_id = nil
    thread.forum = forum.short_name
    return create_response(ResultCode.Ok, thread)
end

api_thread_details = function(args)
    if not keys_present(args.query_params, { 'thread' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local thread = single_value(conn:execute('select * from thread where id = ?', args.query_params.thread))
    if not thread then
        return create_response(ResultCode.NotFound, 'thread')
    end
    -- todo: remove copy&paste
    if args.query_params.related ~= nil then
        local related_keys = {}
        if type(args.query_params.related) == 'string' then
            table.insert(related_keys, args.query_params.related)
        else
            related_keys = args.query_params.related
        end
        for _, v in pairs(related_keys) do
            if v == 'user' then
                fetch_single_related(thread, 'user', 'user_id', 'id')
            elseif v == 'forum' then
                fetch_single_related(thread, 'forum', 'forum_id', 'id')
                local forum_user = single_value(conn:execute('select email from user where id = ?', thread.forum.user_id))
                if not forum_user then
                    return create_response(ResultCode.NotFound, 'thread_forum_user')
                end
                thread.forum.user = forum_user.email
            else
                return create_response(ResultCode.MeaninglessRequest, {})
            end
        end
    end
    thread.posts = single_value(
        conn:execute('select count(*) as nposts from post where not isDeleted and thread_id = ?', thread.id)
    ).nposts
    -- todo: переформулировать схему базы и убрать эти подпорки
    if not thread.user then
        thread.user = single_value(conn:execute('select email from user where id = ?', thread.user_id)).email
    end
    if not thread.forum then
        thread.forum = single_value(conn:execute('select short_name from forum where id = ?', thread.forum_id)).short_name
    end
    thread.points = thread.likes - thread.dislikes
    return create_response(ResultCode.Ok, thread)
end

api_thread_close = function(args)
    -- todo: убрать copy&paste
    if not keys_present(args.json, { 'thread' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    conn:begin()
    local thread = single_value(conn:execute('select 1 from thread where id = ?', args.json.thread))
    if not thread then
        return create_response(ResultCode.NotFound, 'thread')
    end
    conn:execute('update thread set isClosed = 1 where id = ?', args.json.thread)
    conn:commit()
    return create_response(ResultCode.Ok, { thread = thread.id })
end

api_thread_open = function(args)
    -- todo: убрать copy&paste
    if not keys_present(args.json, { 'thread' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    conn:begin()
    local thread = single_value(conn:execute('select id from thread where id = ?', args.json.thread))
    if not thread then
        return create_response(ResultCode.NotFound, 'thread')
    end
    conn:execute('update thread set isClosed = 0 where id = ?', args.json.thread)
    conn:commit()
    return create_response(ResultCode.Ok, { thread = thread.id })
end

api_thread_remove = function(args)
    -- todo: убрать copy&paste
    if not keys_present(args.json, { 'thread' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    conn:begin()
    local thread = single_value(conn:execute('select id from thread where id = ?', args.json.thread))
    if not thread then
        return create_response(ResultCode.NotFound, 'thread')
    end
    conn:execute('update post set isDeleted = 1 where thread_id = ?', thread.id)
    conn:execute('update thread set isDeleted = 1 where id = ?', thread.id)
    conn:commit()
    return create_response(ResultCode.Ok, { thread = thread.id })
end

api_thread_restore = function(args)
    -- todo: убрать copy&paste
    if not keys_present(args.json, { 'thread' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    conn:begin()
    local thread = single_value(conn:execute('select id from thread where id = ?', args.json.thread))
    if not thread then
        return create_response(ResultCode.NotFound, 'thread')
    end
    conn:execute('update post set isDeleted = 0 where thread_id = ?', thread.id)
    conn:execute('update thread set isDeleted = 0 where id = ?', thread.id)
    conn:commit()
    return create_response(ResultCode.Ok, { thread = thread.id })
end

api_thread_subscribe = function(args)
    -- todo: remove copy&paste
    if not keys_present(args.json, { 'user', 'thread' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local user = single_value(conn:execute('select id,email from user where email = ?', args.json.user))
    if not user then
        return create_response(ResultCode.NotFound, "user")
    end
    local thread = single_value(conn:execute('select id from thread where id = ?', args.json.thread))
    if not thread then
        return create_response(ResultCode.NotFound, "thread")
    end
    -- todo: пересмотреть
    pcall(function()
        conn:execute('insert into usersubscription (user_id, thread_id) values (?, ?)', user.id, thread.id)
    end)
    return create_response(ResultCode.Ok, { thread = thread.id, user = user.email })
end

api_thread_unsubscribe = function(args)
    -- todo: remove copy&paste
    if not keys_present(args.json, { 'user', 'thread' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local user = single_value(conn:execute('select id,email from user where email = ?', args.json.user))
    if not user then
        return create_response(ResultCode.NotFound, "user")
    end
    local thread = single_value(conn:execute('select id from thread where id = ?', args.json.thread))
    if not thread then
        return create_response(ResultCode.NotFound, "thread")
    end
    -- todo: пересмотреть
    pcall(function()
        conn:execute('delete from usersubscription where user_id = ? and thread_id = ?', user.id, thread.id)
    end)
    return create_response(ResultCode.Ok, { thread = thread.id, user = user.email })
end

api_thread_update = function(args)
    if not keys_present(args.json, { 'message', 'slug', 'thread' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    conn:begin()
    if not single_value(conn:execute('select 1 from thread where id = ?', args.json.thread)) then
        return create_response(ResultCode.NotFound, 'thread')
    end
    conn:execute('update thread set message = ?, slug = ? where id = ?', args.json.message, args.json.slug, args.json.thread)
    local thread = single_value(conn:execute('select * from thread where id = ?', args.json.thread))
    if not thread then
        error('oops O_o')
    end
    local user = single_value(conn:execute('select id,email from user where id = ?', thread.user_id))
    if not user then
        error('oops O_o x2')
    end
    conn:commit()
    thread.user_id = nil
    thread.user = user.email
    return create_response(ResultCode.Ok, thread)
end

api_thread_vote = function(args)
    if not keys_present(args.json, { 'vote', 'thread' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local thread = single_value(conn:execute('select id from thread where id = ?', args.json.thread))
    if not thread then
        return create_response(ResultCode.NotFound, 'thread')
    end
    if tonumber(args.json.vote) == 1 then
        conn:execute('update thread set likes = likes + 1 where id = ?', thread.id)
    elseif tonumber(args.json.vote) == -1 then
        conn:execute('update thread set dislikes = dislikes + 1 where id = ?', thread.id)
    else
        return create_response(ResultCode.MeaninglessRequest, 'vote')
    end
    local updated_thread = single_value(conn:execute('select * from thread where id = ?', thread.id))
    updated_thread.forum = single_value(conn:execute('select short_name from forum where id = ?', updated_thread.forum_id)).short_name
    updated_thread.user = single_value(conn:execute('select email from user where id = ?', updated_thread.user_id)).email
    return create_response(ResultCode.Ok, updated_thread)
end

server:route({ path = '/db/api/thread/create', method = 'POST' }, api_thread_create)
server:route({ path = '/db/api/thread/details', method = 'GET' }, api_thread_details)
server:route({ path = '/db/api/thread/close', method = 'POST' }, api_thread_close)
--server:route({ path = '/db/api/thread/list', method = 'GET' }, api_thread_list)
--server:route({ path = '/db/api/thread/listPosts', method = 'GET' }, api_thread_list_posts)
server:route({ path = '/db/api/thread/open', method = 'POST' }, api_thread_open)
server:route({ path = '/db/api/thread/remove', method = 'POST' }, api_thread_remove)
server:route({ path = '/db/api/thread/restore', method = 'POST' }, api_thread_restore)
server:route({ path = '/db/api/thread/subscribe', method = 'POST' }, api_thread_subscribe)
server:route({ path = '/db/api/thread/unsubscribe', method = 'POST' }, api_thread_unsubscribe)
server:route({ path = '/db/api/thread/update', method = 'POST' }, api_thread_update)
server:route({ path = '/db/api/thread/vote', method = 'POST' }, api_thread_vote)

-- post
local api_post_create -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/create.md
local api_post_details -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/details.md
local api_post_list -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/list.md
local api_post_remove -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/remove.md
local api_post_restore -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/restore.md
local api_post_update -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/update.md
local api_post_vote -- https://github.com/andyudina/technopark-db-api/blob/master/doc/post/vote.md

api_post_create = function(args)
    if not keys_present(args.json, { 'date', 'thread', 'message', 'user', 'forum' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local thread = single_value(conn:execute('select id from thread where id = ?', args.json.thread))
    if not thread then
        return create_response(ResultCode.NotFound, 'thread')
    end
    local forum = single_value(conn:execute('select id,short_name from forum where short_name = ?', args.json.forum))
    if not forum then
        return create_response(ResultCode.NotFound, 'forum')
    end
    local user = single_value(conn:execute('select id,email from user where email = ?', args.json.user))
    if not user then
        return create_response(ResultCode.NotFound, 'user')
    end
    local parent_post = {}
    if type(args.json.parent) == 'number' and args.json.parent > 0 then
        parent_post = single_value(conn:execute('select id from post where id = ?', args.json.parent))
        if not parent_post then
            return create_response(ResultCode.NotFound, 'parent')
        end
    end
    conn:begin()
    conn:execute('insert into post(date, thread_id, message, user_id, forum_id, parent_post_id,' ..
            ' isApproved, isHighlighted, isEdited, isSpam, isDeleted) values(?,?,?,?,?,?,?,?,?,?,?)',
        args.json.date, thread.id, args.json.message, user.id, forum.id, parent_post.id,
        args.json.isApproved and 1 or 0, args.json.isHighlighted and 1 or 0,
        args.json.isEdited and 1 or 0, args.json.isSpam and 1 or 0, args.json.isDeleted and 1 or 0)
    local post = single_value(conn:execute('select * from post where id = last_insert_id()'))
    conn:commit()
    post.parent = post.parent_post_id
    post.parent_post_id = nil
    post.forum = forum.short_name
    post.user = user.email
    return create_response(ResultCode.Ok, post)
end

api_post_details = function(args)
    if not keys_present(args.query_params, { 'post' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local post = single_value(conn:execute('select * from post where id = ?', args.query_params.post))
    if not post then
        return create_response(ResultCode.NotFound, 'post')
    end
    post.parent = post.parent_post_id
    post.parent_post_id = nil
    -- todo: remove copy&paste
    if args.query_params.related then
        local related_keys = {}
        if type(args.query_params.related) == 'string' then
            table.insert(related_keys, args.query_params.related)
        else
            related_keys = args.query_params.related
        end
        log.info(table.concat(related_keys, ','))
        for _, v in pairs(related_keys) do
            if v == 'user' then
                fetch_single_related(post, 'user', 'user_id', 'id')
                post.user_id = nil
            elseif v == 'thread' then
                fetch_single_related(post, 'thread', 'thread_id', 'id')
                post.thread_id = nil
            elseif v == 'forum' then
                fetch_single_related(post, 'forum', 'forum_id', 'id')
                post.forum_id = nil
            else
                return create_response(ResultCode.MeaninglessRequest, {})
            end
        end
        for _, v in pairs(related_keys) do
            if v == 'thread' then
                local thread_user = single_value(conn:execute('select email from user where id = ?', post.thread.user_id))
                if not thread_user then
                    return create_response(ResultCode.NotFound, 'post_thread_user')
                end
                post.thread.user = thread_user.email
                post.thread.user_id = nil
                local thread_forum = single_value(conn:execute('select short_name from forum where id = ?', post.thread.forum_id))
                if not thread_forum then
                    return create_response(ResultCode.NotFound, 'post_thread_user')
                end
                post.thread.forum = thread_forum.short_name
                post.thread.forum_id = nil
                post.thread.posts = single_value(
                    conn:execute('select count(*) as nposts from post where not isDeleted and thread_id = ?', post.thread.id)
                ).nposts
                post.thread.points = post.thread.likes - post.thread.dislikes
            elseif v == 'forum' then
                local forum_user = single_value(conn:execute('select email from user where id = ?', post.forum.user_id))
                if not forum_user then
                    return create_response(ResultCode.NotFound, 'post_forum_user')
                end
                post.forum.user = forum_user.email
                post.forum.user_id = nil
            end
        end
    end
    -- todo: переформулировать схему базы, убрать подпорки
    if not post.user then
        post.user = single_value(conn:execute('select email from user where id = ?', post.user_id)).email
    end
    if not post.thread then
        post.thread = post.thread_id
    end
    if not post.forum then
        post.forum = single_value(conn:execute('select short_name from forum where id = ?', post.forum_id)).short_name
    end
    post.points = post.likes - post.dislikes
    return create_response(ResultCode.Ok, post)
end

api_post_remove = function(args)
    if not keys_present(args.json, { 'post' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local post = single_value(conn:execute('select id from post where id = ?', args.json.post))
    if not post then
        return create_response(ResultCode.NotFound, {})
    end
    conn:execute('update post set isDeleted = 1 where id = ?', post.id)
    return create_response(ResultCode.Ok, { post = post.id })
end

api_post_restore = function(args)
    if not keys_present(args.json, { 'post' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local post = single_value(conn:execute('select id from post where id = ?', args.json.post))
    if not post then
        return create_response(ResultCode.NotFound, {})
    end
    conn:execute('update post set isDeleted = 0 where id = ?', post.id)
    return create_response(ResultCode.Ok, { post = post.id })
end

api_post_update = function(args)
    if not keys_present(args.json, { 'post', 'message' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local post = single_value(conn:execute('select id from post where id = ?', args.json.post))
    if not post then
        return create_response(ResultCode.NotFound, 'post')
    end
    conn:execute('update post set message = ? where id = ?', args.json.message, post.id)
    local updated_post = single_value(conn:execute('select * from post where id = ?', post.id))
    -- todo: убрать подпорки
    updated_post.forum = single_value(conn:execute('select short_name from forum where id = ?', updated_post.forum_id)).short_name
    updated_post.user = single_value(conn:execute('select email from user where id = ?', updated_post.forum_id)).email
    updated_post.thread = updated_post.thread_id
    return create_response(ResultCode.Ok, updated_post)
end

api_post_vote = function(args)
    if not keys_present(args.json, { 'vote', 'post' }) then
        return create_response(ResultCode.MeaninglessRequest, {})
    end
    local post = single_value(conn:execute('select id from post where id = ?', args.json.post))
    if not post then
        return create_response(ResultCode.NotFound, 'post')
    end
    if tonumber(args.json.vote) == 1 then
        conn:execute('update post set likes = likes + 1 where id = ?', post.id)
    elseif tonumber(args.json.vote) == -1 then
        conn:execute('update post set dislikes = dislikes + 1 where id = ?', post.id)
    else
        return create_response(ResultCode.MeaninglessRequest, 'vote')
    end
    local updated_post = single_value(conn:execute('select * from post where id = ?', post.id))
    -- todo: убрать подпорки
    updated_post.forum = single_value(conn:execute('select short_name from forum where id = ?', updated_post.forum_id)).short_name
    updated_post.user = single_value(conn:execute('select email from user where id = ?', updated_post.forum_id)).email
    updated_post.thread = updated_post.thread_id
    return create_response(ResultCode.Ok, updated_post)
end

server:route({ path = '/db/api/post/create', method = 'POST' }, api_post_create)
server:route({ path = '/db/api/post/details', method = 'GET' }, api_post_details)
--server:route({ path = '/db/api/post/list', method = 'GET' }, api_post_list)
server:route({ path = '/db/api/post/remove', method = 'POST' }, api_post_remove)
server:route({ path = '/db/api/post/restore', method = 'POST' }, api_post_restore)
server:route({ path = '/db/api/post/update', method = 'POST' }, api_post_update)
server:route({ path = '/db/api/post/vote', method = 'POST' }, api_post_vote)

-- -- --

server:hook('before_dispatch', function(self, request)
    local obj = {}
    if request.method ~= 'GET' then
        local status, err = pcall(function() obj.json = request:json() end)
        if not obj.json then
            obj.response = create_response(ResultCode.BadRequest, err)
        end
    else
        obj.query_params = request:query_param(nil)
    end
    return obj
end)
server:hook('after_handler_error', function(self, request, request_override, err)
    return create_response(ResultCode.UnknownError, err)
end)
server:hook('after_dispatch', function(self, request, request_override, response_data)
    return request:render({ json = response_data })
end)

server:start()
