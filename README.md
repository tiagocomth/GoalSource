# GoalSource

SDK de HealthKit. Recebe as metas monitoradas, devolve o progresso delas no dia e mantém isso atualizado sozinho.

Não conhece backend, UI, cores, tema, grupo nem usuário. Meta que o usuário marca na mão ("ler 20 páginas") também está fora: não tem nada a ver com HealthKit, e o app já é dono desse estado.

- Swift 5.10, `iOS 17+` / `watchOS 10+`, sem dependências externas
- API 100% `async/await`, um ator, tudo `Sendable`
- HealthKit importado condicionalmente: o package compila e roda os testes em CI sem HealthKit

## Instalação

```swift
dependencies: [
    .package(url: "https://github.com/tiagocomth/GoalSource.git", from: "1.0.0")
]
```

```swift
.target(name: "App", dependencies: ["GoalSource"])
```

No Xcode: **File › Add Package Dependencies…**, cole `https://github.com/tiagocomth/GoalSource` e escolha *Up to Next Major* a partir de `1.0.0`.

## Configuração do app

### Info.plist

Nos dois targets (iPhone e Watch):

```xml
<key>NSHealthShareUsageDescription</key>
<string>Para acompanhar suas metas de atividade junto com o seu grupo.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>Para registrar a água que você bebeu na sua meta de hidratação.</string>
```

`NSHealthUpdateUsageDescription` só é necessário se o grupo puder ter meta de água, mas o sistema exige a chave antes de o app chegar a saber disso. Deixe as duas sempre.

### Capabilities

| Capability | Onde | Para quê |
|---|---|---|
| HealthKit | iPhone + Watch | qualquer leitura |
| HealthKit › Background Delivery | só iPhone | `enablesBackgroundDelivery: true` |
| App Groups | iPhone + Watch | cache compartilhado com widgets e complicações |

O App Group vale **dentro de um mesmo aparelho**: une o app e suas extensões. Ele não atravessa iPhone e Watch. Desde o watchOS 2 o app do relógio roda no relógio, com container próprio, então cada um mantém o seu cache. Sem App Group o package continua funcionando, só que o widget passa a não ver o último snapshot.

Cada aparelho pode usar um identificador diferente. Usar o mesmo é conveniente, não é requisito.

## Uso

Uma instância por app, em algum lugar acessível:

```swift
import GoalSource

enum Goals {
    static let store = HealthKitGoalStore(
        configuration: .appGroup("group.com.example.goalsource")
    )
}
```

As metas vêm do seu backend; o `id` tem que ser o mesmo para todos do grupo. Os atalhos poupam digitar `kind:`:

```swift
let goals = [
    GoalDefinition.water(2, id: remote[0].id),
    GoalDefinition.steps(10_000, id: remote[1].id),
    GoalDefinition.running(kilometers: 5, id: remote[2].id)
]
```

Passe só as metas monitoradas; as manuais o app resolve sozinho. O `id` é uma `String` opaca: passe exatamente o que o seu backend usa, sem conversão. Ele volta em `GoalProgress.goalID` para você casar resposta com pergunta.

Na tela, use o `GoalsMonitor`: ele é `@MainActor @Observable`, então o corpo da view lê propriedade normal, sem `await`.

```swift
struct MyPartView: View {
    @State private var monitor = GoalsMonitor(goals: goals, store: Goals.store)

    var body: some View {
        VStack {
            ForEach(monitor.goals) { goal in
                GoalRing(fraction: monitor.fraction(for: goal))
            }
        }
        .task { await monitor.start() }   // pede permissão, carrega o cache e transmite
    }
}
```

`start()` roda até a `.task` ser cancelada, que é o que o SwiftUI faz quando a view sai da tela. As queries do HealthKit são desregistradas sozinhas.

Se preferir falar direto com o ator, tudo continua acessível:

```swift
let snapshot = try await Goals.store.snapshot(for: goals, on: .now)
try await Goals.store.log(0.25, for: .water, at: .now)
```

O `DailySnapshot` é a resposta do package: a data mais o progresso das metas monitoradas daquele dia, colados num tipo só. Ele é `Codable` e não carrega nada de HealthKit, mas não presuma que ele é o seu formato de persistência. Se o seu backend guarda uma linha por meta, o snapshot é insumo da escrita, e a tradução mora na sua camada de sincronização, que é também onde ele se junta às metas manuais.

Para decidir sob qual dia publicar, use `await Goals.store.dayKey(for: date)`: ele devolve o mesmo `yyyy-MM-dd` que o package usa para ler o HealthKit. Inventar o seu põe participante de outro fuso escrevendo num dia diferente do que você lê.

### Estado "sem acesso ao Health"

Uma meta monitorada nunca falha por falta de permissão. Ela volta em zero com um `unavailableReason`, e a UI decide o que mostrar:

```swift
switch progress.unavailableReason {
case nil:                          RingView(fraction: progress.fraction)
case .noSamples:                   RingView(fraction: 0)          // zero de verdade, ou leitura negada
case .authorizationNotRequested:   AskForHealthAccessView()
case .authorizationDenied:         OpenHealthSettingsView()
case .metricUnavailableOnDevice:   UnsupportedMetricView()
}
```

