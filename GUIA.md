# Guia de leitura do código

Este arquivo existe para estudo. O código não tem comentários: o que ele faz está nos nomes, e o
porquê está aqui.

## Ordem de leitura

Leia nesta ordem. Cada passo só usa o que veio antes.

**1. `Model/GoalMetric.swift`**
O tipo mais simples do package: um enum. Repare em três coisas. O `rawValue` estável e por que
tem teste travando a lista. O bloco `#if canImport(HealthKit)`, que é o mecanismo que permite
tudo rodar em CI. E `readsWorkouts`, que é a única regra de negócio dentro de um enum.

**2. `Model/GoalDefinition.swift`**
Quatro campos e nada mais. Repare no que **não** está aqui: cor, usuário, grupo, ordem, e
qualquer noção de meta manual. Tudo isso é do app. No fim, `metrics` numa extensão de
`Collection`, que é o que garante "peça só o que o grupo usa".

**3. `Model/GoalProgress.swift`**
O init que calcula em vez de aceitar valores prontos. Entenda por que `fraction` não é parâmetro:
o tipo não confia em quem chama, ele deriva. Leia as três defesas (target zero, valor negativo,
`NaN`) e depois abra `Tests/GoalSourceTests/GoalProgressTests.swift` para ver cada uma testada.

**4. `Model/DailySnapshot.swift`**
Por que data e progressos andam colados num tipo só. Dois motivos, os dois com teste: à meia-noite
o stream emite zeros e sem a data não dá para distinguir virada de dia de falha de leitura; e o
cache precisa saber se o que guardou é de hoje ou de ontem.

**5. `Persistence/SnapshotStoring.swift`**
O primeiro protocolo do package. Aqui começa a ideia central: dependência que fala com o mundo
externo entra por protocolo. Duas implementações no mesmo arquivo, uma delas de três linhas.

**6. `Queries/HealthStoreProviding.swift`**
**Este é o arquivo mais importante para entender a arquitetura.** Repare que nenhum tipo do
HealthKit aparece nas assinaturas. Pergunte-se por que antes de continuar. A resposta está na
seção "As cinco decisões" mais abaixo, item 2.

**7. `Store/HealthKitGoalStore.swift`**
O ator. Leia de cima para baixo até `// MARK: - Encanamento das sessões`, pare, e só depois volte
para o `runSession`. É a parte mais difícil do package e não faz sentido antes do resto.

**8. `Store/GoalsMonitor.swift`**
A casca de main actor. Curto e sem lógica própria: tudo aqui é delegação. Serve para entender o
que `@Observable` resolve.

**9. `Queries/LiveHealthStore.swift`**
Deixe por último. É o único arquivo sem teste, e o único que precisa de aparelho de verdade.

## Conceitos do Swift que aparecem, e onde ver cada um

| Conceito | Onde está | O que observar |
|---|---|---|
| `actor` | `HealthKitGoalStore` | por que substitui `lock` |
| `Sendable` | em todo lugar | o que o compilador está garantindo |
| `@unchecked Sendable` | `HealthObservationToken`, `UncheckedBox` | quando é legítimo mentir para o compilador |
| `AsyncStream` | `liveSnapshots` | ponte entre callback e `for await` |
| `withCheckedThrowingContinuation` | `LiveHealthStore.sum` | ponte entre callback e `async` |
| `withThrowingTaskGroup` | `snapshot(for:on:)` | paralelismo, e por que reordena no fim |
| cancelamento de `Task` | `runSession`, `GoalsMonitor.start` | como o SwiftUI desliga tudo sozinho |
| `@Observable` | `GoalsMonitor` | o que substituiu `ObservableObject` |
| `#if canImport` | `GoalMetric`, `LiveHealthStore` | compilação condicional por plataforma |
| injeção por protocolo | `HealthStoreProviding`, `SnapshotStoring` | por que os testes existem |

## As cinco decisões que explicam o resto

1. **Erro é só para "não dá para continuar".** Leitura vazia vira dado (`ProgressUnavailableReason`),
   não exceção, porque os outros anéis precisam continuar desenhando. Veja `HealthKitGoalError`.
2. **Nenhum tipo do HealthKit cruza `HealthStoreProviding`.** Unidade fica de um lado, calendário
   do outro. É o que faz 83 testes rodarem sem HealthKit.
3. **O package conhece uma pessoa só, e só o que vem do HealthKit.** Não existe `userId`, nem
   grupo, nem meta manual. Se o dado não sai de um sensor, não entra aqui.
4. **O cache é local ao aparelho.** App Group une app e widget, não iPhone e Watch.
5. **O HealthKit nunca revela permissão de leitura.** Metade do `AuthorizationSummary` vem da
   Apple e metade vem do que o package anotou. Veja `MetricAuthorization`.

## Exercícios

Aprende-se mais quebrando do que lendo. Os testes dizem exatamente o que quebrou.

1. Em `GoalProgress.init`, troque `min(1, ...)` por `sanitizedValue / sanitizedTarget`. Rode
   `swift test`. Qual teste pega, e o que aconteceria na tela sem ele?
2. Em `HealthKitGoalStore.snapshot`, apague o `.sorted { $0.0 < $1.0 }`. O teste pode passar
   algumas vezes antes de falhar. Por quê?
3. Em `runSession`, apague o `token?.cancel()` do final. Qual teste pega, e qual seria o sintoma
   no app real depois de entrar e sair da tela vinte vezes?
4. Em `progress(for:on:in:)`, inverta a ordem dos dois primeiros `guard`. Qual teste pega, e que
   informação errada o usuário veria na tela?
5. Adicione uma métrica nova ao `GoalMetric` sem mexer em mais nada. Quantos erros de compilação
   aparecem, e por que isso é bom?

## Rodando

```
swift build          # compila para macOS, sem HealthKit
swift test           # 71 testes, nenhum precisa de aparelho
xcodebuild -scheme GoalSource -destination 'generic/platform=iOS' build
xcodebuild -scheme GoalSource -destination 'generic/platform=watchOS' build
```

Os dois últimos são os únicos que compilam o `LiveHealthStore` de verdade.
