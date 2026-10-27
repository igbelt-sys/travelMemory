# Fotos locais e exclusão

## Armazenamento

O aplicativo instalado copia a imagem selecionada para `getApplicationDocumentsDirectory()`, usando `path_provider`. Não depende do caminho temporário devolvido pelo seletor. O Firestore armazena somente os metadados:

```text
imageSource: "local"
imageUrl: null
imagePath: "users/{uid}/travel_entries/{entryId}/memoria.png"
```

O caminho é relativo ao diretório permanente do app e a extensão corresponde ao formato real. JPEG, PNG e WebP são validados por tamanho, assinatura, MIME e decodificação, até 10 MiB. A cópia é escrita em arquivo temporário e renomeada; um arquivo existente diferente não é sobrescrito.

O serviço confere sessão e caminho antes/depois das etapas assíncronas. Não aceita caminhos absolutos, travessia de diretórios ou outro usuário/registro. Nome, memória, GeoPoint/null e timestamp continuam no fluxo Firestore. Memórias antigas com URL do Storage e memórias sem foto permanecem compatíveis.

## Limitações

- A foto continua disponível ao reiniciar e entrar na mesma conta na mesma instalação. Reautenticar não baixa fotos do Firestore.
- Outro aparelho/navegador acessa texto e coordenadas, mas não possui o arquivo; o app mostra “Foto não disponível neste dispositivo”.
- Desinstalar, limpar dados ou perder o aparelho pode perder as imagens. Não há backup/sincronização de fotos.
- A Web permite criar memórias sem foto e exibe a indisponibilidade de fotos locais de outro dispositivo.
- O sistema operacional protege o diretório privado; não há criptografia própria. Regras Storage não controlam esses arquivos.
- Essa adaptação não comprova o requisito original de upload no Firebase Storage e URL de download.

## Excluir

Nos detalhes, toque em **Excluir memória**, na lixeira, e confirme **Excluir**. **Cancelar** preserva o registro. A ação não pode ser desfeita.

O serviço lê os dados atuais e exclui o documento em uma transação Firestore, que exige conexão. Após a confirmação, remove somente a cópia local correspondente ou o objeto Storage de um registro antigo. O original da galeria é mantido. Memórias sem foto não acessam arquivos/Storage.

Durante a operação, a tela mostra progresso e bloqueia cliques repetidos e retorno. Falha no Firestore conserva os detalhes e a foto; uma nova tentativa usa o mesmo ID. Resposta incerta não dispara limpeza prematura nem falso sucesso. Falha posterior na remoção da foto gera um aviso separado da exclusão já confirmada.

Banco e arquivos não são atômicos: interrupção do processo pode deixar foto órfã. Excluir por outro dispositivo não apaga arquivos do dispositivo original. Não há limpeza automática de órfãos.

## Verificação

Testes automatizados cobrem cópia persistente, sessão, caminhos, arquivo ausente, exclusão exata sem afetar outras fotos, falha/retomada, duplicação, confirmação/cancelamento e limpeza após remover o documento. Arquivos temporários reais são usados nos testes de disco. As regras negam exclusão a outra identidade/visitante nos emuladores.

No BlueStacks com Firebase real, um registro temporário com foto da galeria foi salvo, aberto e excluído, sem aviso de falha de limpeza; a lista permaneceu sem ele após reiniciar. As memórias anteriores foram preservadas. A inspeção direta do diretório privado Android pelo ADB não foi permitida; não foi tratada como verificação independente do arquivo no dispositivo.

Para repetir, crie uma memória de teste, confira foto/detalhes e persistência após reiniciar; cancele uma exclusão e depois confirme. Confira a ausência do documento no Console e a presença do original na galeria. Repita sem foto e teste perda de conexão. O ensaio com duas contas reais permanece manual, conforme [README](../README.md).
