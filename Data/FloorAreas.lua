-- Sub-zone names shown on each floor (game DB2 UiMapAssignment + WMOAreaTable,
-- enUS / koKR), so the shown floor follows where the player stands.
-- Kept apart from MinimapData.lua (generated) and applied to multi-page dungeons.
-- A name on two floors is resolved by the next objective (see CurrentPage in MapFrame.lua).
local _, ns = ...

local AREAS = {
  dm = {
    mines = { "Goblin Foundry", "고블린 주물 공장", "Mast Room", "목재 작업장" },
    cove = { "Ironclad Cove", "철갑 동굴" },
  },
  sfk = {
    ground = { "The Courtyard", "Courtyard", "안뜰", "안마당", "Dining Hall", "연회장", "The Kitchen", "주방", "The Butcher's Den", "푸줏간", "Stables", "마구간" },
    upper = { "Council Chamber", "의회실", "The Wall Walk", "Wall Walk", "성벽 통로", "Theology Chamber", "신학의 방" },
    tower = { "Lower Observatory", "Observatory", "천문대", "관측소 하층", "Sorcerer's Tower", "마법사의 탑" },
    top = { "The Vacant Den", "빈 굴", "텅 빈 굴", "Upper Observatory", "관측소 상층", "Arugal's Chamber", "아루갈의 방", "Lord Godfrey's Chamber", "고드프리 경의 방" },
  },
  bfd = {
    pool = { "The Forgotten Pool", "잊혀진 웅덩이", "The Pool of Ask'ar", "The Pool of Ask'Ar", "아스카르 연못", "The Drowned Sacellum", "가라앉은 제단", "Moonshrine Ruins", "달의 제단 폐허" },
    sanctum = { "The Forgotten Pool", "잊혀진 웅덩이", "Moonshrine Ruins", "달의 제단 폐허", "Moonshrine Sanctum", "달의 제단 성소", "Aku'mai's Lair", "아쿠마이의 둥지" },
  },
  gnomer = {
    upper = { "The Hall of Gears", "톱니바퀴의 전당", "The Clean Zone", "정화 지역", "The Clockwerk Run", "태엽장치 통로", "Train Depot", "기차 정거장", "Loading Room", "하역장" },
    workshop = { "The Hall of Gears", "톱니바퀴의 전당", "Workshop", "작업장" },
    launch = { "The Hall of Gears", "톱니바퀴의 전당", "Engineering Labs", "기계공학 연구소", "Launch Bay", "출격실" },
    court = { "The Dormitory", "거주 지구", "Tinkers' Court", "땜장이 왕실" },
  },
  ulda = {
    keepers = { "Equinox Monument", "춘분 기념비", "Map Chamber", "발굴 지도실", "Echomok Cavern", "메아리 동굴", "Hall of the Keepers", "수호자의 전당", "Temple Hall", "신전 전당", "Dig Three", "제3 발굴지", "Dig One", "제1 발굴지", "Dig Two", "제2 발굴지", "The Stone Vault", "지하 석실", "Hall of the Crafters", "장인의 전당" },
    seat = { "Khaz'goroth's Seat", "Khaz'Goroth's Seat", "카즈고로스의 왕좌", "Hall of the Crafters", "장인의 전당" },
  },
  smgy = {
    main = { "Chamber of Atonement", "속죄의 방", "Forlorn Cloister", "버려진 회랑", "The Graveyard", "묘지" },
    crypt = { "Honor's Tomb", "명예의 무덤", "Crypt", "납골당" },
  },
  dala = {
    sewers = { "The Underbelly", "마법사 구역 지하", "Dalaran Sewers", "달라란 하수도", "The Sewers", "하수도", "Cantrips & Crows", "마법과 까마귀 여관" },
    main = { "Krasus' Landing", "크라서스 착륙장", "The Violet Hold", "보랏빛 요새", "The Violet Citadel", "보랏빛 성채", "Antonidas Memorial", "안토니다스 기념비", "Runeweaver Square", "룬매듭 광장", "The Magus Commerce Exchange", "마법사 거래소", "The Eventide", "황혼의 제단", "Sunreaver's Sanctuary", "선리버 성소", "The Silver Enclave", "은빛 자치구", "Purple Parlor", "보랏빛 응접실" },
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
