import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, getDocs, collection, updateDoc, deleteDoc, query, orderBy, serverTimestamp, Timestamp, GeoPoint } from 'firebase/firestore';
import { ref, uploadBytes, getBytes, getDownloadURL, deleteObject, listAll, updateMetadata } from 'firebase/storage';

let environment;
const path = 'users/ana/travel_entries/viagem';
const imagePath = `${path}/memoria.jpg`;
const photo = new Uint8Array([0xff, 0xd8, 0xff, 0xe0]);
const data = (changes = {}) => ({ placeName: 'Praia do Rosa', description: 'Um dia especial',
  imageUrl: 'https://firebasestorage.googleapis.com/photo.jpg', imagePath,
  location: new GeoPoint(-28.12, -48.64), createdAt: serverTimestamp(), ...changes });

before(async () => {
  environment = await initializeTestEnvironment({ projectId: 'demo-wanderlog',
    firestore: { host: '127.0.0.1', port: 8080, rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8') },
    storage: { host: '127.0.0.1', port: 9199, rules: readFileSync(new URL('../../storage.rules', import.meta.url), 'utf8') },
  });
});
beforeEach(async () => {
  await environment.clearFirestore();
  // clearStorage() desta versão limpa somente itens na raiz. As fotos do app
  // ficam em subpastas; percorrer os prefixos evita resíduos entre os testes.
  await environment.withSecurityRulesDisabled(async (context) => {
    async function clearFolder(folder) {
      const { items, prefixes } = await folder.listAll();
      await Promise.all([
        ...items.map((item) => item.delete()),
        ...prefixes.map(clearFolder),
      ]);
    }
    await clearFolder(context.storage().ref());
  });
});
after(async () => { await environment?.cleanup(); });

test('dono cria, consulta e lista seus registros com GeoPoint ou null', async () => {
  const db = environment.authenticatedContext('ana').firestore();
  await assertSucceeds(setDoc(doc(db, path), data()));
  await assertSucceeds(getDoc(doc(db, path)));
  await assertSucceeds(getDocs(collection(db, 'users/ana/travel_entries')));
  await assertSucceeds(getDocs(query(collection(db, 'users/ana/travel_entries'), orderBy('createdAt', 'desc'))));
  await assertSucceeds(setDoc(doc(db, 'users/ana/travel_entries/sem-local'), data({
    imagePath: 'users/ana/travel_entries/sem-local/memoria.jpg', location: null,
  })));
});

test('memória sem foto aceita GeoPoint/null e continua privada e validada', async () => {
  const owner = environment.authenticatedContext('ana').firestore();
  const noPhoto = data({ imageUrl: null, imagePath: null });
  await assertSucceeds(setDoc(doc(owner, path), noPhoto));
  await assertSucceeds(getDoc(doc(owner, path)));
  for (const context of [environment.authenticatedContext('bia'), environment.unauthenticatedContext()]) {
    await assertFails(getDoc(doc(context.firestore(), path)));
    await assertFails(setDoc(doc(context.firestore(), 'users/ana/travel_entries/novo'), noPhoto));
  }
  await assertSucceeds(setDoc(doc(owner, 'users/ana/travel_entries/sem-local-sem-foto'), data({imageUrl: null, imagePath: null, location: null})));
  for (const changes of [{imagePath: null}, {imageUrl: null}, {imageUrl: '', imagePath: ''},
    {imageUrl: null, imagePath: null, location: 'inválida'}, {imageUrl: null, imagePath: null, placeName: ''}]) {
    await assertFails(setDoc(doc(owner, 'users/ana/travel_entries/invalida'), data(changes)));
  }
});

test('foto local aceita somente caminho do dono/registro e não exige URL fictícia', async () => {
  const owner = environment.authenticatedContext('ana').firestore();
  const localPhoto = data({ imageUrl: null, imageSource: 'local' });
  await assertSucceeds(setDoc(doc(owner, path), localPhoto));
  await assertSucceeds(getDoc(doc(owner, path)));
  for (const context of [environment.authenticatedContext('bia'), environment.unauthenticatedContext()]) {
    await assertFails(getDoc(doc(context.firestore(), path)));
    await assertFails(setDoc(doc(context.firestore(), 'users/ana/travel_entries/local-invasao'), data({
      imageUrl: null, imageSource: 'local', imagePath: 'users/ana/travel_entries/local-invasao/foto.jpg',
    })));
  }
  let invalidIndex = 0;
  for (const changes of [
    { imageSource: 'local', imagePath: null, imageUrl: null },
    { imageSource: 'local', imageUrl: 'https://example.com/foto.jpg' },
    { imageSource: 'local', imagePath: '/data/user/0/app/foto.jpg', imageUrl: null },
    { imageSource: 'local', imagePath: 'users/bia/travel_entries/viagem/foto.jpg', imageUrl: null },
    { imageSource: 'local', imagePath: `${path}/../foto.jpg`, imageUrl: null },
    { imageSource: 'local', imagePath: `${path}/foto.gif`, imageUrl: null },
    { imageSource: 'qualquer' }, { imageSource: true },
    { imageSource: 'storage', imageUrl: null, imagePath: null },
  ]) {
    const invalidPath = `users/ana/travel_entries/invalida-${invalidIndex++}`;
    await assertFails(setDoc(doc(owner, invalidPath), data({ imagePath: `${invalidPath}/foto.jpg`, ...changes })));
  }
});

test('outra conta e visitante não podem ler, listar, criar ou alterar registros', async () => {
  const owner = environment.authenticatedContext('ana').firestore();
  await setDoc(doc(owner, path), data());
  for (const context of [environment.authenticatedContext('bia'), environment.unauthenticatedContext()]) {
    const db = context.firestore();
    await assertFails(getDoc(doc(db, path)));
    await assertFails(getDocs(collection(db, 'users/ana/travel_entries')));
    await assertFails(setDoc(doc(db, 'users/ana/travel_entries/invasao'), data({
      imagePath: 'users/ana/travel_entries/invasao/memoria.jpg',
    })));
    await assertFails(updateDoc(doc(db, path), { description: 'Alterada' }));
    await assertFails(deleteDoc(doc(db, path)));
  }
});

test('duas contas criam diários independentes e não consultam a pasta alheia', async () => {
  const ana = environment.authenticatedContext('ana');
  const bia = environment.authenticatedContext('bia');
  for (const [uid, context] of [['ana', ana], ['bia', bia]]) {
    const privatePath = `users/${uid}/travel_entries/viagem`;
    const privateImagePath = `${privatePath}/memoria.jpg`;
    await assertSucceeds(uploadBytes(ref(context.storage(), privateImagePath), photo, { contentType: 'image/jpeg' }));
    await assertSucceeds(setDoc(doc(context.firestore(), privatePath), data({
      placeName: `Viagem de ${uid}`, imagePath: privateImagePath,
    })));
  }
  for (const [uid, context] of [['ana', ana], ['bia', bia]]) {
    const ownEntries = await assertSucceeds(getDocs(query(
      collection(context.firestore(), `users/${uid}/travel_entries`), orderBy('createdAt', 'desc'))));
    if (ownEntries.size !== 1 || ownEntries.docs[0].data().placeName !== `Viagem de ${uid}`) {
      throw new Error('O diário deve conter somente o registro da própria conta.');
    }
    const otherUid = uid === 'ana' ? 'bia' : 'ana';
    await assertFails(getDocs(collection(context.firestore(), `users/${otherUid}/travel_entries`)));
    await assertFails(getBytes(ref(context.storage(), `users/${otherUid}/travel_entries/viagem/memoria.jpg`)));
  }
});

test('rejeita campos inválidos, timestamp do cliente e caminho de outro usuário', async () => {
  const db = environment.authenticatedContext('ana').firestore();
  for (const changes of [
    { placeName: '' }, { placeName: ' \n ' }, { placeName: 123 }, { placeName: 'x'.repeat(121) },
    { description: '' }, { description: '\n\t' }, { description: false }, { description: 'x'.repeat(2001) },
    { location: 'coordenadas' }, { location: { latitude: 1, longitude: 2 } },
    { createdAt: Timestamp.fromMillis(0) }, { createdAt: null }, { createdAt: 'agora' },
    { imagePath: 'users/bia/travel_entries/viagem/memoria.jpg' },
    { imagePath: 'users/ana/travel_entries/outro/memoria.jpg' },
    { imagePath: `${path}/pasta/foto.jpg` }, { imagePath: 12 },
    { imageUrl: '' }, { imageUrl: null }, { imageUrl: 12 }, { imageUrl: 'https://' },
    { extra: true }, { imageUrl: 'http://inseguro' },
  ]) await assertFails(setDoc(doc(db, path), data(changes)));
  for (const field of Object.keys(data())) {
    const missing = data();
    delete missing[field];
    await assertFails(setDoc(doc(db, path), missing));
  }
});

test('SDK exige dono para ler a foto e nega uploads fora da pasta', async () => {
  const storage = environment.authenticatedContext('ana').storage();
  await assertSucceeds(uploadBytes(ref(storage, imagePath), photo, { contentType: 'image/jpeg' }));
  await assertSucceeds(getBytes(ref(storage, imagePath)));
  for (const context of [environment.authenticatedContext('bia'), environment.unauthenticatedContext()]) {
    await assertFails(getBytes(ref(context.storage(), imagePath)));
    await assertFails(uploadBytes(ref(context.storage(), imagePath), photo, { contentType: 'image/jpeg' }));
    // Objeto novo: o teste não deve passar apenas pela proibição de sobrescrita.
    await assertFails(uploadBytes(ref(context.storage(), `${path}/invasao.jpg`), photo, { contentType: 'image/jpeg' }));
    await assertFails(deleteObject(ref(context.storage(), imagePath)));
  }
  await assertFails(uploadBytes(ref(storage, 'outra-pasta/memoria.jpg'), photo, { contentType: 'image/jpeg' }));
});

test('rejeita tipo, nome e tamanho inválidos, e impede sobrescrita', async () => {
  const storage = environment.authenticatedContext('ana').storage();
  await assertFails(uploadBytes(ref(storage, imagePath), photo, { contentType: 'text/plain' }));
  await assertFails(uploadBytes(ref(storage, `${path}/foto.svg`), photo, { contentType: 'image/svg+xml' }));
  await assertFails(uploadBytes(ref(storage, `${path}/foto.png`), photo, { contentType: 'image/jpeg' }));
  await assertFails(uploadBytes(ref(storage, `${path}/pasta/foto.jpg`), photo, { contentType: 'image/jpeg' }));
  await assertFails(uploadBytes(ref(storage, imagePath), new Uint8Array(0), { contentType: 'image/jpeg' }));
  await assertFails(uploadBytes(ref(storage, imagePath), new Uint8Array(10 * 1024 * 1024 + 1), { contentType: 'image/jpeg' }));
  await assertSucceeds(uploadBytes(ref(storage, imagePath), photo, { contentType: 'image/jpeg' }));
  await assertFails(uploadBytes(ref(storage, imagePath), photo, { contentType: 'image/jpeg' }));
  await assertFails(updateMetadata(ref(storage, imagePath), { contentType: 'image/png' }));
  await assertFails(listAll(ref(storage, 'users/ana/travel_entries')));
});

test('dono limpa upload órfão e não pode apagar foto de memória confirmada', async () => {
  const owner = environment.authenticatedContext('ana');
  const image = ref(owner.storage(), imagePath);
  await uploadBytes(image, photo, { contentType: 'image/jpeg' });
  await assertSucceeds(deleteObject(image));
  await uploadBytes(image, photo, { contentType: 'image/jpeg' });
  await setDoc(doc(owner.firestore(), path), data());
  await assertFails(deleteObject(image));
});

test('somente o dono exclui a memória, sem liberar edição; foto só é removida depois', async () => {
  const db = environment.authenticatedContext('ana').firestore();
  const image = ref(environment.authenticatedContext('ana').storage(), imagePath);
  await uploadBytes(image, photo, { contentType: 'image/jpeg' });
  await setDoc(doc(db, path), data());
  await assertFails(updateDoc(doc(db, path), { description: 'Nova descrição' }));
  await assertFails(deleteObject(image));
  for (const context of [environment.authenticatedContext('bia'), environment.unauthenticatedContext()]) {
    await assertFails(deleteDoc(doc(context.firestore(), path)));
  }
  await assertSucceeds(deleteDoc(doc(db, path)));
  if ((await getDoc(doc(db, path))).exists()) throw new Error('Memória ainda existe.');
  await assertSucceeds(deleteObject(image));
  await assertSucceeds(setDoc(doc(db, path), data({ imageSource: 'local', imageUrl: null })));
  await assertSucceeds(deleteDoc(doc(db, path)));
  await assertSucceeds(setDoc(doc(db, path), data({ imageUrl: null, imagePath: null })));
  await assertSucceeds(deleteDoc(doc(db, path)));
});

test('aceita limites exatos, texto multilinha e nomes de imagem suportados', async () => {
  const owner = environment.authenticatedContext('ana');
  await assertSucceeds(setDoc(doc(owner.firestore(), path), data({
    placeName: 'x'.repeat(120), description: 'x'.repeat(2000),
  })));
  await assertSucceeds(setDoc(doc(owner.firestore(), 'users/ana/travel_entries/unicode'), data({
    imagePath: 'users/ana/travel_entries/unicode/foto.jpg',
    placeName: '🌍'.repeat(60), description: '🌍'.repeat(1000),
  })));
  await assertSucceeds(setDoc(doc(owner.firestore(), 'users/ana/travel_entries/acentos'), data({
    imagePath: 'users/ana/travel_entries/acentos/foto.jpg',
    placeName: 'é'.repeat(120), description: 'é'.repeat(2000),
  })));
  await assertFails(setDoc(doc(owner.firestore(), 'users/ana/travel_entries/acima-unicode'), data({
    imagePath: 'users/ana/travel_entries/acima-unicode/foto.jpg', placeName: '🌍'.repeat(61),
  })));
  for (const [extension, type] of [['jpg', 'image/jpeg'], ['jpeg', 'image/jpeg'], ['png', 'image/png'], ['webp', 'image/webp']]) {
    const id = `foto-${extension}`;
    const objectPath = `users/ana/travel_entries/${id}/lembranca-01.${extension}`;
    await assertSucceeds(uploadBytes(ref(owner.storage(), objectPath), photo, { contentType: type }));
    await assertSucceeds(setDoc(doc(owner.firestore(), `users/ana/travel_entries/${id}`), data({
      imagePath: objectPath, description: 'Primeira linha\nSegunda linha',
    })));
  }
  await assertSucceeds(uploadBytes(ref(owner.storage(), `${path}/limite.jpg`), new Uint8Array(10 * 1024 * 1024), { contentType: 'image/jpeg' }));
});

test('URL com token permite download por quem tem o link, sem sessão', async () => {
  const storage = environment.authenticatedContext('ana').storage();
  const image = ref(storage, imagePath);
  await uploadBytes(image, photo, { contentType: 'image/jpeg' });
  const url = await getDownloadURL(image);
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Download com token falhou: ${response.status}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length !== photo.length) throw new Error('Conteúdo inesperado.');
  await assertFails(getBytes(ref(environment.unauthenticatedContext().storage(), imagePath)));
});
