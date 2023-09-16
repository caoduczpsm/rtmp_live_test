import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:haishin_kit/audio_source.dart';
import 'package:haishin_kit/rtmp_connection.dart';
import 'package:haishin_kit/rtmp_stream.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
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
  RtmpConnection? _connection;
  RtmpStream? _stream;
  bool _recording = false;
  final FlutterFFmpeg _ffmpeg = FlutterFFmpeg();
  String selectedFilePath = "";
  String rtmpUrl = "rtmp://truyenthongdev-rtmp.vnptics.vn:30138/be372495-faa8-488b-8bde-4a76f49e8cd0";
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  String? _recordedFilePath;

  StreamingController controller = StreamingController();
  bool get isStreaming => controller.value.isStreaming ?? false;

  @override
  void initState() {
    super.initState();
    checkAndRequestPermission();
    initPlatformState();
    initRecorder();
    initPlayer();
    initialize();
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
          print('Event: $event');
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
          print('initialize: $e');
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
      await controller.stop();
      setState(() {});
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

  Future<void> initRecorder() async {
    _recorder = FlutterSoundRecorder();
    await _recorder!.openRecorder();
    await _recorder!.setSubscriptionDuration(const Duration(milliseconds: 10));
  }

  Future<void> initPlayer() async {
    _player = FlutterSoundPlayer();
    await _player!.openPlayer();
    await _player!.setSubscriptionDuration(const Duration(milliseconds: 10));
  }

  Future<void> startRecording() async {
    String tempDir = (await getTemporaryDirectory()).path;
    String path = '$tempDir/flutter_sound_example.aac';
    await _recorder!.startRecorder(
      toFile: path,
      codec: Codec.aacADTS,
    );
    setState(() {
      _recordedFilePath = path;
    });
  }

  Future<void> stopRecording() async {
    await _recorder!.stopRecorder();
  }

  Future<void> startPlaying() async {
    if (_recordedFilePath != null) {
      await _player!.startPlayer(
        fromURI: _recordedFilePath!,
        codec: Codec.aacADTS,
      );
    }
  }

  Future<void> stopPlaying() async {
    await _player!.stopPlayer();
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
    if (!_recording) {
      stopPlaying();
      startRecording();
      RtmpConnection connection = await RtmpConnection.create();

      connection.eventChannel.receiveBroadcastStream().listen((event) {
        switch (event["data"]["code"]) {
          case 'NetConnection.Connect.Success':
            _stream?.publish("live");
            setState(() {
              _recording = true;
            });
            break;
        }
      });

      RtmpStream stream = await RtmpStream.create(connection);
      stream.attachAudio(AudioSource());
      stream.setHasVideo(false);

      if (!mounted) return;
      setState(() {
        _connection = connection;
        _stream = stream;
      });

      if (!_recording) {
        _connection?.connect(rtmpUrl);
        setState(() {
          _recording = true;
        });
      }
    }
  }

  Future<void> disconnectRtmp() async {
    stopRecording();
    startPlaying();
    if (_recording) {
      _connection?.close();
      _stream?.attachAudio(null);
      _stream?.dispose();
      _connection?.dispose();
      setState(() {
        _recording = false;
        _stream = null;
      });
    }
  }

  @override
  void dispose() async {
    // TODO: implement dispose
    super.dispose();
    _ffmpeg.cancel();
    _connection?.dispose();
    _stream?.dispose();
    _recorder!.closeRecorder();
    _player!.closePlayer();
    if (isStreaming) await controller.stop();
    controller.dispose();
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

        await _player!.startPlayer(
          fromURI: selectedFilePath,
          codec: Codec.aacADTS,
        );

        await startStreaming();

        // String command = "-re -i '${selectedFile.path}' -c:a aac -b:a 128k -f wav $rtmpUrl";
        //
        // await _ffmpeg.execute(command);
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
              _stream == null
                  ? const Text("")
                  : const Text(
                      "Đang phát trực tiếp",
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
              const SizedBox(
                height: 50,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: <Widget>[
                  IconButton(
                    iconSize: 96.0,
                    icon: Icon(_recording ? Icons.mic_off : Icons.mic),
                    onPressed: _recording ? disconnectRtmp : connectRtmp,
                  ),
                ],
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _pickAndStream,
          backgroundColor: Colors.blueAccent,
          child: const Icon(Icons.file_copy_outlined, color: Colors.white,),
        ),
      ),
    );
  }
}
