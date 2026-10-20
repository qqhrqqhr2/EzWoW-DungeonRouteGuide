# Changelog - EzWoW - Dungeon Route Guide

## v1.0.16
- 드래그 시 마우스 포인터와 아이콘/프레임 좌표가 어긋나거나 벌어지는 스케일 오차(`EffectiveScale`) 및 초기 점프 현상 수정
- **모듈 계층 재구성 (`Core/`, `Data/`, `Modules/`, `UI/`) 및 성능 개선**:
  - `Core/Init.lua`, `Core/Locales.lua`, `Core/UIKit.lua`, `Core/WorldMapDock.lua`
  - `Data/DungeonData.lua`(18개 던전·125개 목표·99개 퀘스트), `Data/FloorAreas.lua`, `Data/MinimapData.lua`
  - `Modules/ProgressTracker.lua`, `Modules/EntranceArrow.lua`
  - `UI/DungeonMapWindow.lua`, `UI/HUD.lua`, `UI/OptionsWindow.lua`, `UI/WorldMapPins.lua`, `UI/WorldMapDockSearch.lua`, `UI/LauncherIcon.lua`
  - 문자열 정규화 캐시 및 월드맵/던전맵 렌더링 스로틀링 최적화 적용
- **기능 및 데이터 보강**:
  - 월드맵 좌하단 자동 정렬(`EzWoWWorldMapDock`, 순번 3) 및 한·영 던전 입구 즉시 이동 검색창 통합
  - 로데론의 폐허 진행 순서(남작 → 비열한 빅토르 → 버려진 자 → 비요크 → 라스마엘) 및 야외 달라란 호드 주의사항, 군주 아쿠아니스 퀘스트 보상 3종 툴팁 반영
  - 99개 던전 퀘스트 최소 수락 레벨 표시 및 `EzWoW-MapFinder` 퀘스트 위치 검색 연동
  - 8개 언어(`Auto` 포함) 실시간 전환 및 슬래시 명령어(`/ezdg`, `/dungeonroute`, `/던전길잡이`) 정비
