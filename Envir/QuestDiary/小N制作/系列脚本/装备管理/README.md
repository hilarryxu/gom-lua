## 安装

```lua
-- MerChant.txt 中添加一个NPC
小N制作\功能NPC\装备管理 3 321 325 装备管理 0 24 0

-- Market_Def\小N制作\功能NPC\装备管理-3.txt
[@main]
#IF
#ACT
  #CALL [\小N制作\系列脚本\装备管理\npc.txt] @装备管理_入口

-- QFunction-0.txt 中添加拾取触发
[@PickUpItemEx]
#IF
#ACT
  #CALL [\小N制作\系列脚本\装备管理\npc.txt] @装备管理_捡取触发
```
