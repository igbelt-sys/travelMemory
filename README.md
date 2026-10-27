# WanderLog

Diário visual de viagens da agência **Mundo Afora**, desenvolvido em Flutter com Firebase para uma atividade do SENAI. Interface em português do Brasil, Material 3, verde-petróleo, fundo claro e detalhes em coral.

## Funcionalidades

- Cadastro, login e logout com Firebase Authentication (e-mail e senha).
- Memórias privadas por usuário, com nome do local, descrição e foto opcional da galeria.
- Fotos locais copiadas para o diretório permanente do aplicativo, com prévia e troca da imagem.
- Latitude/longitude opcionais, digitadas ou capturadas pelo botão **Usar minha localização**.
- Firestore em tempo real, ordenado do registro mais recente para o mais antigo.
- Detalhes com foto, memória completa, data em português e coordenadas quando disponíveis.
- Exclusão com confirmação, espera pelo servidor e limpeza da cópia da foto.
- Feedback de carregamento, falhas, permissão e progresso; proteção contra envio duplicado.

O modo atual usa **foto local**, sem depender do Firebase Storage. A imagem funciona na mesma instalação: não é sincronizada entre aparelhos e pode ser perdida ao desinstalar o app ou limpar seus dados. Na Web, é possível usar o diário sem foto; fotos locais de outro dispositivo aparecem como indisponíveis. A alternativa original com Firebase Storage permanece implementada no serviço e coberta por testes, mas não está selecionada no formulário atual.

Essa adaptação segue a proposta de armazenar a imagem no dispositivo. **Não substitui a comprovação do requisito original de upload no Storage e obtenção da URL de download.** Veja [fotos locais e exclusão](docs/local-photos.md).

## Ambiente e dependências

Versões usadas: **Flutter 3.38.9 / Dart 3.10.8**, Android mínimo API 24, AGP 8.11.1, Gradle 8.14 e Kotlin 2.2.20. O `pubspec.lock` deve ser mantido para reproduzir as versões.

| Dependência | Versão | Uso |
| --- | --- | --- |
| firebase_core | 4.4.0 | Inicialização |
| firebase_auth | 6.1.4 | Conta e sessão |
| cloud_firestore | 6.1.2 | Documentos, consulta e GeoPoint |
| firebase_storage | 13.0.6 | Fluxo alternativo de upload |
| image_picker | 1.2.3 no lockfile | Galeria e recuperação Android |
| geolocator / geolocator_android | 14.0.2 / 5.0.2 | Captura opcional de coordenadas |
| path_provider / path_provider_android | 2.1.5 / 2.2.17 | Diretório permanente de fotos |
| path / mime | 1.9.1 / 2.1.0 no lockfile | Caminhos e validação de formato |
| flutter_localizations | SDK Flutter | Interface e datas em pt-BR |

Android e Web possuem configuração real. O projeto iOS foi preservado, com permissões e mínimo iOS 15, mas ainda exige configuração Firebase e validação em macOS/Xcode.

## Executar

```powershell
git clone https://github.com/igbelt-sys/travelMemory.git
cd travelMemory
flutter pub get
flutter doctor -v
flutter devices
flutter run -d chrome
```

Para usar o BlueStacks, habilite o ADB nas configurações dele e execute:

```powershell
adb connect 127.0.0.1:5555
flutter run -d 127.0.0.1:5555
```

Em outro Android, use o ID exibido por `flutter devices`. O dispositivo precisa de internet para Authentication/Firestore. Para gerar um APK de depuração:

```powershell
# BlueStacks x86_64:
flutter build apk --debug --target-platform android-x64
# Aparelho ARM64:
flutter build apk --debug --target-platform android-arm64
```

O resultado fica em `build/app/outputs/flutter-apk/app-debug.apk`. Builds, caches, logs, capturas de diagnóstico e configurações locais de IDE não são versionados.

## Configuração do Firebase

Projeto configurado: **`travelmemory-5822e`**. Pacote Android: `br.com.mundoafora.wanderlog`.

- Authentication: provedor **E-mail/senha** habilitado.
- Firestore: banco Standard `(default)`, região **southamerica-east1 (São Paulo)**.
- `lib/firebase_options.dart`, `android/app/google-services.json`, `.firebaserc` e `firebase.json` preservam a configuração Android/Web.
- As regras Firestore, incluindo fotos locais e exclusão pelo dono, foram publicadas com autorização do responsável.
- Storage não foi provisionado nesta entrega; o responsável optou por manter o plano Spark. Nenhum faturamento foi alterado.

