import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:wanderlog/models/travel_entry.dart';
import 'package:wanderlog/services/photo_service.dart';
import 'package:wanderlog/services/travel_entry_service.dart';

Future<TravelPhoto> validPhoto() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xFF155E63), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return TravelPhoto(bytes: bytes, contentType: 'image/png', extension: 'png');
}

class UploadUser implements User {
  UploadUser(this.uid);
  @override
  final String uid;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UploadAuth implements FirebaseAuth {
  User? user = UploadUser('ana');
  final changes = StreamController<User?>.broadcast();
  @override
  User? get currentUser => user;
  @override
  Stream<User?> authStateChanges() async* {
    yield user;
    yield* changes.stream;
  }

  @override
  Future<void> signOut() async {
    user = null;
    changes.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryStorage implements FirebaseStorage {
  MemoryStorage(this.db);
  final FakeFirebaseFirestore db;
  final files = <String, Uint8List>{};
  final deleted = <String>[];
  final events = <String>[];
  bool autoComplete = true;
  Object? deleteError;
  Object? uploadResponseError;
  Object? downloadUrlError;
  Completer<void>? deleteGate;
  UploadFuture? task;
  int puts = 0;
  int references = 0;
  @override
  Reference ref([String? path]) {
    references++;
    return MemoryReference(this, path!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryReference implements Reference {
  MemoryReference(this.owner, this.fullPath);
  final MemoryStorage owner;
  @override
  final String fullPath;
  @override
  UploadTask putData(Uint8List data, [SettableMetadata? metadata]) {
    owner.puts++;
    owner.events.add('upload:$fullPath:${metadata?.contentType}');
    final task = UploadFuture(
      () {
        owner.files[fullPath] = data;
      },
      data.length,
      owner.uploadResponseError,
    );
    owner.task = task;
    if (owner.autoComplete) scheduleMicrotask(task.complete);
    return task;
  }

  @override
  Future<String> getDownloadURL() async {
    owner.events.add('url');
    if (owner.downloadUrlError != null) throw owner.downloadUrlError!;
    return 'https://example.com/foto.png';
  }

  @override
  Future<FullMetadata> getMetadata() async {
    if (!owner.files.containsKey(fullPath)) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'object-not-found',
      );
    }
    return MemoryMetadata();
  }

  @override
  Future<void> delete() async {
    owner.deleted.add(fullPath);
    if (owner.deleteGate != null) await owner.deleteGate!.future;
    if (owner.deleteError != null) throw owner.deleteError!;
    final documentPath = fullPath.split('/').take(4).join('/');
    if ((await owner.db.doc(documentPath).get()).exists) {
      throw FirebaseException(plugin: 'firebase_storage', code: 'unauthorized');
    }
    owner.files.remove(fullPath);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryMetadata implements FullMetadata {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UploadSnapshot implements TaskSnapshot {
  UploadSnapshot(this.bytesTransferred, this.totalBytes);
  @override
  final int bytesTransferred;
  @override
  final int totalBytes;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UploadFuture implements UploadTask {
  UploadFuture(this.onComplete, this.total, [this.responseError]);
  final void Function() onComplete;
  final int total;
  final Object? responseError;
  final done = Completer<TaskSnapshot>();
  final progress = StreamController<TaskSnapshot>.broadcast();
  void complete() {
    if (done.isCompleted) return;
    onComplete();
    final snapshot = UploadSnapshot(total, total);
    progress.add(snapshot);
    if (responseError != null) {
      done.completeError(responseError!);
    } else {
      done.complete(snapshot);
    }
  }

  void tick(int bytes) => progress.add(UploadSnapshot(bytes, total));
  @override
  Stream<TaskSnapshot> get snapshotEvents => progress.stream;
  @override
  Future<bool> cancel() async {
    if (done.isCompleted) return false;
    done.completeError(
      FirebaseException(plugin: 'firebase_storage', code: 'canceled'),
    );
    return true;
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(TaskSnapshot) onValue, {
    Function? onError,
  }) => done.future.then(onValue, onError: onError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UploadService extends TravelEntryService {
  UploadService(this.db, this.auth, this.memory, {super.localPhotos})
    : super(firestore: db, auth: auth, storage: memory);
  final FakeFirebaseFirestore db;
  final UploadAuth auth;
  final MemoryStorage memory;
  Object? writeError;
  Object? afterWriteError;
  Completer<void>? writeGate;
  Completer<void>? afterWriteGate;
  final documentWritten = Completer<void>();
  Completer<void> enteredWrite = Completer<void>();
  int writes = 0;
  int reservations = 0;
  @override
  String createEntryId() {
    reservations++;
    return super.createEntryId();
  }

  TravelEntry? written;
  @override
  Future<String> createEntry(TravelEntry entry) async {
    writes++;
    written = entry;
    memory.events.add('firestore');
    if (!enteredWrite.isCompleted) enteredWrite.complete();
    if (writeGate != null) await writeGate!.future;
    if (writeError != null) throw writeError!;
    final id = await super.createEntry(entry);
    if (!documentWritten.isCompleted) documentWritten.complete();
    if (afterWriteGate != null) await afterWriteGate!.future;
    if (afterWriteError != null) throw afterWriteError!;
    return id;
  }
}
