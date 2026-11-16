# v2.0.24

### 한국어
- 세계지도의 던전 이름표에 마우스를 올려도 핀처럼 위로 올라오고 툴팁이 나오며, 이름표를 눌러도 핀을 누른 것과 같습니다.
- 지도에서 마지막으로 마우스를 올린 핀이 마우스를 떼도 다른 모든 EzWoW 핀(퀘스트·던전·비행·낚시 등) 위에 남습니다. 다른 핀에 올리면 그 핀이 맨 위로 옵니다.
- 애드온에 든 데이터가 다 있으면 공용 데이터 애드온의 던전 데이터를 불러오지 않아 메모리를 덜 씁니다.
- 공유 기록 저장 데이터가 오래 쓰면 조금씩 커지던 문제를 고쳤습니다.

### English
- Dungeon name tags on the World Map now act like their pins: hovering raises them and shows the tooltip, and a click does what a pin click does.
- The map pin you hovered last stays in front of all other EzWoW pins (quests, dungeons, flights, fishing…) after the mouse leaves, until you hover another one.
- Uses less memory: the shared data addon's dungeon module is no longer loaded when the addon's own data is complete.
- Fixed shared-record save data slowly growing over long use.
