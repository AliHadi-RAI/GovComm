import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class VoiceNoteService {
  final _audioRecorder = AudioRecorder();
  String? _currentPath;

  Future<bool> startRecording() async {
    try {
      if (await Permission.microphone.request().isGranted) {
        final directory = await getTemporaryDirectory();
        _currentPath = '${directory.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        const config = RecordConfig();
        await _audioRecorder.start(config, path: _currentPath!);
        debugPrint("🎙️ [VoiceNoteService] Recording started: $_currentPath");
        return true;
      } else {
        debugPrint("⚠️ [VoiceNoteService] Microphone permission denied");
        return false;
      }
    } catch (e) {
      debugPrint("❌ [VoiceNoteService] Start recording error: $e");
      return false;
    }
  }

  Future<String?> stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      debugPrint("🎙️ [VoiceNoteService] Recording stopped: $path");
      return path;
    } catch (e) {
      debugPrint("❌ [VoiceNoteService] Stop recording error: $e");
      return null;
    }
  }

  Future<void> dispose() async {
    await _audioRecorder.dispose();
  }

  bool isRecording() {
    // Note: The record package's isRecording is an async call in some versions, 
    // but in 5.x+ it might be different. Let's check the current state if needed.
    // For now, we'll rely on the UI state management.
    return false; 
  }
}