## Exemplo SwiftUI: quatro anéis ao vivo

As cores vêm do tema do app; o package não as conhece.

```swift
import SwiftUI
import GoalSource

struct MyPartView: View {
    @State private var monitor: GoalsMonitor
    let palette: [GoalDefinition.ID: Color]

    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                ForEach(Array(monitor.goals.enumerated()), id: \.element.id) { index, goal in
                    GoalRing(
                        fraction: monitor.fraction(for: goal),
                        color: palette[goal.id] ?? .accentColor,
                        lineWidth: 18
                    )
                    .padding(CGFloat(index) * 24)
                }
            }
            .frame(width: 240, height: 240)
            .animation(.snappy, value: monitor.snapshot)

            ForEach(monitor.goals) { goal in
                GoalRow(
                    goal: goal,
                    progress: monitor.progress(for: goal),
                    needsAccess: monitor.needsHealthAccess(for: goal),
                    color: palette[goal.id] ?? .accentColor
                )
            }
        }
        .padding()
        .task { await monitor.start() }
    }
}

struct GoalRing: View {
    let fraction: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct GoalRow: View {
    let goal: GoalDefinition
    let progress: GoalProgress?
    let needsAccess: Bool
    let color: Color

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(goal.title)
            Spacer()
            trailing
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if needsAccess {
            Label("Sem acesso", systemImage: "heart.slash")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        } else {
            Text(progress?.fraction ?? 0, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
```

### Previews e simulador

O simulador não tem o app Saúde, então toda leitura real volta zero. Para preview e para rodar no simulador com número na tela:

```swift
#Preview {
    MyPartView(
        monitor: .preview(goals: goals, totals: [.stepCount: 7_500, .water: 1.4]),
        palette: [:]
    )
}
```

`GoalsMonitor.preview` monta um store sobre `StubHealthStore` e cache em memória. Nada de HealthKit, nada de disco. O mesmo vale para `HealthKitGoalStore.preview(totals:)` se você não usar o monitor.

## watchOS

O mesmo target compila no Watch, e a API é a mesma. Para os anéis e o gráfico de barras basta:

```swift
let fractions = try await store.todayFractions(for: goals)   // [String: Double], indexado pelo id da meta
```

O watchOS tem HealthKit próprio, já com o que os sensores do relógio registraram. O Watch não precisa perguntar nada ao iPhone para desenhar os anéis: ele lê o HealthKit dele mesmo.

O que muda:

- background delivery é ignorado (a API não existe no watchOS); o stream continua funcionando em primeiro plano
- criar metas e configurações continuam exclusivos do iPhone: o package não impede, o app é que não expõe

### O que atravessa entre os aparelhos, e o que não

| | Como chega do outro lado |
|---|---|
| Meta monitorada (HealthKit) | o sistema já espelha as amostras do Watch para o iPhone, sem código seu |
| Meta manual (checkmark) | fora do escopo deste SDK: é estado do app, e o app é quem sincroniza |

A sincronização das amostras Watch → iPhone também não é instantânea: depende dos aparelhos se falarem, e leva de segundos a minutos. O número no relógio pode ficar à frente do número no telefone por um tempo. É comportamento do sistema, não do package.

## Testes

```
swift test
```

Roda em qualquer macOS, sem simulador e sem HealthKit. O ator depende do protocolo `HealthStoreProviding`, e o alvo de testes injeta um `MockHealthStore`. As 71 asserções cobrem cálculo de fração (clamp, target zero, `NaN`), limites de dia e fuso (incluindo horário de verão), autorização parcial, debounce do stream, virada do dia, cancelamento sem vazar observer, e o cache persistindo e restaurando. O `GoalsMonitor` tem os seus: leitura segura antes do primeiro snapshot, prompt opcional, erro de escrita virando `lastError`, e troca de metas limpando o snapshot velho.

Os testes que dependem de `HKUnit` de verdade estão sob `#if canImport(HealthKit)` e só rodam quando você compila para iOS ou watchOS:

```
xcodebuild -scheme GoalSource -destination 'generic/platform=iOS' build
xcodebuild -scheme GoalSource -destination 'generic/platform=watchOS' build
```

## Arquitetura

```
Model/         GoalMetric, GoalDefinition (+ atalhos), GoalProgress, DailySnapshot,
               AuthorizationSummary, erros
Store/         HealthKitGoalStore (o ator), Configuration, GoalsMonitor (@Observable)
Queries/       HealthStoreProviding, LiveHealthStore (HKHealthStore), StubHealthStore,
               HealthObservationToken
Persistence/   SnapshotStoring, FileSnapshotStore, InMemorySnapshotStore, PersistedState
Support/       Logger, aritmética de dia/calendário
```

