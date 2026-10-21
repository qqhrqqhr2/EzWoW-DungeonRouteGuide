--===========================================================================
-- EzWoW - Dungeon Route Guide
-- Core/Locales.lua : Multilingual Localization Table & Entry Field Resolver
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local LocaleRegistry = ns.LocaleRegistry or {}
ns.LocaleRegistry = LocaleRegistry

ns.locale = (GetLocale and GetLocale() == "koKR") and "ko" or "en"

function ns.GetLocalizedText(v)
    if type(v) == "table" then return v[ns.locale] or v.en or v.ko or "" end
    return v
end

-- Every language's text of a localized field (for search and zone matching
-- on any client language)
function ns.AllLocalizedTexts(v)
    local list = {}
    if type(v) == "table" then
        for _, text in pairs(v) do
            if type(text) == "string" and text ~= "" then list[#list + 1] = text end
        end
    elseif type(v) == "string" then
        list[1] = v
    end
    return list
end

local StyleService = {
    WING_PENDING    = { "수도원 지역을 아직 판별하지 못했습니다. 현재 지역을 선택하거나 지역명이 갱신될 때까지 기다려 주세요.", "The monastery area is not identified yet. Choose your current area or wait for the zone name to update." },
    WING_TITLE      = { "수도원: 현재 지역 선택", "Monastery: choose your current area" },
    WING_WAIT       = { "지역명이 확인되면 자동으로 지도가 열립니다.", "The map opens automatically when the area is identified." },
    WING_MANUAL     = { "현재 지역 선택: %s (이번 입장 동안 유지). /ezdg wing auto 로 자동 판별로 돌아갑니다.", "Current area: %s (until the next entry). Use /ezdg wing auto to resume detection." },
    WING_HELP       = { "/ezdg wing 도서관 · 묘지 · 무기고 · 대성당 또는 auto", "/ezdg wing library · graveyard · armory · cathedral, or auto" },
    MAP_FIT         = { "전체", "Fit" },
    MAP_ZOOM_TIP    = { "휠: 확대·축소 / 확대 후 지도 끌기: 이동 / 이 버튼: 전체 보기", "Wheel: zoom / Drag while zoomed: pan / Click this button: fit map" },
    MAP_CLASSIC_SUPPLEMENT = { "이 지역은 공식 클래식 클라이언트의 미니맵으로 보완했습니다. 현재 파일의 타일 번호와 건물 배치 좌표가 일치하는지 확인했습니다.", "Supplemented with official Classic client minimaps. Map tile coordinates and WMO placements match the current client." },
    MAP_NORTH_UP    = { "북 ↑", "N ↑" },
    MAP_GUIDE_UP    = { "방향 고정", "Fixed orientation" },
    MAP_NORTH_TIP   = { "북쪽이 위인 고정 지도입니다. 미니맵 회전 옵션이 켜져 있으면 미니맵과 화면 방향이 달라질 수 있습니다.", "Fixed north-up map. With minimap rotation enabled, the minimap can face a different direction." },
    MAP_GUIDE_TIP   = { "방향이 고정된 지도입니다. 미니맵 회전 설정을 사용하면 화면 방향이 다를 수 있습니다.", "Fixed map orientation. With minimap rotation enabled, the minimap can face a different direction." },
    PARTIAL_MINIMAP = { "일부 미니맵 타일 누락", "Some minimap tiles unavailable" },
    UNAVAILABLE_MINIMAP = { "지도를 불러오지 못했습니다.\n목록에서 다른 지역을 선택해 주세요.", "The map could not be loaded.\nSelect another area from the list." },
    PIN_CANDIDATES  = { "무작위 출현 후보 위치입니다. 선택하면 다른 후보 지점도 표시합니다. 실제 출현 지점은 게임에서 확인하세요.", "Possible random spawn locations. Select to show alternative spots. Check the active spawn in game." },
    TITLE           = { "EzWoW - Dungeon Route Guide", "EzWoW - Dungeon Route Guide" },
    NEXT            = { "다음", "Next" },
    TARGET          = { "대상", "Target" },
    DONE_ALL        = { "던전 완료! 수고하셨습니다.", "Dungeon complete!" },
    PROGRESS        = { "진행 %d/%d", "Bosses %d/%d" },
    TAB_ROUTE       = { "경로", "Route" },
    TAB_QUEST       = { "퀘스트", "Quests" },
    BTN_LIST        = { "목록", "List" },
    BTN_MENU        = { "설정", "Options" },
    BTN_MAP         = { "지도", "Map" },
    BTN_ANNOUNCE    = { "파티 알림", "Tell party" },
    BTN_CHECK       = { "완료", "Done" },
    BTN_STOP        = { "중지", "Stop" },
    KIND_boss       = { "우두머리", "Boss" },
    KIND_npc        = { "NPC", "NPC" },
    KIND_rare       = { "희귀", "Rare" },
    KIND_object     = { "물건", "Object" },
    KIND_task       = { "할 일", "Task" },
    KIND_fork       = { "갈림길", "Junction" },
    UNCONFIRMED     = { "위치 미확인", "Spot unconfirmed" },
    OUTSIDE         = { "던전 밖", "Outside" },
    LEG_ENTRANCE    = { "입구", "Entrance" },
    LEG_BOSS        = { "우두머리", "Boss" },
    LEG_RARE        = { "희귀 몹", "Rare" },
    LEG_NPC         = { "NPC", "NPC" },
    LEG_QUEST       = { "퀘스트 장소", "Quest spot" },
    LEG_ALT         = { "다른 출현 지점", "Other spawn spots" },
    QUEST_MARK      = { "퀘스트 관련", "Quest related" },
    TAB_NOTES       = { "준비", "Prep" },
    NO_NOTES        = { "준비 사항이 없습니다.", "No notes." },
    NO_MAP          = { "이 던전은 아직 지도 자료가 없습니다.\n오른쪽 목록을 참고하세요.", "No map data for this dungeon yet.\nUse the list on the right." },
    BLANK_MAP       = { "지형 그림 없음 · 상대 위치만 표시", "No terrain art · relative positions only" },
    BTN_CURRENT     = { "현재 던전", "Current" },
    TIP_CURRENT     = { "지금 있는 던전 지도로 돌아갑니다", "Back to the map of the dungeon you are in" },
    FLOW_ONLY       = { "미니맵 자료가 없어 진행 순서만 표시", "No minimap data yet: route order only" },
    SCHEMATIC       = { "위치는 참고용", "Sketch map, positions approximate" },
    LEGACY_MAP      = { "구버전 미니맵 · 지역 배치 확인 필요", "Legacy minimap - verify area layout" },
    APPROX          = { "표식 위치 추정 · 확인 필요", "Estimated markers - review required" },
    LOOT            = { "전리품", "Loot" },
    TRASH_LOOT      = { "일반 몹 드랍", "Trash drops" },
    TRASH_ALL       = { "던전 일반 몹이 떨구는 아이템", "Dropped by the dungeon's trash mobs" },
    TRASH_NAMED     = { "경로 밖 네임드 몹", "Named mob off the route" },
    TRASH_ROW_TIP   = { "클릭: 이 몹들이 떨구는 아이템 보기", "Click: show what these mobs drop" },
    TRASH_TIP       = { "아이템 %d개. 아래 아이콘이나 옆 카드에서 아이템마다 떨구는 몹과 확률을 볼 수 있어요.", "%d items. Hover the icons below or see the card for the mob and chance of each." },
    WHEEL           = { "휠", "wheel" },
    PREVIEW_MAP     = { "게임 공식 지도 미리보기 (표식은 약도에)", "Official game map preview (markers are on the sketch)" },
    SCAN_NONE       = { "지도 정보를 읽을 수 없습니다. 던전 밖에서 다시 해 보세요.", "Map info is not readable here. Try again outside a dungeon." },
    SCAN_HIT        = { "공식 지도 %d: %s (종류 %d, 그림 조각 %d개)", "Official map %d: %s (type %d, %d art tiles)" },
    SCAN_DONE       = { "공식 지도 %d개를 찾았습니다. 원본 지도가 없던 던전은 설정 > 지도 그림 '블리자드 원본'에서 미리 볼 수 있어요.", "Found %d official maps. Dungeons without one before can preview them with Options > Map art: Blizzard." },
    ITEMS_LOADING   = { "아이템 정보 불러오는 중 %d/%d", "Loading item info %d/%d" },
    ITEM_MISSING    = { "(이 게임에 없는 아이템)", "(not in this game)" },
    ITEMS_MISSING   = { "%d개는 이 게임 버전에 없는 아이템입니다.", "%d item(s) do not exist in this game version." },
    SRC_WORLD       = { "던전의 모든 몹 · 낮은 확률", "Any mob in the dungeon · low chance" },
    SRC_FROM        = { "떨구는 몹", "Dropped by" },
    SRC_MORE        = { "외 %d", "+%d more" },
    LOADING         = { "불러오는 중…", "Loading…" },
    LOOT_HINT       = { "Shift+클릭: 채팅에 링크", "Shift-click: link in chat" },
    OPT_LANG        = { "언어: %s", "Language: %s" },
    OPT_MAPSTYLE    = { "지도 그림: %s", "Map art: %s" },
    MAP_BLIZ        = { "미니맵 조합", "Minimap tiles" },
    MAP_ATLAS       = { "스케치 지도", "Sketch map" },
    MAPSTYLE_SET    = { "지도 그림: %s", "Map art: %s" },
    MODEL_HINT      = { "끌기: 회전 · 휠: 확대/축소 · 오른쪽 클릭: 처음 각도", "Drag: rotate · Wheel: zoom · Right-click: reset" },
    NO_MODEL        = { "3D 모델 정보 없음", "No 3D model" },
    NO_LOOT         = { "등록된 전리품이 없습니다.", "No loot listed." },
    LANG_auto       = { "자동 (Auto)", "Auto" },
    LANG_ko         = { "한국어", "한국어 (Korean)" },
    LANG_en         = { "English (영어)", "English" },
    LANG_de         = { "Deutsch (독일어)", "Deutsch (German)" },
    LANG_fr         = { "Français (프랑스어)", "Français (French)" },
    LANG_es         = { "Español (스페인어)", "Español (Spanish)" },
    LANG_ru         = { "Русский (러시아어)", "Русский (Russian)" },
    LANG_zhCN       = { "简体中文 (중국어 간체)", "简体中文 (Simplified Chinese)" },
    LANG_zhTW       = { "繁體中文 (중국어 번체)", "繁體中文 (Traditional Chinese)" },
    PICK_DUNGEON    = { "던전 선택 (클릭)", "Pick a dungeon (click)" },
    PAGE            = { "지도 %d", "Map %d" },
    AREA            = { "지역 %d/%d", "Area %d/%d" },
    AREA_SHORT      = { "지역 %d", "Area %d" },
    AREA_TIP        = { "이 던전은 지역(지도)이 %d곳입니다. 눌러서 다른 지역 보기", "This dungeon has %d areas (maps). Click to view another" },
    NEXT_AREA       = { "다음 목표 → %s", "Next objective → %s" },
    AREA_NEXT       = { "다음", "next" },
    AREA_LEFT       = { "남은 %d", "%d left" },
    LINK_CLICK      = { "클릭: 이 지역 지도 보기", "Click: show this area's map" },
    OPTIONAL        = { "선택", "Optional" },
    SKIPPED         = { "건너뜀", "Skipped" },
    Q_DONE          = { "완료", "Done" },
    Q_ACTIVE        = { "진행 중", "In log" },
    Q_MISSING       = { "미수락", "Not taken" },
    Q_MINLEVEL      = { "%d레벨부터", "From Lv %d" },
    Q_MINLEVEL_TIP  = { "%d레벨부터 받을 수 있습니다", "Can be taken from level %d" },
    Q_REWARDS       = { "퀘스트 보상", "Quest rewards" },
    Q_TARGET_STEPS  = { "던전 내 목표: %s", "In-dungeon objective: %s" },
    Q_CLICK_STEP    = { "좌클릭: 던전 지도에서 목표 위치 보기", "Left-click: Show objective on dungeon map" },
    Q_CLICK_MAP     = { "우클릭: 세계지도에서 퀘스트 시작 위치 찾기", "Right-click: Find quest start on World Map" },
    OPT_WORLD_PINS  = { "세계 지도 던전 표시: %s", "World map dungeons: %s" },
    WORLD_PIN_GROUP = { "%s 외 %d곳", "%s +%d" },
    WORLD_PIN_LEVEL = { "권장 %s레벨", "Recommended levels %s" },
    WORLD_TOOLS     = { "EzWoW - Dungeon Route Guide · 던전 찾기", "EzWoW - Dungeon Route Guide · Dungeon Finder" },
    WORLD_SHOW      = { "세계지도에 던전 입구 표시", "Show dungeon entrances on World Map" },
    WORLD_LABELS    = { "세계지도에 던전 이름 표시", "Show dungeon names on World Map" },
    WORLD_LEVELS    = { "세계지도에 권장 레벨 표시", "Show recommended levels on World Map" },
    WORLD_AUTO_ALIGN = { "지도 버튼 좌하단 자동 정렬", "Auto-align map button (bottom-left)" },
    WORLD_RIGHT_CLICK = { "왼쪽 클릭: 던전 찾기 창 펼치기/접기\n오른쪽 클릭: 아이콘 위치 초기화\n드래그: 아이콘 위치 이동", "Left-click: Expand/collapse dungeon search\nRight-click: Reset icon position\nDrag: Move icon" },
    WORLD_ROW_QUESTS = { "던전 퀘스트 %d개 (진행 중 %d / 완료 %d)", "Dungeon quests: %d (%d active / %d done)" },
    WORLD_ROW_HINT  = { "좌클릭: 입구 지도 보기 · 우클릭: 공략/퀘스트 창 열기", "Left-click: Show entrance map · Right-click: Open route/quest guide" },
    WORLD_SEARCH    = { "던전 검색 · Enter: 지역 지도", "Find dungeon · Enter: zone map" },
    WORLD_RESULTS   = { "검색 결과 %d개 / 전체 %d개", "%d results / %d dungeons" },
    WORLD_NO_RESULT = { "일치하는 던전이 없습니다.", "No matching dungeons." },
    Q_NOTE          = { "퀘스트 행 좌클릭: 던전 내 목표 위치 보기 · 우클릭: 세계지도 시작 위치 검색", "Left-click quest: show dungeon objective · Right-click: find quest start on World Map" },
    NO_QUESTS       = { "이 던전에 등록된 퀘스트가 없습니다.", "No quests listed for this dungeon." },
    NEW_INSTANCE    = { "새 인스턴스를 감지해서 진행을 초기화했습니다.", "New instance detected, progress reset." },
    RESET_SEEN      = { "%s 초기화 확인: 다음 입장 때 처음부터 시작합니다.", "%s was reset: next entry starts a new run." },
    NEW_RUN         = { "새 진행을 시작합니다: %s", "New run started: %s" },
    KILLED          = { "%s 처치 확인 (%d/%d)", "%s defeated (%d/%d)" },
    RARE_ALERT      = { "희귀 몹 발견: %s", "Rare spotted: %s" },
    BROWSE_ONLY     = { "둘러보기 중 (지금 있는 던전이 아님)", "Browsing (not the dungeon you are in)" },
    NOT_SUPPORTED   = { "이 던전은 아직 데이터가 없습니다. /ezdg debug 결과를 알려주세요.", "No data for this dungeon yet. Please report /ezdg debug." },
    ENTRANCE_START  = { "%s 입구 안내를 시작합니다.", "Guiding you to %s." },
    ENTRANCE_STOP   = { "입구 안내를 끝냈습니다.", "Entrance guide stopped." },
    ENTRANCE_ARRIVE = { "도착! 입구로 들어가세요.", "Arrived! Enter the portal." },
    ENTRANCE_OTHER  = { "%s(으)로 이동하세요", "Travel to %s" },
    ENTRANCE_SET    = { "%s 입구 위치 저장: %.1f, %.1f", "%s entrance saved: %.1f, %.1f" },
    ENTRANCE_NOPOS  = { "현재 위치를 읽을 수 없습니다. (던전 안에서는 불가)", "Cannot read your position (not possible inside dungeons)." },
    ENTRANCE_INSIDE = { "던전 안입니다", "Inside a dungeon" },
    DIST            = { "%s쪽 %d야드", "%s, %d yd" },
    DIR_0 = { "북", "N" }, DIR_1 = { "북서", "NW" }, DIR_2 = { "서", "W" }, DIR_3 = { "남서", "SW" },
    DIR_4 = { "남", "S" }, DIR_5 = { "남동", "SE" }, DIR_6 = { "동", "E" }, DIR_7 = { "북동", "NE" },
    EDIT_ON         = { "표식 위치 편집: 목록에서 단계를 고른 뒤 지도를 왼쪽 클릭=그 자리로 옮기기, 오른쪽 클릭=원래 자리로", "Marker edit: pick a step, then left-click the map = move it there, right-click = back to default" },
    EDIT_OFF        = { "경로 편집 모드 꺼짐", "Edit mode off" },
    EDIT_POINT      = { "%s: 경로점 추가 (%d, %d)", "%s: waypoint added (%d, %d)" },
    EDIT_MARK       = { "%s: 표식 위치 (%d, %d)", "%s: marker moved (%d, %d)" },
    EDIT_CLEAR      = { "%s: 편집 내용을 지웠습니다", "%s: edits cleared" },
    OPT_ALPHA       = { "창 투명도: %d%%", "Window opacity: %d%%" },
    OPT_SIZE        = { "던전 지도 크기: %d", "Dungeon map size: %d" },
    OPT_LOCK        = { "공략 창 위치 잠금: %s", "Lock guide window: %s" },
    OPT_AUTO        = { "던전 입장 시 공략 창 자동 열기: %s", "Auto-open guide on dungeon entry: %s" },
    OPT_HUD         = { "화면 상단 다음 목표 바(HUD) 표시: %s", "Show next-objective HUD bar: %s" },
    OPT_RARE        = { "던전 희귀 몹 발견 알림: %s", "Rare mob spotted alert: %s" },
    OPT_FADE        = { "전투 중 공략 창 반투명화: %s", "Fade guide window in combat: %s" },
    OPT_ICON        = { "화면 바로가기 아이콘 표시: %s", "Show floating launcher icon: %s" },
    ICON_LEFT       = { "왼쪽 클릭: 공략 지도 열기/닫기", "Left-click: Open/close route map" },
    ICON_RIGHT      = { "오른쪽 클릭: 입구 안내 시작/끄기", "Right-click: Start/stop entrance guide" },
    ICON_DRAG       = { "드래그: 아이콘 위치 이동", "Drag: Move icon" },
    OPT_GO          = { "입구 방향 화살표 안내 시작", "Guide to dungeon entrance" },
    OPT_RESET       = { "현재 던전 진행도 초기화", "Reset current dungeon progress" },
    OPT_EDIT        = { "지도 표식 위치 수동 편집 모드: %s", "Marker position edit mode: %s" },
    OPT_EXPORT      = { "편집한 표식 위치 내보내기", "Export marker edits" },
    OPT_RESET_POS   = { "창·아이콘 위치 초기화", "Reset window & icon positions" },
    SEC_TOOLS       = { "도구 및 빠른 실행", "Tools & Quick Actions" },
    TIP_OPT_AUTO    = { "던전 인스턴스에 입장하면 해당 던전의 공략 지도 창을 자동으로 엽니다.", "Automatically opens the dungeon route map when entering a dungeon instance." },
    TIP_OPT_HUD     = { "던전 안에서 다음에 처치할 보스나 목표를 알려주는 작은 안내 바(HUD)를 표시합니다.", "Shows a compact HUD bar inside dungeons indicating the next boss or objective." },
    TIP_OPT_RARE    = { "던전 안에서 희귀(은테) 몬스터를 대상이나 마우스오버로 발견하면 경보음과 알림을 표시합니다.", "Plays a warning sound and alert when a rare mob is spotted inside a dungeon." },
    TIP_OPT_FADE    = { "전투가 시작되면 시야를 가리지 않도록 공략 지도 창을 반투명하게 흐리게 만듭니다.", "Fades the dungeon route window during combat so it does not block your view." },
    TIP_OPT_LOCK    = { "공략 지도 창과 다음 목표 바(HUD)가 마우스 드래그로 움직이지 않도록 고정합니다.", "Locks the route map window and HUD bar in place so they cannot be dragged." },
    TIP_OPT_ICON    = { "화면에 어디서나 공략 창을 바로 열 수 있는 EzWoW - Dungeon Route Guide 아이콘을 표시합니다.", "Displays the floating EzWoW - Dungeon Route Guide launcher icon on your screen." },
    TIP_WORLD_SHOW  = { "세계지도(M) 위에 각 지역 던전 입구 핀 아이콘을 표시합니다.", "Displays dungeon entrance pins on the World Map (M)." },
    TIP_WORLD_LABELS = { "세계지도 던전 입구 핀 아래에 던전 이름을 함께 표시합니다.", "Shows dungeon names below dungeon entrance pins on the World Map." },
    TIP_WORLD_LEVELS = { "세계지도 던전 입구 핀에 권장 입장 레벨 범위를 함께 표시합니다.", "Shows recommended level ranges on World Map dungeon entrance pins." },
    TIP_WORLD_AUTO_ALIGN = { "세계지도 왼쪽 하단 도킹 바에 EzWoW - Dungeon Route Guide 버튼을 자동으로 정렬합니다.", "Automatically aligns the EzWoW - Dungeon Route Guide button on the bottom-left of the World Map." },
    TIP_OPT_EDIT    = { "공략 지도에서 단계 선택 후 클릭하여 핀 위치를 직접 수정할 수 있는 편집 모드를 켭니다.", "Enables marker edit mode so you can reposition step pins on the dungeon map." },
    EXPORT_HINT     = { "Ctrl+A, Ctrl+C 로 복사하세요", "Ctrl+A, Ctrl+C to copy" },
    OPT_DONATE      = { "|cffff7799후원하기|r", "|cffff7799Support the addon|r" },
    DONATE_TEXT     = { "EzWoW - Dungeon Route Guide가 도움이 됐다면 후원으로 응원해 주세요!\n아래 주소를 Ctrl+C로 복사해 웹 브라우저에 붙여 넣으세요.",
                                            "If EzWoW - Dungeon Route Guide helps you, you can support it here.\nCopy the link with Ctrl+C and paste it into your web browser." },
    ON              = { "켜짐", "on" },
    OFF             = { "꺼짐", "off" },
    CLICK_HINT      = { "왼쪽 클릭: 선택 · 오른쪽 클릭: 완료 표시 전환", "Left-click: select · Right-click: toggle done" },
    SOURCE          = { "EzWoW - Dungeon Route Guide", "EzWoW - Dungeon Route Guide" },
    RESET_DONE      = { "진행을 초기화했습니다.", "Progress reset." },
    COMBAT_LOCKED   = { "전투 중에는 할 수 없습니다.", "Not available in combat." },
    HELP = {
        "|cffea837e/ezdg|r (/ezdg) 지도 열기/닫기 · |cffea837e/ezdg hud|r 다음 목표 표시\n" ..
        "|cffea837e/ezdg next|r 다음 단계 직접 완료 · |cffea837e/ezdg undo|r 되돌리기 · |cffea837e/ezdg reset|r 진행 초기화\n" ..
        "|cffea837e/ezdg go|r 입구 안내 · |cffea837e/ezdg go stop|r 안내 끄기 · |cffea837e/ezdg entrance set|r 지금 위치를 입구로 저장\n" ..
        "|cffea837e/ezdg lang|r 언어 (auto · ko · en · de · fr · es · ru · zhCN · zhTW) · |cffea837e/ezdg map|r 미니맵 다시 불러오기 · |cffea837e/ezdg icon|r 화면 아이콘 보이기/숨기기 · |cffea837e/ezdg edit|r 표식 위치 편집 · |cffea837e/ezdg export|r 편집 내보내기 · |cffea837e/ezdg debug|r 던전 정보 확인",
        "|cffea837e/ezdg|r (/ezdg) toggle map · |cffea837e/ezdg hud|r next-objective bar\n" ..
        "|cffea837e/ezdg next|r mark next done · |cffea837e/ezdg undo|r undo · |cffea837e/ezdg reset|r reset progress\n" ..
        "|cffea837e/ezdg go|r guide to entrance · |cffea837e/ezdg go stop|r stop · |cffea837e/ezdg entrance set|r save current spot as entrance\n" ..
        "|cffea837e/ezdg lang|r language (auto · ko · en · de · fr · es · ru · zhCN · zhTW) · |cffea837e/ezdg map|r reload minimap · |cffea837e/ezdg icon|r show/hide icon · |cffea837e/ezdg edit|r marker edit · |cffea837e/ezdg export|r export edits · |cffea837e/ezdg debug|r dungeon info",
    },
}

local EXTRA_LOCALE = {
    de = {
        TITLE = "EzWoW - Dungeon Route Guide",
        NEXT = "Nächster", TARGET = "Ziel", DONE_ALL = "Dungeon abgeschlossen!", PROGRESS = "Bosse %d/%d",
        TAB_ROUTE = "Route", TAB_QUEST = "Quests", TAB_NOTES = "Vorbereitung",
        BTN_LIST = "Liste", BTN_MENU = "Optionen", BTN_MAP = "Karte", BTN_ANNOUNCE = "Gruppe melden",
        BTN_CHECK = "Fertig", BTN_STOP = "Stopp", BTN_CURRENT = "Aktuell",
        KIND_boss = "Boss", KIND_npc = "NSC", KIND_rare = "Selten", KIND_object = "Objekt", KIND_task = "Aufgabe", KIND_fork = "Kreuzung",
        LEG_ENTRANCE = "Eingang", LEG_BOSS = "Boss", LEG_RARE = "Selten", LEG_NPC = "NSC", LEG_QUEST = "Questort", LEG_ALT = "Andere Spawnpunkte",
        LOOT = "Beute", OPTIONAL = "Optional", SKIPPED = "Übersprungen",
        Q_DONE = "Fertig", Q_ACTIVE = "Im Log", Q_MISSING = "Nicht angenommen", Q_REWARDS = "Questbelohnungen",
        Q_TARGET_STEPS = "Ziel im Dungeon: %s",
        Q_CLICK_STEP = "Linksklick: Ziel auf der Dungeonkarte zeigen",
        Q_CLICK_MAP = "Rechtsklick: Queststart auf der Weltkarte suchen",
        OPT_LANG = "Sprache: %s", OPT_ALPHA = "Transparenz: %d%%", OPT_SIZE = "Kartengröße: %d",
        OPT_LOCK = "Fenster sperren: %s", OPT_AUTO = "Automatisch öffnen: %s", OPT_HUD = "Nächstes-Ziel-Leiste: %s",
        OPT_RARE = "Seltenheitswarnung: %s", OPT_FADE = "Im Kampf verblassen: %s", OPT_ICON = "Bildschirmsymbol: %s",
        OPT_WORLD_PINS = "Weltkarten-Dungeons: %s", OPT_GO = "Zum Eingang führen", OPT_RESET = "Fortschritt zurücksetzen",
        OPT_RESET_POS = "Positionen zurücksetzen", SEC_TOOLS = "Werkzeuge & Schnellzugriff",
        WORLD_TOOLS = "EzWoW - Dungeon Route Guide · Dungeonsuche",
        WORLD_SHOW = "Dungeoneingänge anzeigen", WORLD_LABELS = "Dungeonnamen anzeigen", WORLD_LEVELS = "Empfohlene Stufen anzeigen",
        WORLD_AUTO_ALIGN = "Kartenschaltfläche automatisch ausrichten (unten links)",
        WORLD_RIGHT_CLICK = "Linksklick: Suchfenster ein-/ausklappen\nRechtsklick: Symbolposition zurücksetzen\nZiehen: Symbol verschieben",
        WORLD_ROW_QUESTS = "Dungeonquests: %d (%d aktiv / %d fertig)",
        WORLD_ROW_HINT = "Linksklick: Eingangskarte · Rechtsklick: Routen-/Questführer",
        WORLD_SEARCH = "Dungeon suchen · Enter: Zonenkarte",
        WORLD_RESULTS = "%d Ergebnisse / %d Dungeons", WORLD_NO_RESULT = "Keine passenden Dungeons.",
        ON = "ein", OFF = "aus", MAP_FIT = "Einpassen",
    },
    fr = {
        TITLE = "EzWoW - Dungeon Route Guide",
        NEXT = "Suivant", TARGET = "Cible", DONE_ALL = "Donjon terminé !", PROGRESS = "Boss %d/%d",
        TAB_ROUTE = "Route", TAB_QUEST = "Quêtes", TAB_NOTES = "Prép.",
        BTN_LIST = "Liste", BTN_MENU = "Options", BTN_MAP = "Carte", BTN_ANNOUNCE = "Annoncer",
        BTN_CHECK = "Fait", BTN_STOP = "Arrêter", BTN_CURRENT = "Actuel",
        KIND_boss = "Boss", KIND_npc = "PNJ", KIND_rare = "Rare", KIND_object = "Objet", KIND_task = "Tâche", KIND_fork = "Carrefour",
        LEG_ENTRANCE = "Entrée", LEG_BOSS = "Boss", LEG_RARE = "Rare", LEG_NPC = "PNJ", LEG_QUEST = "Lieu de quête", LEG_ALT = "Autres apparitions",
        LOOT = "Butin", OPTIONAL = "Optionnel", SKIPPED = "Ignoré",
        Q_DONE = "Terminé", Q_ACTIVE = "En cours", Q_MISSING = "Non prise", Q_REWARDS = "Récompenses",
        Q_TARGET_STEPS = "Objectif dans le donjon : %s",
        Q_CLICK_STEP = "Clic gauche : Afficher l'objectif sur la carte du donjon",
        Q_CLICK_MAP = "Clic droit : Chercher le début de quête sur la carte du monde",
        OPT_LANG = "Langue : %s", OPT_ALPHA = "Opacité : %d%%", OPT_SIZE = "Taille : %d",
        OPT_LOCK = "Verrouiller : %s", OPT_AUTO = "Ouverture auto : %s", OPT_HUD = "Barre d'objectif : %s",
        OPT_RARE = "Alertes rares : %s", OPT_FADE = "Atténuer en combat : %s", OPT_ICON = "Icône d'écran : %s",
        OPT_WORLD_PINS = "Donjons sur la carte : %s", OPT_GO = "Guider vers l'entrée", OPT_RESET = "Réinitialiser",
        OPT_RESET_POS = "Réinitialiser les positions", SEC_TOOLS = "Outils & Accès rapide",
        WORLD_TOOLS = "EzWoW - Dungeon Route Guide · Recherche de donjon",
        WORLD_SHOW = "Afficher les entrées", WORLD_LABELS = "Afficher les noms", WORLD_LEVELS = "Afficher les niveaux recommandés",
        WORLD_AUTO_ALIGN = "Aligner auto. le bouton de carte (bas-gauche)",
        WORLD_RIGHT_CLICK = "Clic gauche : Déplier/replier la recherche\nClic droit : Réinitialiser la position de l'icône\nGlisser : Déplacer l'icône",
        WORLD_ROW_QUESTS = "Quêtes de donjon : %d (%d en cours / %d terminées)",
        WORLD_ROW_HINT = "Clic gauche : Carte d'entrée · Clic droit : Guide de route/quêtes",
        WORLD_SEARCH = "Chercher un donjon · Entrée : carte de zone",
        WORLD_RESULTS = "%d résultats / %d donjons", WORLD_NO_RESULT = "Aucun donjon correspondant.",
        ON = "activé", OFF = "désactivé", MAP_FIT = "Ajuster",
    },
    es = {
        TITLE = "EzWoW - Dungeon Route Guide",
        NEXT = "Siguiente", TARGET = "Objetivo", DONE_ALL = "¡Mazmorra completada!", PROGRESS = "Jefes %d/%d",
        TAB_ROUTE = "Ruta", TAB_QUEST = "Misiones", TAB_NOTES = "Prep.",
        BTN_LIST = "Lista", BTN_MENU = "Opciones", BTN_MAP = "Mapa", BTN_ANNOUNCE = "Avisar grupo",
        BTN_CHECK = "Hecho", BTN_STOP = "Parar", BTN_CURRENT = "Actual",
        KIND_boss = "Jefe", KIND_npc = "PNJ", KIND_rare = "Raro", KIND_object = "Objeto", KIND_task = "Tarea", KIND_fork = "Cruce",
        LEG_ENTRANCE = "Entrada", LEG_BOSS = "Jefe", LEG_RARE = "Raro", LEG_NPC = "PNJ", LEG_QUEST = "Lugar de misión", LEG_ALT = "Otros puntos",
        LOOT = "Botín", OPTIONAL = "Opcional", SKIPPED = "Omitido",
        Q_DONE = "Completada", Q_ACTIVE = "En registro", Q_MISSING = "Sin aceptar", Q_REWARDS = "Recompensas",
        Q_TARGET_STEPS = "Objetivo en mazmorra: %s",
        Q_CLICK_STEP = "Clic izq.: Mostrar objetivo en el mapa de mazmorra",
        Q_CLICK_MAP = "Clic der.: Buscar inicio de misión en el mapa del mundo",
        OPT_LANG = "Idioma: %s", OPT_ALPHA = "Opacidad: %d%%", OPT_SIZE = "Tamaño: %d",
        OPT_LOCK = "Bloquear ventana: %s", OPT_AUTO = "Abrir auto.: %s", OPT_HUD = "Barra de objetivo: %s",
        OPT_RARE = "Alertas de raros: %s", OPT_FADE = "Atenuar en combate: %s", OPT_ICON = "Icono en pantalla: %s",
        OPT_WORLD_PINS = "Mazmorras en mapa: %s", OPT_GO = "Guiar a la entrada", OPT_RESET = "Reiniciar progreso",
        OPT_RESET_POS = "Restablecer posiciones", SEC_TOOLS = "Herramientas y acceso rápido",
        WORLD_TOOLS = "EzWoW - Dungeon Route Guide · Buscador de mazmorras",
        WORLD_SHOW = "Mostrar entradas", WORLD_LABELS = "Mostrar nombres", WORLD_LEVELS = "Mostrar niveles recomendados",
        WORLD_AUTO_ALIGN = "Alinear botón de mapa (abajo-izquierda)",
        WORLD_RIGHT_CLICK = "Clic izq.: Desplegar/plegar buscador\nClic der.: Restablecer posición del icono\nArrastrar: Mover icono",
        WORLD_ROW_QUESTS = "Misiones de mazmorra: %d (%d activas / %d hechas)",
        WORLD_ROW_HINT = "Clic izq.: Mapa de entrada · Clic der.: Guía de ruta/misiones",
        WORLD_SEARCH = "Buscar mazmorra · Intro: mapa de zona",
        WORLD_RESULTS = "%d resultados / %d mazmorras", WORLD_NO_RESULT = "No hay mazmorras coincidentes.",
        ON = "act.", OFF = "desact.", MAP_FIT = "Ajustar",
    },
    ru = {
        TITLE = "EzWoW - Dungeon Route Guide",
        NEXT = "Далее", TARGET = "Цель", DONE_ALL = "Подземелье пройдено!", PROGRESS = "Боссы %d/%d",
        TAB_ROUTE = "Маршрут", TAB_QUEST = "Задания", TAB_NOTES = "Подготовка",
        BTN_LIST = "Список", BTN_MENU = "Настройки", BTN_MAP = "Карта", BTN_ANNOUNCE = "Сообщить группе",
        BTN_CHECK = "Готово", BTN_STOP = "Стоп", BTN_CURRENT = "Текущее",
        KIND_boss = "Босс", KIND_npc = "НИП", KIND_rare = "Редкий", KIND_object = "Объект", KIND_task = "Задача", KIND_fork = "Развилка",
        LEG_ENTRANCE = "Вход", LEG_BOSS = "Босс", LEG_RARE = "Редкий", LEG_NPC = "НИП", LEG_QUEST = "Место задания", LEG_ALT = "Другие точки",
        LOOT = "Добыча", OPTIONAL = "Необяз.", SKIPPED = "Пропущено",
        Q_DONE = "Выполнено", Q_ACTIVE = "В журнале", Q_MISSING = "Не взято", Q_REWARDS = "Награды",
        Q_TARGET_STEPS = "Цель в подземелье: %s",
        Q_CLICK_STEP = "ЛКМ: Показать цель на карте подземелья",
        Q_CLICK_MAP = "ПКМ: Найти начало задания на карте мира",
        OPT_LANG = "Язык: %s", OPT_ALPHA = "Прозрачность: %d%%", OPT_SIZE = "Размер карты: %d",
        OPT_LOCK = "Закрепить окно: %s", OPT_AUTO = "Авто-открытие: %s", OPT_HUD = "Панель следующей цели: %s",
        OPT_RARE = "Оповещения о редких: %s", OPT_FADE = "Прозрачность в бою: %s", OPT_ICON = "Значок на экране: %s",
        OPT_WORLD_PINS = "Подземелья на карте мира: %s", OPT_GO = "Путь ко входу", OPT_RESET = "Сбросить прогресс",
        OPT_RESET_POS = "Сбросить позиции окон", SEC_TOOLS = "Инструменты и быстрый доступ",
        WORLD_TOOLS = "EzWoW - Dungeon Route Guide · Поиск подземелий",
        WORLD_SHOW = "Показывать входы", WORLD_LABELS = "Показывать названия", WORLD_LEVELS = "Показывать рекомендуемые уровни",
        WORLD_AUTO_ALIGN = "Авто-выравнивание кнопки карты (внизу слева)",
        WORLD_RIGHT_CLICK = "ЛКМ: Развернуть/свернуть поиск\nПКМ: Сбросить позицию значка\nПеретаскивание: Переместить значок",
        WORLD_ROW_QUESTS = "Задания подземелья: %d (активно %d / выполнено %d)",
        WORLD_ROW_HINT = "ЛКМ: Карта входа · ПКМ: Открыть маршрут/задания",
        WORLD_SEARCH = "Поиск подземелья · Enter: карта зоны",
        WORLD_RESULTS = "Результатов: %d / %d", WORLD_NO_RESULT = "Подходящих подземелий не найдено.",
        ON = "вкл.", OFF = "выкл.", MAP_FIT = "Вписать",
    },
    zhCN = {
        TITLE = "EzWoW - Dungeon Route Guide",
        NEXT = "下一个", TARGET = "目标", DONE_ALL = "地下城已完成！", PROGRESS = "首领 %d/%d",
        TAB_ROUTE = "路线", TAB_QUEST = "任务", TAB_NOTES = "准备",
        BTN_LIST = "列表", BTN_MENU = "选项", BTN_MAP = "地图", BTN_ANNOUNCE = "通告小队",
        BTN_CHECK = "完成", BTN_STOP = "停止", BTN_CURRENT = "当前副本",
        KIND_boss = "首领", KIND_npc = "NPC", KIND_rare = "稀有", KIND_object = "物体", KIND_task = "事项", KIND_fork = "岔路",
        LEG_ENTRANCE = "入口", LEG_BOSS = "首领", LEG_RARE = "稀有怪", LEG_NPC = "NPC", LEG_QUEST = "任务点", LEG_ALT = "其他刷新点",
        LOOT = "掉落", OPTIONAL = "可选", SKIPPED = "已跳过",
        Q_DONE = "已完成", Q_ACTIVE = "进行中", Q_MISSING = "未接取", Q_REWARDS = "任务奖励",
        Q_TARGET_STEPS = "副本内目标：%s",
        Q_CLICK_STEP = "左键：在副本地图上查看目标位置",
        Q_CLICK_MAP = "右键：在世界地图上查找任务起始位置",
        OPT_LANG = "语言：%s", OPT_ALPHA = "透明度：%d%%", OPT_SIZE = "地图大小：%d",
        OPT_LOCK = "锁定窗口：%s", OPT_AUTO = "进入副本自动打开：%s", OPT_HUD = "下一目标栏：%s",
        OPT_RARE = "稀有怪提醒：%s", OPT_FADE = "战斗中淡出：%s", OPT_ICON = "屏幕图标：%s",
        OPT_WORLD_PINS = "世界地图副本标记：%s", OPT_GO = "指引前往入口", OPT_RESET = "重置进度",
        OPT_RESET_POS = "重置窗口与图标位置", SEC_TOOLS = "工具与快捷操作",
        WORLD_TOOLS = "EzWoW - Dungeon Route Guide · 地下城搜索",
        WORLD_SHOW = "显示地下城入口", WORLD_LABELS = "显示地下城名称", WORLD_LEVELS = "显示推荐等级",
        WORLD_AUTO_ALIGN = "世界地图按钮左下角自动对齐",
        WORLD_RIGHT_CLICK = "左键点击：展开/收起搜索面板\n右键点击：重置图标位置\n拖动：移动图标",
        WORLD_ROW_QUESTS = "地下城任务 %d 个（进行中 %d / 已完成 %d）",
        WORLD_ROW_HINT = "左键：查看入口地图 · 右键：打开路线/任务指南",
        WORLD_SEARCH = "搜索地下城 · 回车：打开区域地图",
        WORLD_RESULTS = "搜索结果 %d / 共 %d 个", WORLD_NO_RESULT = "没有匹配的地下城。",
        ON = "开启", OFF = "关闭", MAP_FIT = "全局",
    },
    zhTW = {
        TITLE = "EzWoW - Dungeon Route Guide",
        NEXT = "下一個", TARGET = "目標", DONE_ALL = "地城已完成！", PROGRESS = "首領 %d/%d",
        TAB_ROUTE = "路線", TAB_QUEST = "任務", TAB_NOTES = "準備",
        BTN_LIST = "列表", BTN_MENU = "選項", BTN_MAP = "地圖", BTN_ANNOUNCE = "通報隊伍",
        BTN_CHECK = "完成", BTN_STOP = "停止", BTN_CURRENT = "目前副本",
        KIND_boss = "首領", KIND_npc = "NPC", KIND_rare = "稀有", KIND_object = "物體", KIND_task = "事項", KIND_fork = "岔路",
        LEG_ENTRANCE = "入口", LEG_BOSS = "首領", LEG_RARE = "稀有怪", LEG_NPC = "NPC", LEG_QUEST = "任務點", LEG_ALT = "其他刷新點",
        LOOT = "掉落", OPTIONAL = "可選", SKIPPED = "已跳過",
        Q_DONE = "已完成", Q_ACTIVE = "進行中", Q_MISSING = "未接取", Q_REWARDS = "任務獎勵",
        Q_TARGET_STEPS = "副本內目標：%s",
        Q_CLICK_STEP = "左鍵：在副本地圖上查看目標位置",
        Q_CLICK_MAP = "右鍵：在世界地圖上查找任務起始位置",
        OPT_LANG = "語言：%s", OPT_ALPHA = "透明度：%d%%", OPT_SIZE = "地圖大小：%d",
        OPT_LOCK = "鎖定視窗：%s", OPT_AUTO = "進入副本自動打開：%s", OPT_HUD = "下一目標欄：%s",
        OPT_RARE = "稀有怪提醒：%s", OPT_FADE = "戰鬥中淡出：%s", OPT_ICON = "螢幕圖示：%s",
        OPT_WORLD_PINS = "世界地圖副本標記：%s", OPT_GO = "指引前往入口", OPT_RESET = "重置進度",
        OPT_RESET_POS = "重置視窗與圖示位置", SEC_TOOLS = "工具與快捷操作",
        WORLD_TOOLS = "EzWoW - Dungeon Route Guide · 地城搜尋",
        WORLD_SHOW = "顯示地城入口", WORLD_LABELS = "顯示地城名稱", WORLD_LEVELS = "顯示推薦等級",
        WORLD_AUTO_ALIGN = "世界地圖按鈕左下角自動對齊",
        WORLD_RIGHT_CLICK = "左鍵點擊：展開/收合搜尋面板\n右鍵點擊：重置圖示位置\n拖曳：移動圖示",
        WORLD_ROW_QUESTS = "地城任務 %d 個（進行中 %d / 已完成 %d）",
        WORLD_ROW_HINT = "左鍵：查看入口地圖 · 右鍵：打開路線/任務指南",
        WORLD_SEARCH = "搜尋地城 · Enter：打開區域地圖",
        WORLD_RESULTS = "搜尋結果 %d / 共 %d 個", WORLD_NO_RESULT = "沒有符合的地城。",
        ON = "開啟", OFF = "關閉", MAP_FIT = "全覽",
    },
}

local VALID_LANGS = {
    ko = true, en = true, de = true, fr = true, es = true, ru = true, zhCN = true, zhTW = true,
}

local CLIENT_MAP = {
    koKR = "ko",
    enUS = "en", enGB = "en",
    deDE = "de",
    frFR = "fr",
    esES = "es", esMX = "es",
    ruRU = "ru",
    zhCN = "zhCN",
    zhTW = "zhTW",
}

ns.L = setmetatable({}, { __index = function(_, k)
    local v = StyleService[k]
    return v and v[2] or k
end })
ns.locWidgets = {}

function ns.GetLocalizedEntryField(widget, key)
    widget:SetText(ns.L[key])
    ns.locWidgets[#ns.locWidgets + 1] = { w = widget, key = key }
    return widget
end

function ns.ResolveLocale(setting)
    if setting and VALID_LANGS[setting] then return setting end
    local cli = GetLocale and GetLocale() or "enUS"
    return CLIENT_MAP[cli] or "en"
end

function ns.SetLanguage(setting)
    ns.langSetting = (setting and VALID_LANGS[setting]) and setting or "auto"
    ns.locale = ns.ResolveLocale(ns.langSetting)
    local koVal = ns.locale == "ko"
    local extra = EXTRA_LOCALE[ns.locale]
    for k, v in pairs(StyleService) do
        local rawValue = (extra and extra[k]) or (koVal and v[1] or v[2]) or v[2]
        rawset(ns.L, k, rawValue)
    end
    
    BINDING_HEADER_EZWOWDUNGEONROUTEGUIDE = "EzWoW - Dungeon Route Guide"
    BINDING_NAME_EZWOWDUNGEONROUTEGUIDE_TOGGLE = koVal and "EzWoW - Dungeon Route Guide 지도 열기/닫기" or "Toggle route map"
    BINDING_NAME_EZWOWDUNGEONROUTEGUIDE_NEXT = koVal and "다음 단계 완료 표시" or "Mark next step done"
    BINDING_NAME_EZWOWDUNGEONROUTEGUIDE_ANNOUNCE = koVal and "다음 목표 파티에 알리기" or "Tell party the next objective"
    for _, recordEntry in ipairs(ns.locWidgets) do pcall(recordEntry.w.SetText, recordEntry.w, ns.L[recordEntry.key]) end
    if ns.OnLanguageChanged then ns.OnLanguageChanged() end
end

ns.SetLanguage("auto")

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
LocaleRegistry.GetLocalizedEntryField = ns.GetLocalizedEntryField
LocaleRegistry.GetLocalizedText = ns.GetLocalizedText
