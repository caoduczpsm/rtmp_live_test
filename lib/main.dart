import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_audio_streaming/flutter_audio_streaming.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isStreaming = false;
  final FlutterFFmpeg _ffmpeg = FlutterFFmpeg();
  String selectedFilePath = "";
  String rtmpUrl =
      "rtmp://truyenthongdev-rtmp.vnptics.vn:30138/be372495-faa8-488b-8bde-4a76f49e8cd0";

  StreamingController controller = StreamingController();
  bool get isStreaming => controller.value.isStreaming ?? false;

  @override
  void initState() {
    super.initState();
    checkAndRequestPermission();
    initPlatformState();
    initialize();
  }

  @override
  void dispose() async {
    // TODO: implement dispose
    super.dispose();
    _ffmpeg.cancel();
    if (isStreaming) await controller.stop();
    controller.dispose();
  }

  void initialize() async {
    controller.addListener(() async {
      if (controller.value.hasError) {
        showInSnackBar('Camera error ${controller.value.errorDescription}');
        await stopStreaming();
      } else {
        try {
          if (controller.value.event == null) return;
          final Map<dynamic, dynamic> event =
              controller.value.event as Map<dynamic, dynamic>;
          log('Event: $event');
          final String eventType = event['eventType'] as String;
          switch (eventType) {
            case StreamingController.ERROR:
              break;
            case StreamingController.RTMP_STOPPED:
              break;
            case StreamingController.RTMP_RETRY:
              if (isStreaming) {
                await stopStreaming();
              }
              break;
          }
        } catch (e) {
          log('initialize: $e');
        }
      }
    });
    await controller.initialize();
    controller.prepare();
  }

  Future<String> startStreaming() async {
    if (!controller.value.isInitialized!) {
      showInSnackBar('Error: is not Initialized.');
      return '';
    }
    if (isStreaming) return '';
    // Open up a dialog for the ur
    try {
      await controller.start(rtmpUrl);
    } on AudioStreamingException catch (e) {
      _showException("startStreaming", e);
      return '';
    }
    return rtmpUrl;
  }

  Future<void> stopStreaming() async {
    if (!controller.value.isInitialized!) {
      return;
    }
    if (!isStreaming) {
      return;
    }
    try {
      setState(() {
        _isStreaming = false;
      });
      await controller.stop();
    } on AudioStreamingException catch (e) {
      _showException("stopStreaming", e);
      return;
    }
  }

  void _showException(String at, AudioStreamingException e) {
    log("AudioStreaming: Error at $at \n${e.code}\n${e.description}");
    showInSnackBar('$at Error: ${e.code}\n${e.description}');
  }

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 1),
      action: SnackBarAction(
        label: 'OK',
        onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
      ),
    ));
  }

  Future<void> initPlatformState() async {
    await Permission.camera.request();
    await Permission.microphone.request();
    await Permission.storage.request();

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth,
    ));
  }

  Future<void> connectRtmp() async {
    if (!_isStreaming) {
      await startStreaming();
    }
  }

  Future<void> disconnectRtmp() async {
    if (_isStreaming) {
      await stopStreaming();
    }
  }

  Future<void> checkAndRequestPermission() async {
    await Permission.audio.request();
    PermissionStatus status = await Permission.audio.status;

    if (!status.isGranted) {
      status = await Permission.audio.request();
    }

    if (status.isGranted) {
      _pickAndStream();
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  void _pickAndStream() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );

    if (result != null) {
      final selectedFile = File(result.files.single.path!);
      if (selectedFile.existsSync()) {
        setState(() {
          selectedFilePath = result.files.single.path!;
        });

        String command =
            "-re -i '${selectedFile.path}' -c:v libx264 -c:a aac -f flv $rtmpUrl";
        await _ffmpeg.execute(command);
      } else {
        log("File null");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Ứng dụng Flutter với haishin_kit')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                height: 50,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: <Widget>[
                  IconButton(
                    iconSize: 96.0,
                    icon: Icon(_isStreaming ? Icons.mic_off : Icons.mic),
                    onPressed: _isStreaming ? disconnectRtmp : connectRtmp,
                  ),
                ],
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _pickAndStream,
          backgroundColor: Colors.blueAccent,
          child: const Icon(
            Icons.file_copy_outlined,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
