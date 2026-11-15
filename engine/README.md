# EZ 엔진 패치

EZ 서버는 [Axolotl-PM](https://github.com/axolotl-pm/PocketMine-MP)(PocketMine-MP 포크) 공식 릴리스 위에 패치 몇 개를 붙여 직접 빌드해서 쓴다.

처음부터 엔진을 고칠 생각은 없었다. 렉을 잡다 보니 플러그인에서 엔진 내부 값을 리플렉션으로 바꾸는 코드가 생겼다.
private 속성 이름이 바뀌면 조용히 안 먹히는 코드라 업데이트할 때마다 불안했다.
그럴 바엔 필요한 함수를 엔진에 직접 넣고, 새 판이 나오면 패치가 붙는지부터 확인하는 쪽이 낫다고 판단했다.

## 빌드

```
bash build.sh 5.51.2                       # 패치 붙여 빌드
bash build.sh 5.51.2 --vanilla             # 패치 없이 (공식 판과 비교용)
OFFICIAL=PocketMine-MP.phar bash build.sh 5.51.2   # 공식 판과 같은 빌드 번호로
```

공식 릴리스 워크플로와 같은 명령으로 만든다. 처음에 그냥 `composer install`로 빌드했더니 공식 phar과
클래스맵, 플랫폼 검사 파일이 달랐다. 공식 CI와 같은 옵션, 같은 빌드 번호로 맞추고 나니
`--vanilla` 빌드와 공식 phar의 차이는 JSON 압축 여부와 버전 표기뿐이었다.

새 판이 나와서 패치가 안 붙으면 빌드가 멈춘다. 그때 패치를 새 판에 맞게 고친다.

## 패치

| 번호 | 내용 | 왜 |
|---|---|---|
| [001](patches/001-gc-threshold-api.patch) | `GarbageCollectorManager::setThreshold()`, `MemoryManager::getCycleGcManager()` | 판이 도는 동안 순환 GC를 미루고 판 사이에 돌리려고. 전에는 리플렉션으로 바꿨다 |
| [002](patches/002-creative-cache-warmup.patch) | `CreativeInventoryCache::warmup()` | 서버가 켜질 때 크리에이티브 목록 캐시를 미리 만들려고. 만드는 함수가 private이라 리플렉션으로 불렀다 |
| [003](patches/003-world-light-updates-toggle.patch) | `World::setLightUpdatesEnabled()`, `areLightUpdatesEnabled()` | 미니게임 경기장에서 서버 빛 계산을 끄려고. 전에는 청크의 빛 상태를 비워서 엔진이 건너뛰게 만들었다 |

003은 조금 조심해야 했다. 예전 방식은 빛 상태가 비어 있는 청크의 무작위 블록 틱(풀 번짐, 얼음 녹기 같은 것)도 같이 멈췄다.
새 함수로 빛만 끄면 그동안 멈춰 있던 무작위 틱이 다시 돌기 시작한다. 빛은 더 이상 다시 계산되지 않으니, 낡은 빛 값을 보고 얼음이 녹을지 정하게 된다.
그래서 엔진에 원래 있는 `setChunkTickRadius(0)`으로 무작위 틱도 같이 꺼서 동작을 예전과 똑같이 맞췄다.

플러그인 쪽은 함수가 있으면 쓰고, 없으면(공식 엔진) 예전 리플렉션으로 돌아간다. 그래서 공식 엔진으로 되돌려도 서버는 그대로 돈다.

```php
$memory = $server->getMemoryManager();
if(method_exists($memory, "getCycleGcManager")){
	$manager = $memory->getCycleGcManager();
	$this->apply = fn(int $value) => $manager->setThreshold($value);
	return;
}
// 없으면 ReflectionProperty 로 threshold 를 바꾼다
```

시험 서버에서 부하 테스트(6판)를 돌려 TPS 20.00, 실패 0을 확인했다.
002, 003을 붙인 판은 휴대폰으로 재난의 섬을 한 판 끝까지 해 보고 실서버에 올렸다.
접속하는 순간 멈춤이 없었고, 화산 웨이브의 서버 틱은 최대 77ms였다. 고치기 전에는 빛 계산 하나로 131~192ms가 걸렸다.

## 라이선스

엔진이 LGPL-3.0이라 패치도 LGPL-3.0이다.
