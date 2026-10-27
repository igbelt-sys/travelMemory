# Dados e segurança

## Isolamento

Toda consulta parte de `users/{uid}/travel_entries`, com UID obtido do Firebase Authentication. A listagem usa `orderBy('createdAt', descending: true).snapshots()`, sem consulta global ou filtragem posterior. A sessão é conferida antes das operações e após etapas assíncronas. A troca de conta descarta as rotas, os dados visíveis e as assinaturas anteriores.

`TravelEntry` converte documentos tipados, valida texto, tipos, caminho e coordenadas. `createdAt` usa `FieldValue.serverTimestamp()`; uma leitura pendente pode retornar null, exibido sem substituir pelo relógio local. Documentos sem `createdAt` não participam da consulta ordenada.

## Firestore

`firestore.rules` permite leitura, criação e exclusão somente se houver sessão e `request.auth.uid == uid`. Atualização e caminhos não declarados são negados. Na criação:

- Nome e descrição obrigatórios, não vazios, limitados a 120 e 2.000 unidades UTF-16.
- Campos extras/ausentes e tipos incorretos são recusados.
- `location` deve ser GeoPoint ou null; o cliente também valida os intervalos.
- `createdAt` deve corresponder ao timestamp do servidor (`request.time`).
- Foto local: `imageSource: "local"`, `imageUrl: null`, caminho relativo do mesmo usuário/registro.
- Sem foto: `imageUrl` e `imagePath` ambos null, sem origem de imagem.
- Foto Storage: URL HTTPS e caminho privado do mesmo usuário/registro; origem ausente ou "storage".

Os seis campos originais continuam presentes. O modo local acrescenta somente `imageSource`. Caminhos não podem apontar para pastas de outro usuário/registro nem conter níveis adicionais.

## Storage

`storage.rules` permite ao dono criar e obter objetos conhecidos em `users/{uid}/travel_entries/{entryId}/{nomeDoArquivo}`. Somente JPEG, PNG e WebP são aceitos, com extensão/MIME correspondentes e tamanho de 1 byte até 10 MiB. Sobrescrita, alteração de metadados e listagem são negadas.

A exclusão exige o dono e a ausência do documento correspondente no Firestore `(default)`. Isso permite limpar um upload órfão ou remover a foto depois de excluir a memória, preservando a foto de um registro confirmado. Uma escrita ainda em trânsito não é protegida apenas por essa regra: o cliente também conserva a imagem até reconciliar respostas incertas.

As regras validam metadados e tamanho; assinatura e decodificação dos bytes são verificadas no cliente, sem promessa de inspeção de conteúdo no servidor. O modo local não acessa Storage.

## Fotos e URLs

Arquivos locais são protegidos pelo diretório privado do sistema operacional e pelas verificações de sessão/caminho do app, não pelas regras do Firebase Storage. Não há sincronização ou criptografia própria. Veja [limitações dos arquivos locais](local-photos.md).

Uma URL `imageUrl` do Firebase Storage com token pode ser usada por qualquer pessoa com o link completo, mesmo deslogada. As regras não impedem esse compartilhamento. Não exponha essas URLs em logs públicos. O teste de regras confirma tanto o download via token sem sessão quanto a negação de leitura anônima pelo SDK sem token.

## Testes e implantação

```powershell
npm ci --prefix tests/firebase
firebase emulators:exec --only "firestore,storage" --project demo-wanderlog "npm --prefix tests/firebase test"
```

São 12 testes, com dono, outra identidade e visitante, incluindo leitura, consulta ordenada, criação, exclusão, edição negada, dados inválidos, limites e acesso por token. As identidades são simuladas somente nos emuladores; não substituem duas contas reais do Authentication.

Para implantação manual, revise o destino e o conteúdo:

```powershell
firebase deploy --project travelmemory-5822e --only firestore:rules
```

Somente Firestore foi publicado nesta entrega, com autorizações anteriores para cada alteração de contrato. Storage permanece pendente de recurso disponível e implantação separada; o projeto mantém o plano atual. `firestore.indexes.json` não exige índices compostos, pois a consulta usa apenas o índice automático de `createdAt`. Nenhuma implantação é feita ao executar os testes.