São duas portas de entrada para a mesma coisa. `HealthKitGoalStore` é o ator, e é onde mora a lógica. `GoalsMonitor` é uma casca `@MainActor` em cima dele para o SwiftUI não ter que lidar com `await` no corpo da view. Use o monitor na tela e o ator em qualquer outro lugar; nada é exclusivo de um dos dois.

A fronteira que importa é o `HealthStoreProviding`: nada de HealthKit atravessa esse protocolo. Unidades ficam do lado de dentro (`LiveHealthStore`), matemática de dia fica do lado de fora (`HealthKitGoalStore`). É o que deixa o ator inteiro testável numa máquina sem HealthKit.

Sem `print`. Tudo vai pro `Logger` no subsystem `com.goalsource`, categorias `model`, `store`, `queries` e `persistence`.

## Limitações e decisões

**Corrida não é o mesmo que caminhada.** O HealthKit não tem um quantity type de "distância correndo": `distanceWalkingRunning` conta o dia inteiro, ida à padaria incluída. Então `runningDistance` soma a distância registrada *dentro de workouts de corrida* (`HKSampleQuery` sobre `predicateForWorkouts(with: .running)`), enquanto `walkingDistance` usa o total do dia. As duas apontam para o mesmo `hkQuantityTypeIdentifier` porque é esse o tipo que precisa de permissão; quem separa é `GoalMetric.readsWorkouts`. Consequência: uma meta de corrida só progride se houver workout registrado. Correr sem iniciar um treino não conta, e isso é o comportamento correto para a meta.

**Nadar usa o quantity type, não os workouts.** `distanceSwimming` só é produzido por workouts de natação, então a query simples já é precisa. Não vale o segundo caminho.

**Só água é gravável.** Passos, distância e energia vêm dos sensores; escrever à mão corromperia o Health do usuário. Tudo que não é água lança `writeNotPermitted`.

**Workout manual ficou de fora.** Você mencionou "água e workouts manuais" na escrita, mas um workout é `HKWorkout`, não `HKQuantitySample`: não cabe na assinatura `log(_ amount: Double, for metric:)`. Registrar treino exige `HKWorkoutBuilder`, sessão, tipo de atividade, duração e energia. É uma superfície inteira, e a decisão foi não inventá-la agora. Se o produto precisar, entra como `startWorkout`/`endWorkout` num arquivo separado, sem mexer no que existe.

**Nada de `HKAnchoredObjectQuery`.** O anel precisa do total do dia, não das amostras novas. `HKObserverQuery` avisa que mudou e o package recalcula o total do dia com `HKStatisticsQuery`. Âncora só ajudaria se o package processasse amostra por amostra, o que ele não faz. Se um dia precisar de histórico incremental, aí sim.

**Nada de `HKStatisticsCollectionQuery`.** Ela existe para séries de vários dias. Aqui a janela é sempre um dia só, e uma statistics query simples é mais barata.

**O debounce é *trailing*, sem teto.** Uma rajada contínua de amostras adia a emissão indefinidamente enquanto durar. Na prática o HealthKit agrupa em lotes e a rajada termina; se aparecer um caso patológico, o conserto é um `maxWait`.

**Leitura negada é indistinguível de dia vazio.** É de propósito na Apple: um app não pode descobrir que o usuário escondeu dados. Por isso `MetricAuthorization` só reporta `.denied`/`.authorized` para água (a única gravável) e, para o resto, `.notRequested`/`.requested` com base no que o package persistiu ter pedido. `ProgressUnavailableReason.noSamples` significa "zero ou sem acesso", e a UI deve escolher um texto que sirva para os dois.

**Target zero não completa a meta.** `target <= 0` devolve fração 0 e `isComplete == false`, com warning no log. Uma meta malformada aparecendo como anel cheio esconde o bug de quem a criou.

**Snapshot com mais de quatro metas trunca.** Fica nas quatro primeiras e loga `.error`. Um `init` de modelo que lança complicaria toda a cadeia por um caso que é bug de chamador.

**`isCumulative` é `true` para as sete métricas.** O flag existe porque a camada de query escolhe `.cumulativeSum` com base nele; só vira `false` se entrar peso ou frequência cardíaca.

**`.macOS(.v14)` na lista de plataformas.** Não é plataforma de produto. Está ali só para `swift test` rodar numa máquina de CI sem Xcode: sem um mínimo de macOS declarado, nem o `Logger` compila.

**O package não sincroniza nada.** Ele produz `DailySnapshot` e para por aí. Publicar, receber o dos colegas, enviar lembrete e resolver conflito são responsabilidade da camada de sincronização.

**E não sincroniza entre iPhone e Watch tampouco.** O cache é local a cada aparelho. Para metas monitoradas isso não importa, porque o próprio sistema espelha as amostras do HealthKit do relógio para o telefone.

**Meta manual ficou de fora por completo.** Um check de "ler 20 páginas" não tem relação nenhuma com HealthKit, o app já é dono desse estado e já o publica no backend. Deixar o SDK guardar isso criaria um segundo dono do mesmo fato. O app junta as duas origens na hora de montar os anéis, que é onde ele já conhece os dois lados.