Os arquivos Firebase versionados são configuração pública do cliente, não contas de serviço. Não inclua senhas, tokens de CLI, chaves de administração, arquivos `.env` ou chaves de assinatura no repositório. O acesso aos dados depende das regras e da sessão autenticada.

Para configurar seu próprio projeto, habilite E-mail/senha, crie o Firestore em modo de produção/restrito e escolha a região considerando proximidade dos usuários, latência e custos. Revise a região antes de criar os recursos. Depois execute o [FlutterFire CLI](https://firebase.google.com/docs/flutter/setup):

```powershell
firebase login
dart pub global activate flutterfire_cli
# Substitua pelo ID do projeto sob sua responsabilidade:
flutterfire configure --project=SEU_ID_DE_PROJETO --platforms=android,web --android-package-name=br.com.mundoafora.wanderlog
```

A inicialização usa as opções geradas, sem encaminhamento aos emuladores. Os testes de regras são separados e usam apenas `demo-wanderlog`.

### Storage e faturamento

A [documentação oficial do Firebase](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024), consultada em **27/10/2026**, informa que Cloud Storage exige o plano **Blaze**, vinculado a uma conta de faturamento. Cotas sem custo não dispensam esse requisito e pode haver cobrança conforme o uso. Consulte também a [tabela oficial de preços](https://firebase.google.com/pricing).

O arquivo de opções pode conter um nome de bucket sem que o bucket esteja provisionado. O responsável precisa verificar sua existência e região no Console antes de usar o fluxo Storage. Esta aplicação não altera o plano nem cria serviços pagos automaticamente.

### Regras e índices

Revise projeto e arquivos antes de uma implantação manual:

```powershell
firebase deploy --project travelmemory-5822e --only firestore:rules
```

Esse comando envia apenas `firestore.rules`. A consulta por `createdAt` usa o índice automático descendente de campo único; não exige índice composto. `firestore.indexes.json` fica preservado, sem índices adicionais. Se índices forem adicionados, revise os existentes antes de publicar `firestore:indexes`.

Para uma futura ativação do Storage, depois de provisionar o bucket e revisar `storage.rules`, a implantação separada é `firebase deploy --project travelmemory-5822e --only storage`. A regra de limpeza consulta a existência do documento Firestore e pode exigir a permissão de integração entre os serviços. Não use permissões públicas para contornar erros. Veja [segurança e testes](docs/security.md).

## Estrutura

```text
lib/
  main.dart              # Inicialização, idioma e aplicativo
  firebase_options.dart  # Configuração gerada pelo FlutterFire
  models/                # TravelEntry: conversão e validação
  screens/               # Sessão, autenticação, lista, formulário e detalhes
  services/              # Auth, Firestore/Storage, fotos e localização
  theme/                 # Identidade Material 3
  widgets/               # Cartões e exibição de fotos
android/                 # Aplicativo Android
ios/                     # Projeto iOS preservado, ainda não validado
web/                     # Aplicativo Web
test/                    # Testes Dart e de interface
tests/firebase/          # Testes da Emulator Suite
docs/                    # Fluxos, segurança e limitações
```

As telas cuidam de navegação e feedback; os serviços coordenam persistência, sessão e operações assíncronas. O `AuthGate` descarta as rotas privadas ao sair ou trocar de conta. Não há API própria, feed público, mapas ou consulta global filtrada no cliente.

## Contrato dos dados

Firestore: `users/{uid}/travel_entries/{entryId}`.

Foto local: caminho relativo `users/{uid}/travel_entries/{entryId}/memoria.{extensão}` dentro do diretório de documentos do app. Para o fluxo Storage, o mesmo caminho identifica o objeto do bucket.

| Campo | Valor |
| --- | --- |
| placeName | String obrigatória, até 120 caracteres |
| description | String obrigatória, até 2.000 caracteres |
| imageUrl | URL HTTPS no modo Storage; null para foto local ou memória sem foto |
| imagePath | Caminho da foto local/Storage; null sem foto |
| imageSource | "local" para foto local; "storage" ou ausente para documentos antigos com URL |
| location | GeoPoint ou null |
| createdAt | Timestamp do servidor |

JPEG, PNG e WebP são aceitos até **10 MiB**, com assinatura, MIME e decodificação validados. Não se renomeia a extensão para fingir conversão. Latitude e longitude devem ser informadas juntas, nos intervalos [-90, 90] e [-180, 180]. Dois campos vazios salvam `null`; 0,0 nunca substitui localização desconhecida. Datas pendentes mostram “Sincronizando data…”.

**Privacidade:** uma URL de download do Storage com token pode ser aberta por quem possuir o link, mesmo sem sessão. As regras não impedem esse compartilhamento. O modo local não gera URL de download e não envia a foto ao Firestore.

## Verificar e testar

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release --no-wasm-dry-run
```

Para as regras, instale Node.js 20+ e Java 21+, com as portas 8080 e 9199 livres:

```powershell
npm ci --prefix tests/firebase
firebase emulators:exec --only "firestore,storage" --project demo-wanderlog "npm --prefix tests/firebase test"
```

A suíte limpa somente dados dos emuladores entre cenários. Não a aponte ao projeto remoto. Testes Flutter usam serviços controlados, banco em memória e arquivos temporários; não comprovam sozinhos a integração remota. Testes de regras cobrem dono, outra identidade, visitante, dados inválidos, limites, exclusão e acesso por token.

### Evidências e limites

Em 27/10/2026 foram aprovados **109 testes Flutter**, **12 testes de regras**, análise estática e builds Android debug x86_64/Web release. O fluxo de foto local e a exclusão já foram exercitados no BlueStacks conectado ao Firebase real: registro temporário com foto salvo, aberto, excluído e ausência confirmada após reiniciar; memórias anteriores preservadas. Captura e gravação de GeoPoint também foram conferidas no emulador.

| Critério | Situação |
| --- | --- |
| Cadastro/login reais | Confirmados pelo usuário; logout implementado e testado em widgets |
| Foto da galeria e cópia local | Implementados; funcionamento confirmado no BlueStacks |
| Upload/URL no Storage | Implementados no serviço e testados localmente; validação remota pendente de Storage disponível |
| Firestore, lista, detalhes e GeoPoint | Testes automatizados e fluxo real no BlueStacks |
| Exclusão e preservação do original | Confirmação/cancelamento e exclusão reais; remoção de arquivo exato também testada com arquivos temporários |
| Isolamento entre contas | Testado nos emuladores e widgets; ensaio com duas contas reais pendente |
| Falhas sem falso sucesso | Testes de upload, gravação, limpeza, sessão, duplicação e confirmação perdida |

O APK é de depuração e a configuração release ainda utiliza assinatura debug; não é uma distribuição de produção. iOS, GPS físico e o roteiro completo com duas contas reais permanecem pendentes. Não há rascunho persistente nem limpeza automática de fotos órfãs. Interromper o processo pode deixar resultados incertos; confira a lista antes de repetir. Banco e arquivos não são atualizados atomicamente.

## Demonstração para o professor

1. Entre na conta A e abra **Nova memória**. Ative **Incluir foto**, selecione uma imagem e confira a prévia/troca.
2. Informe nome, memória e coordenadas manuais ou use **Usar minha localização**; salve e aguarde a confirmação.
3. Abra o cartão e confira imagem, data, texto e coordenadas. No Console, verifique o documento privado, GeoPoint, timestamp e caminho relativo; a foto local não estará no bucket.
4. Salve outra memória sem localização e confira `location: null`. Reinicie o aplicativo para conferir a persistência da foto na mesma instalação.
5. Saia, entre na conta B e confirme que ela não vê as memórias de A. Volte à conta A.
6. Abra uma memória de teste, cancele a exclusão e depois confirme. Confira a lista e o original da galeria.
7. Demonstre campos inválidos, uma coordenada ausente, cancelamento da galeria e falha de conexão, sem falso sucesso.
8. Explique a adaptação de fotos locais e a pendência do requisito original de Storage, sem apresentá-lo como teste remoto concluído.

Detalhes: [localização atual](docs/current-location.md), [salvamento e upload](docs/upload-flow.md), [fotos locais e exclusão](docs/local-photos.md), [segurança](docs/security.md).
