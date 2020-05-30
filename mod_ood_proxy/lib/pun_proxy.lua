local user_map    = require 'ood.user_map'
local proxy       = require 'ood.proxy'
local http        = require 'ood.http'
local nginx_stage = require 'ood.nginx_stage'
local os          = require 'os'
local io          = require 'io'

--[[
  pun_proxy_handler

  Maps an authenticated user to a system user. Then proxies user's traffic to
  user's backend PUN through a Unix domain socket. If the backend PUN is down,
  then launch the user's PUN through a redirect.
--]]
function pun_proxy_handler(r)
  -- read in OOD specific settings defined in Apache config
  local user_map_cmd    = r.subprocess_env['OOD_USER_MAP_CMD']
  local user_env        = r.subprocess_env['OOD_USER_ENV']
  local pun_socket_root = r.subprocess_env['OOD_PUN_SOCKET_ROOT']
  local nginx_uri       = r.subprocess_env['OOD_NGINX_URI']
  local map_fail_uri    = r.subprocess_env['OOD_MAP_FAIL_URI']
  local pun_stage_cmd   = r.subprocess_env['OOD_PUN_STAGE_CMD']
  local pun_max_retries = tonumber(r.subprocess_env['OOD_PUN_MAX_RETRIES'])

  -- io.write(r.subprocess_env['OIDC_id_token'])
  -- io.write(os.getenv("OIDC_access_token"))
  -- io.write(r.headers_in['OIDC_access_token'])
  -- io.write(r.headers_in['OIDC_access_token'])

  -- get the system-level user name
  local user = user_map.map(r, user_map_cmd, user_env and r.subprocess_env[user_env] or r.user)
  if not user then
    if map_fail_uri then
      return http.http302(r, map_fail_uri .. "?redir=" .. r:escape(r.unparsed_uri))
    else
      return http.http404(r, "failed to map user (" .. r.user .. ")")
    end
  end

  -- generate connection object used in setting the reverse proxy
  local conn = {}
  conn.user = user
  conn.socket = pun_socket_root .. "/" .. user .. "/passenger.sock"
  conn.uri = r.unparsed_uri

  -- start up PUN if socket doesn't exist
  local err = nil
  local count = 0

  -- try starting the PUN _ONCE_. multiple tries will just waste resources.
  if not r:stat(conn.socket) then

    -- dump the OIDC access token into a file that nginx_stage can
    -- use to retrieve the user's myproxy cert.
    -- well, at least it's got safe perms (0600)
    access_token = r.headers_in['OIDC_access_token']
    local tokenfn = os.tmpname()
    local f = assert(io.open(tokenfn, 'w+'))
    f:write(access_token, "\n", "safe to delete if more than a few mins old")
    f:close()

    local app_init_url = r.is_https and "https://" or "http://"
    app_init_url = app_init_url .. r.hostname .. ":" .. r.port .. nginx_uri .. "/init?redir=$http_x_forwarded_escaped_uri"
    -- generate user config & start PUN process
    err = nginx_stage.pun(r, pun_stage_cmd, user, app_init_url, tokenfn)

    while not r:stat(conn.socket) and count < pun_max_retries do
      r.usleep(1000000)
      count = count + 1
    end
  end

  -- unable to start up the PUN :(
  if err and count == pun_max_retries then
    if string.match(err, 'user doesn\'t exist') then
      err = user .. ' is not authorized to use the portal. For help, contact <contact>'
    end

    return http.http404(r, err)
  end

  -- setup request for reverse proxy
  proxy.set_reverse_proxy(r, conn)

  -- handle if backend server isn't completely started yet
  r:custom_response(502, nginx_uri .. "/noop?redir=" .. r:escape(r.unparsed_uri))

  -- let the proxy handler do this instead
  return apache2.DECLINED
end
