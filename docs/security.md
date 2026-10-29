# Segurança e dados

Cada conta acessa suas próprias memórias no Firestore, armazenadas em `users/{uid}/travel_entries/{entryId}`. As regras em [firestore.rules](../firestore.rules) restringem o acesso à pessoa autenticada que é dona desses registros.

As fotos ficam na pasta privada do aplicativo. `imagePath` guarda somente o caminho relativo local para a foto; esse caminho não envia o arquivo ao Firebase. Veja [fotos locais](local-photos.md).

Os arquivos de configuração Firebase do app identificam o projeto e podem ser necessários para executar o cliente. Não adicione ao repositório senhas, tokens ou credenciais administrativas.
