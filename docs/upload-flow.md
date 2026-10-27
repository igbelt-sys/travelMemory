# Salvamento e upload

O formulário atual usa foto local opcional, conforme [fotos locais](local-photos.md). O fluxo original Firebase Storage permanece no serviço para uso futuro, sem serviço externo, imagem fictícia ou resposta simulada em produção.

## Tentativa de salvamento

1. Valida nome, memória, coordenadas e, quando presente, imagem real. Texto usa os limites 120/2.000; JPEG/PNG/WebP usam assinatura, MIME, decodificação e limite de 10 MiB.
2. Confere o UID autenticado e reserva um único ID, sem gravar documento incompleto.
3. Cria `TravelUploadAttempt`, mantendo UID, ID, dados e caminho imutáveis nas retomadas.
4. Sem foto, segue diretamente ao Firestore. Com foto local, copia para o diretório permanente e grava `imageSource: "local"`, URL nula e caminho relativo.
5. No modo Storage (`savePhotoLocally: false` no serviço), envia `putData` ao caminho `users/{uid}/travel_entries/{entryId}/memoria.{extensão}`, acompanha `snapshotEvents` e aguarda `getDownloadURL()`.
6. Grava os metadados com GeoPoint/null e timestamp do servidor.
7. Confirma sucesso somente após o Future da gravação concluir e a sessão ainda corresponder ao dono. A lista recebe o registro pelo stream do Firestore.

No modo local, o progresso indica a cópia/gravação; não representa um upload remoto. O modo Storage não está selecionado no formulário atual e exige bucket disponível, regras implantadas e os requisitos de faturamento descritos no [README](../README.md).

## Robustez

- Salvar e controles incompatíveis são bloqueados imediatamente. Chamadas concorrentes compartilham a mesma tentativa/Future, evitando duplicação.
- Cancelar a galeria não apresenta erro; trocar a foto substitui a prévia somente depois de validar a nova imagem.
- Falhas preservam campos e foto. Repetir sem alterar dados mantém o ID.
- Antes da escrita Firestore, o envio pode ser cancelado. Após a escrita ser submetida, o SDK não oferece cancelamento; o app aguarda o resultado.
- Falha anterior à escrita ou rejeição definitiva tenta remover somente a imagem daquela tentativa, mantendo o erro original e a falha de limpeza separados.
- Uma resposta incerta conserva a foto e exige **Verificar envio**, consultando o mesmo ID com `Source.server`. Um snapshot com escrita pendente não confirma sucesso. Se já existe, não duplica upload/documento; se o servidor confirma ausência, permite retomar.
- No Storage, uma retomada verifica metadados do objeto já iniciado, inclusive se a confirmação do upload se perdeu. Evita sobrescrita proibida pelas regras.
- Troca/encerramento de sessão interrompe etapas ainda canceláveis e impede sucesso para outra conta. As rotas privadas são descartadas e retornos assíncronos verificam `mounted`.

Não há transação conjunta entre banco e arquivos nem rascunho persistente. Uma escrita pode aguardar conexão. O app não usa um timeout que permitiria duplicar uma gravação ainda em trânsito. Ao encerrar o processo, callbacks de limpeza não são garantidos; confira a lista antes de repetir.

## Formatos e permissões

A extensão corresponde aos bytes recebidos, sem fingir conversão. O seletor solicita redução para até 1.920 pixels e qualidade 85, mas o resultado é validado novamente. HEIC, GIF, SVG e imagens corrompidas são recusados quando não retornam em um formato realmente suportado.

Android usa a galeria/Photo Picker, sem acesso amplo ao armazenamento. `retrieveLostData()` recupera a seleção quando o sistema recria a atividade. iOS possui descrição de biblioteca de fotos, sem câmera/microfone. Na Web, a inclusão de foto local fica desativada; memórias sem foto continuam funcionando.

## Verificação

Os testes Flutter injetam falhas de imagem, upload, URL, escrita, resposta perdida, sessão, cancelamento e limpeza. Os testes de regras usam [Emulator Suite](security.md). Nenhum teste simulado é apresentado como upload real no Firebase Storage.

O fluxo local já foi validado no BlueStacks com Firebase real, incluindo foto, lista, detalhes e exclusão. Para uma futura validação do Storage, configure o recurso e selecione explicitamente esse modo no formulário. Confirme a ordem upload → URL → documento, o objeto e os campos no Console. Teste falha de rede, duplicação, ausência de localização e isolamento entre duas contas sem abrir regras públicas.
