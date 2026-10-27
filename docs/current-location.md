# Localização atual opcional

**Usar minha localização** inicia uma única captura após o toque. Abrir a tela não consulta sensores nem solicita permissão. O serviço verifica plataforma, serviço habilitado e permissão. A posição tem limite de 15 segundos; as verificações preliminares têm limite de cinco segundos cada. O tempo de resposta ao diálogo nativo de permissão não é contado como aquisição da posição.

Latitude e longitude retornadas preenchem o formulário e continuam editáveis. Dois campos vazios salvam `location: null`; valores válidos viram GeoPoint. Latitude deve estar em [-90, 90] e longitude em [-180, 180], informadas juntas. Zero só é usado quando informado ou retornado como posição real, nunca como substituto.

Recusa, bloqueio permanente, serviço desligado, timeout, falha e plataforma sem suporte têm mensagens próprias. Falhas preservam valores anteriores. Durante a captura, as ações incompatíveis ficam bloqueadas. Sair/trocar de conta ignora resultados tardios e impede próximas etapas; diálogos do sistema já abertos podem continuar visíveis. Não há rastreamento contínuo ou localização em segundo plano.

## Plataformas

- Android: somente `ACCESS_COARSE_LOCATION` e `ACCESS_FINE_LOCATION`; localização aproximada é aceita. `forceLocationManager: true` evita depender do Fused Provider do Google Play Services no BlueStacks. Se não houver posição disponível, o usuário pode preencher manualmente ou continuar sem localização.
- iOS 15+: somente `NSLocationWhenInUseUsageDescription`. O Podfile aplica `BYPASS_PERMISSION_LOCATION_ALWAYS=1`. Configuração Firebase, CocoaPods e execução ainda exigem macOS/Xcode e não foram validados neste Windows.
- Web: HTTPS ou localhost, com navegador que suporte Geolocation. A captura faz o pedido de permissão, evitando uma segunda leitura sem limite. Não há novos alvos desktop.

As versões do Geolocator estão fixadas no `pubspec.yaml` para compatibilidade com o ambiente descrito no [README](../README.md).

## Teste em aparelho físico

1. Execute o app e abra **Nova memória**. Nenhum pedido deve aparecer antes do toque.
2. Toque em **Usar minha localização**, permita durante o uso e confira as coordenadas. Edite-as se desejar e salve; confira GeoPoint no Firestore e nos detalhes.
3. Negue a permissão. O formulário deve permanecer utilizável, com coordenadas manuais ou sem localização.
4. Bloqueie a permissão nas configurações e tente novamente; deve aparecer orientação. O comportamento de bloqueio permanente varia pelo sistema.
5. Desligue o serviço de localização e confira a mensagem. Depois ative e teste uma situação sem posição disponível para conferir timeout/falha.
6. Durante a captura, tente tocar novamente, salvar ou sair. Não deve haver captura duplicada, gravação incompatível ou preenchimento em outra sessão.

## Emulador e navegador

- Android Emulator: **Extended controls > Location**, envie uma posição e capture pelo app. Redefina permissões nas configurações para repetir cenários de recusa. Um emulador sem posição pode retornar timeout ou falha, ambos tratados.
- BlueStacks: habilite localização nas configurações do Android e forneça uma posição pelo recurso do emulador, se disponível. A captura automática já foi conferida com GeoPoint salvo no Firebase real; isso não comprova GPS em aparelho físico.
- iOS Simulator: em macOS, use **Features > Location > Custom Location**. Build/execução permanecem pendentes.
- Chrome: execute em localhost; use permissões do site e **DevTools > More tools > Sensors** para fornecer coordenadas, bloquear ou simular indisponibilidade.

Testes automáticos usam a interface controlada do plugin para conferir ordem das verificações, tipos de falha, preenchimento, GeoPoint/null, bloqueios e descarte de resultados após saída. Eles não acionam sensores nem diálogos reais. A suíte e os resultados gerais estão no [README](../README.md).
