# WanderLog

Diário de viagens da agência Mundo Afora. O app permite criar uma conta, guardar memórias de lugares, adicionar fotos locais e registrar coordenadas.

## Executar

Requisitos: Flutter instalado e um dispositivo Android, emulador ou navegador.

```powershell
flutter pub get
flutter devices
flutter run -d ID_DO_DISPOSITIVO
```

Para rodar no Chrome, use `flutter run -d chrome`. Para abrir o emulador Android criado para o projeto, inicie `WanderLog_Pixel_8_API_36` pelo Android Emulator e rode `flutter run -d emulator-5554`.

## Dados e fotos

O Firebase Authentication gerencia as contas e o Cloud Firestore guarda as memórias. As regras ficam em [firestore.rules](firestore.rules).

As fotos são guardadas no aparelho. O campo `imagePath` deve conter um caminho relativo local dentro da pasta privada do app. Fotos não são sincronizadas entre dispositivos; no navegador, é possível salvar memórias sem foto.

## Pastas

- `lib`: código do aplicativo.
- `android`, `ios`, `web`: versões para cada plataforma.
- `docs`: informações sobre fotos, localização e segurança.

Veja [fotos](docs/local-photos.md), [localização](docs/current-location.md), [segurança](docs/security.md) e [salvamento](docs/upload-flow.md).
