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

  test('a chat that held two conversations becomes two, each with its side chats', () async {
    // As a chat was before: one topic, two conversations in it.
    await storage.write('chats.json', [
      {
        'id': 'c1',
        'title': 'Dust Run game',
        'createdAt': '2026-11-01T10:00:00.000',
        'topic': 'Code',
        'icon': 'gamepad',
      },
    ]);
    final first = await thread('Plan the game');
    final second = await thread('Draw the bikes');
    final side = await thread('Which colors?', sideOf: second.id);
    await sessions.save(sessions.byId(first.id)!.copyWith(chatId: 'c1'));
    await sessions.save(sessions.byId(second.id)!.copyWith(chatId: 'c1'));
    await sessions.save(sessions.byId(side.id)!.copyWith(chatId: 'c1'));

    await chats.load();
    expect(sessions.byId(first.id)!.chatId, 'c1', reason: 'the first stays in its chat');
    final own = sessions.byId(second.id)!.chatId!;
    expect(own, isNot('c1'));
    expect(chats.threadsOf('c1').map((t) => t.id), [first.id]);
    expect(chats.threadsOf(own).map((t) => t.id), [second.id]);
    expect(sessions.byId(side.id)!.chatId, own, reason: 'its side chat goes with it');
    expect(chats.byId(own)!.title, 'Draw the bikes');
    expect(chats.byId(own)!.topic, 'Code');
    expect(chats.byId(own)!.icon, 'gamepad');
  });

  test('a name the person gave holds, and is kept on disk', () async {
    await chats.load();
    final a = await thread('Budget');
    final id = sessions.byId(a.id)!.chatId!;
    await chats.rename(id, 'Finances');
    await sessions.save(sessions.byId(a.id)!.copyWith(title: 'Budget for December'));
    expect(chats.byId(id)!.title, 'Finances', reason: 'named by the person');

    final again = ChatRepository(storage, sessions);
    addTearDown(again.dispose);
    await again.load();
    expect(again.byId(id)!.title, 'Finances');
  });
}
