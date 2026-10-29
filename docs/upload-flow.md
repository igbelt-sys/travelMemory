# Como uma memória é salva

O app valida o nome do lugar, o texto, as coordenadas e, se houver, a foto. A foto selecionada é copiada para a pasta privada do app. No Firestore, `imagePath` recebe apenas o caminho relativo local; os dados da memória são salvos na conta da pessoa.

As fotos não são sincronizadas entre dispositivos. Se a pessoa usar outro aparelho ou navegador, verá o texto e as coordenadas, mas não terá a foto local. No navegador, é possível salvar sem foto.

Ao excluir uma memória, o app remove o registro do Firestore e tenta apagar a cópia local correspondente. O arquivo original da galeria não é alterado.
