# Fotos locais

As fotos são copiadas para a pasta privada do app. No Firestore, `imagePath` deve conter somente um caminho relativo local, por exemplo:

```text
users/{uid}/travel_entries/{entryId}/memoria.jpg
```

O arquivo não é enviado nem sincronizado com outros dispositivos. Ele pode ser perdido se os dados do app forem apagados. No navegador, memórias podem ser criadas sem foto.

Ao excluir uma memória, o app também tenta apagar sua cópia local. O original da galeria é mantido.
