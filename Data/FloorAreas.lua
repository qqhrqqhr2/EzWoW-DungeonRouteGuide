-- Sub-zone names shown on each floor (game DB2 UiMapAssignment + WMOAreaTable,
-- enUS / koKR), so the shown floor follows where the player stands.
-- Kept apart from MinimapData.lua (generated) and applied to multi-page dungeons.
-- A name on two floors is resolved by the next objective (see CurrentPage in MapFrame.lua).
local _, ns = ...

local AREAS = {
  dala = {
    sewers = { "The Underbelly", "마법사 구역 지하", "Dalaran Sewers", "달라란 하수도", "The Sewers", "하수도", "Cantrips & Crows", "마법과 까마귀 여관" },
    main = { "Krasus' Landing", "크라서스 착륙장", "The Violet Hold", "보랏빛 요새", "The Violet Citadel", "보랏빛 성채", "Antonidas Memorial", "안토니다스 기념비", "Runeweaver Square", "룬매듭 광장", "The Magus Commerce Exchange", "마법사 거래소", "The Eventide", "황혼의 제단", "Sunreaver's Sanctuary", "선리버 성소", "The Silver Enclave", "은빛 자치구", "Purple Parlor", "보랏빛 응접실" },
  },
  rfc = {
  },
  dm = {
  },
  sfk = {
  },
  bfd = {
  },
  stocks = {
  },
  gnomer = {
  },
  rfk = {
  },
  smgy = {
  },
  smlib = {
  },
  smarm = {
  },
  rfd = {
  },
  smcath = {
  },
  ulda = {
  },
  zf = {
    u219 = { "Zul'Farrak", "줄파락" },
  },
  mara = {
  },
  st = {
  },
  brd = {
  },
  scholo = {
  },
  stratlive = {
  },
  stratud = {
  },
  dmeast = {
  },
  dmwest = {
  },
  dmnorth = {
  },
  lbrs = {
  },
  smgy = {
  },
}

for _, d in ipairs(ns.Dungeons or {}) do
  local byPage = AREAS[d.key]
  if byPage and d.bliz and d.bliz.pages then
    for _, p in ipairs(d.bliz.pages) do
      if byPage[p.key] then
        p.areas = byPage[p.key]
        p.areaSet = nil
      end
    end
  end
end
