import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/utils/result.dart';

import 'support/storage.dart';

void main() {
  late Directory root;
  late StorageService storage;
  late SessionRepositoryLocal sessions;
  late ChatRepository chats;

  // A failed save says why, not just that a cast failed.
  Future<Session> thread(String title, {String cwd = '/w/site', String? sideOf}) async =>
      switch (await sessions.create(cwd: cwd, title: title, sideOf: sideOf)) {
        Ok(:final value) => value,
        Error(:final error) => throw StateError('create failed: $error'),
      };

  setUp(() async {
    root = await Directory.systemTemp.createTemp('chats');
    storage = storageAt(root);
    sessions = SessionRepositoryLocal(storage);
    chats = ChatRepository(storage, sessions);
  });
  tearDown(() async {
    chats.dispose();
    // Saves still on their way land first: deleting under one failed on a CI
    // runner with "Directory not empty".
    await storage.flush();
    await root.delete(recursive: true);
  });

  test('sessions from before chats each get one, titled as they are', () async {
    final a = await thread('Budget for November');
    final b = await thread('Home page');
    await chats.load();
    final ca = sessions.byId(a.id)!.chatId!, cb = sessions.byId(b.id)!.chatId!;
    expect(ca, isNot(cb));
    expect(chats.byId(ca)!.title, 'Budget for November');
    expect(chats.threadsOf(cb).single.id, b.id);
  });

  test("a new thread gets a chat of its own; a side chat, its session's", () async {
    await chats.load();
    final a = await thread('Budget');
    final side = await thread('Why so high?', sideOf: a.id);
    final chat = sessions.byId(a.id)!.chatId!;
    expect(sessions.byId(side.id)!.chatId, chat);
    expect(chats.threadsOf(chat).map((s) => s.id), [
      a.id,
    ], reason: 'side chats are not threads of the list');
  });

  test('threads moved together make one chat; the one left empty goes', () async {
    await chats.load();
    final a = await thread('Budget for November');
    final b = await thread('Taxes', cwd: '/w/money');
    final side = await thread('A question', sideOf: b.id);
    final ca = sessions.byId(a.id)!.chatId!, cb = sessions.byId(b.id)!.chatId!;
    await chats.move(sessions.byId(b.id)!, ca);
    expect(chats.threadsOf(ca).map((s) => s.id).toSet(), {a.id, b.id});
    expect(sessions.byId(side.id)!.chatId, ca, reason: 'side chats move with their thread');
    expect(chats.byId(cb), isNull);
    expect(chats.placesOf(ca).toSet(), {'/w/site', '/w/money'});
    // Two threads: the chat keeps its title rather than following one.
    await sessions.save(sessions.byId(a.id)!.copyWith(title: 'Renamed thread'));
    expect(chats.byId(ca)!.title, 'Budget for November');

    // Out again, into a chat of its own.
    final own = await chats.move(sessions.byId(b.id)!, null);
    expect(chats.threadsOf(own).single.id, b.id);
  });

  test('a name and a brief the person wrote hold, and are kept on disk', () async {
    await chats.load();
    final a = await thread('Budget');
    final id = sessions.byId(a.id)!.chatId!;
    await chats.rename(id, 'Finances');
    await chats.setBrief(id, 'Decided: a budget per month. Open: the car.');
    await sessions.save(sessions.byId(a.id)!.copyWith(title: 'Budget for December'));
    expect(chats.byId(id)!.title, 'Finances', reason: 'named by the person');

    final again = ChatRepository(storage, sessions);
    addTearDown(again.dispose);
    await again.load();
    expect(again.byId(id)!.title, 'Finances');
    expect(again.byId(id)!.brief, startsWith('Decided'));
  });
}
