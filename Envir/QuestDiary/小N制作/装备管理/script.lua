-- LUA脚本
local mir = require"mir"
local ffi = require"ffi"
local string = require"string"
local table = require"table"
local math = require"math"

local ffi_cast = ffi.cast
local ffi_str = ffi.string
local str_fmt = string.format
local unpack = unpack or table.unpack
local tinsert = table.insert
local iif = mir.iif
-- local _p = mir.printf

local _M = {
  max_record_useritem_nr = 15
}

local function res_to_list(res)
  assert(res:is_array())
  local out = {}
  local elem = res:array_next_elem()
  while elem ~= nil do
    if elem:is_null() then
      tinsert(out, nil)
    else
      tinsert(out, elem:to_string())
    end
    elem = res:array_next_elem()
  end
  return out
end

function _M.add_record(params)
  local index = tonumber(params.s3)

  local player = ffi_cast("TPlayObject*", params.player)
  local uid = mir.player_get_uid(params.player)
  local db = mir.vedis_db

  local useritem = player.useritems[index - 1]
  if useritem.make_index > 0 then
    local stditem = mir.get_stditem_by_idx(useritem.index)
    db:exec("BEGIN")
    db:execute("HMSET u_uir:%s i%d %d n%d \"%s\"",
                uid, index, useritem.make_index,
                index, ffi_str(stditem.name))
    db:exec("COMMIT")
  end
end

function _M.del_record(params)
  local index = tonumber(params.s3)

  local uid = mir.player_get_uid(params.player)
  local db = mir.vedis_db

  db:exec("BEGIN")
  db:execute("HDEL u_uir:%s i%d n%d", uid, index, index)
  db:exec("COMMIT")
end

function _M.clear_all(params)
  local uid = mir.player_get_uid(params.player)
  local db = mir.vedis_db

  db:exec("BEGIN")
  for index = 1, _M.max_record_useritem_nr do
    db:execute("HDEL u_uir:%s i%d n%d", uid, index, index)
  end
  db:exec("COMMIT")
end

function _M.record_all(params)
  local player = ffi_cast("TPlayObject*", params.player)
  local uid = mir.player_get_uid(params.player)
  local db = mir.vedis_db

  local useritems = player.useritems
  db:exec("BEGIN")
  for index = 1, math.min(mir.C.U_SWEAPON + 1, _M.max_record_useritem_nr) do
    local useritem = useritems[index - 1]
    if useritem.make_index > 0 then
      local stditem = mir.get_stditem_by_idx(useritem.index)
      db:execute("HMSET u_uir:%s i%d %d n%d \"%s\"",
                  uid, index, useritem.make_index,
                  index, ffi_str(stditem.name))
    end
  end
  db:exec("COMMIT")
end

function _M.build_form(params)
  local npc = ffi_cast("TNormNpc*", params.npc)
  local uid = mir.player_get_uid(params.player)
  local db = mir.vedis_db

  local form = { [[ \]] }
  local s
  for i = 1, _M.max_record_useritem_nr do
    db:execute("HMGET u_uir:%s i%d n%d", uid, i, i)
    local make_index, name = unpack(res_to_list(db:exec_result()))
    s = [[<  %02d、/FCOLOR=249> %s　→　<装备名字：/FCOLOR=250>%-14s  <装备Idx：/FCOLOR=254>%10s  %s\]]
    tinsert(form, str_fmt(s,
      i,
      iif(make_index,
          str_fmt("<清除记录/@LB_清除记录(%d)>", i),
          str_fmt("<确认记录/@LB_确认记录(%d)>", i)),
      name or "",
      make_index or "",
      iif(make_index,
          str_fmt("<查此物品/@LB_查此物品(%d,%s)>", i, make_index or "0"))
    ))
  end

  local _, _, N0 = npc:get_var(params.player, "N0")
  tinsert(form, str_fmt([[ \
　　　　　　　　　<1. /FCOLOR=239>装备掉落可以通过所记录装备的[<Idx/FCOLOR=249>]编号来查询被谁捡取 (便于玩家购回)\
　　　　　　　　　<2. /FCOLOR=239>将要记录的装备放入左边[<装备框/FCOLOR=249>]中，然后点击上方对应位置的[<确认记录/FCOLOR=249>]按钮\
　　　　　　　　　<3. /FCOLOR=239><注意：/FCOLOR=249><装备掉落后,再通过其他途径取回后必须重新[/FCOLOR=253><确认记录/FCOLOR=249><]一次,否则无效!/FCOLOR=253>\
 \
　　　　　　　　　<允许记录列表/FCOLOR=250> → <查看列表<$STR(S$允许列表)>/FCOLOR=125>　　<装备Idx：/FCOLOR=70> %s\
 \
　<查询/@LB_查询>         %s         <一键记录/@LB_一键记录>         <清空记录/@LB_清空记录>\
<ITEMBOX:0:21:160:10:-122:70:70:*:250#请放入要记录的装备^254#然后在上方对应位置^254#点击[确认记录]按钮^151#如有信息,直接替换>\
]],
          iif(N0 > 0, N0),
          iif(N0 > 0, "<查询的装备/FCOLOR=10>", "<请输入Idx/@@InPutInteger0(请输入您要查询的装备Idx...)>")
  ))

  npc:set_var(params.player, "S0", table.concat(form))
end

return _M

-- vim: set et fenc=cp936 ff=dos sts=2 sw=2 ts=2 :
