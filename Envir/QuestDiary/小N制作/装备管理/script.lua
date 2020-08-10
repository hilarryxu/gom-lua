-- LUA�ű�
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
    s = [[<  %02d��/FCOLOR=249> %s������<װ�����֣�/FCOLOR=250>%-14s  <װ��Idx��/FCOLOR=254>%10s  %s\]]
    tinsert(form, str_fmt(s,
      i,
      iif(make_index,
          str_fmt("<�����¼/@LB_�����¼(%d)>", i),
          str_fmt("<ȷ�ϼ�¼/@LB_ȷ�ϼ�¼(%d)>", i)),
      name or "",
      make_index or "",
      iif(make_index,
          str_fmt("<�����Ʒ/@LB_�����Ʒ(%d,%s)>", i, make_index or "0"))
    ))
  end

  local _, _, N0 = npc:get_var(params.player, "N0")
  tinsert(form, str_fmt([[ \
������������������<1. /FCOLOR=239>װ���������ͨ������¼װ����[<Idx/FCOLOR=249>]�������ѯ��˭��ȡ (������ҹ���)\
������������������<2. /FCOLOR=239>��Ҫ��¼��װ���������[<װ����/FCOLOR=249>]�У�Ȼ�����Ϸ���Ӧλ�õ�[<ȷ�ϼ�¼/FCOLOR=249>]��ť\
������������������<3. /FCOLOR=239><ע�⣺/FCOLOR=249><װ�������,��ͨ������;��ȡ�غ��������[/FCOLOR=253><ȷ�ϼ�¼/FCOLOR=249><]һ��,������Ч!/FCOLOR=253>\
 \
������������������<�����¼�б�/FCOLOR=250> �� <�鿴�б�<$STR(S$�����б�)>/FCOLOR=125>����<װ��Idx��/FCOLOR=70> %s\
 \
��<��ѯ/@LB_��ѯ>         %s         <һ����¼/@LB_һ����¼>         <��ռ�¼/@LB_��ռ�¼>\
<ITEMBOX:0:21:160:10:-122:70:70:*:250#�����Ҫ��¼��װ��^254#Ȼ�����Ϸ���Ӧλ��^254#���[ȷ�ϼ�¼]��ť^151#������Ϣ,ֱ���滻>\
]],
          iif(N0 > 0, N0),
          iif(N0 > 0, "<��ѯ��װ��/FCOLOR=10>", "<������Idx/@@InPutInteger0(��������Ҫ��ѯ��װ��Idx...)>")
  ))

  npc:set_var(params.player, "S0", table.concat(form))
end

return _M

-- vim: set et fenc=cp936 ff=dos sts=2 sw=2 ts=2 :
