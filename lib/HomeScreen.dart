import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:RedTree/globals.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:record/record.dart';
import 'globals.dart';
import 'package:path/path.dart' as path;
import 'package:audioplayers/audioplayers.dart';
import 'main.dart' as main_screen;
import 'FileManager.dart' as file_manager;
import 'Parameters.dart';
import 'file_utils.dart';
import 'MemoOptionsModal.dart';
import 'LoginScreen.dart';
import 'BlinkingMicWidget.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:get/get.dart';

class HomeScreen extends StatefulWidget {
  final CameraDescription camera;

  const HomeScreen({Key? key, required this.camera}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Memo functionality variables
  final SpeechToText _speechToText = SpeechToText();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _loadRedTreeStates();
    _loadLoginStatus();
    _ensureRedTreeFolder();
    _configureAudioPlayerContext();
    
    // Preload images to avoid display issues
    _preloadImages();
  }
  Future<void> _configureAudioPlayerContext() async {
    try {
      await _audioPlayer.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playAndRecord,
          options: {
            AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.allowBluetooth,
            AVAudioSessionOptions.allowBluetoothA2DP,
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
        android: AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ));
      await _audioPlayer.setVolume(1.0);
    } catch (e) {
      debugPrint('Failed to set audio context: $e');
    }
  }

  @override
  void dispose() {
    _speechToText.stop();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
  
  void _preloadImages() {
    // Preload images to ensure they're in cache
    Future.microtask(() {
      if (mounted) {
        precacheImage(AssetImage('assets/app_icon_home.png'), context);
        precacheImage(AssetImage('assets/img_redtree.jpeg'), context);
      }
    });
  }
  
  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-preload images when widget updates (e.g., when navigating back)
    _preloadImages();
  }

  Future<void> _loadRedTreeStates() async {
    final prefs = await SharedPreferences.getInstance();
    double savedDelay = prefs.getDouble('rtBoxDelay') ?? 1.5;
    final savedPath = prefs.getString('folderPath') ?? "/storage/emulated/0/Download";
    bool isRedTreeActivated = prefs.getBool('redtree') ?? false;
    String savedPrefix = prefs.getString('fileNamingPrefix') ?? fileNamingPrefixNotifier.value;

    setState(() {
      isRedTreeActivatedNotifier.value = isRedTreeActivated;
      rtBoxDelayNotifier.value = savedDelay;
      fileNamingPrefixNotifier.value = savedPrefix;
      
      // Only update folderPathNotifier if the value has actually changed
      if (folderPathNotifier.value != savedPath) {
        folderPathNotifier.value = savedPath;
        print("HomeScreen: Updated folderPathNotifier to: $savedPath");
      }
    });
  }

  Future<void> _loadLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    isLoggedInNotifier.value = isLoggedIn;
  }

  Future<void> _ensureRedTreeFolder() async {
    // await FileUtils.ensureRedTreeFolderExists();
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userEmail');
    await prefs.remove('userPassword');
    await prefs.remove('isLoggedIn');
    isLoggedInNotifier.value = false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('logoutSuccessful'.tr),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _openCamera(BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => main_screen.MainScreen(
          camera: widget.camera,
          dateFormatNotifier: dateFormatNotifier,
          timeFormatNotifier: timeFormatNotifier,
        ),
      ),
    );
  }

  void _showMemoOptions(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => MemoOptionsModal(),
    );
    
    if (result != null) {
      if (result == 'voice') {
        _showVoiceMemoDialog(context);
      } else {
        _showTextMemoBottomSheet(context);
      }
    }
  }

  void _showVoiceMemoDialog(BuildContext context) async {
    String? recordingPath;
    bool isRecording = false;
    bool isPaused = false;
    bool isPlaying = false;
    Duration playbackTotal = Duration.zero;
    Duration playbackPos = Duration.zero;
    String? _previewPath;
    String recognizedText = '';
    Duration recordingDuration = Duration.zero;
    Timer? speechTimeoutTimer;
    Timer? durationTimer;
    // removed Vosk feed timer
    List<String> allRecognizedText = []; // Store all recognized text segments
    
    // Debug information for UI display
    String debugInfo = '';
    String speechStatus = '';
    bool speechAvailable = false;
    bool speechPermission = false;
    
    // Continuous speech-to-text variables
    bool _shouldKeepListening = false; // Flag to control continuous listening
    bool _autoStarted = false; // Auto-start guard

    // Helper function to start continuous listening
    Future<void> startContinuousListening(Function setState) async {
      if (!_shouldKeepListening) return;
      
      try {
        final available = await _speechToText.initialize(
          onStatus: (status) {
            debugPrint('Speech status: $status');
            setState(() {
              speechStatus = 'Status: $status';
            });
            // Auto-stop recording after STT stops due to silence (~pauseFor)
            if ((status == 'done' || status == 'notListening')) {
              if (isRecording) {
                try {
                  _audioRecorder.stop().then((stoppedPath) {
                    if (stoppedPath != null) {
                      recordingPath = stoppedPath;
                    }
                    durationTimer?.cancel();
                    speechTimeoutTimer?.cancel();
                    if (mounted) {
                      setState(() {
                        isRecording = false;
                        isPaused = false;
                        debugInfo = 'Recording auto-stopped after silence';
                      });
                    }
                  });
                } catch (_) {}
                _shouldKeepListening = false;
                return;
              }
              if (_shouldKeepListening) {
                Future.delayed(Duration(milliseconds: 800), () {
                  if (_shouldKeepListening) {
                    startContinuousListening(setState);
                  }
                });
              }
            }
          },
          onError: (error) {
            debugPrint('Speech error: $error');
            setState(() {
              debugInfo = 'Speech error: $error';
            });
            // Restart on error if we should keep listening
            if (_shouldKeepListening) {
              debugPrint('Speech error occurred, restarting...');
              setState(() {
                debugInfo = 'Speech error occurred, restarting...';
              });
              Future.delayed(Duration(milliseconds: 1000), () {
                if (_shouldKeepListening) {
                  startContinuousListening(setState);
                }
              });
            }
          },
        );
        
        setState(() {
          speechAvailable = available;
        });
        
        if (available && _shouldKeepListening) {
          final hasPermission = await _speechToText.hasPermission;
          setState(() {
            speechPermission = hasPermission;
          });
          
          if (hasPermission) {
            setState(() {
              speechStatus = 'Listening...';
              debugInfo = 'Speech-to-text active and listening continuously';
            });
            
            await _speechToText.listen(
              onResult: (result) {
                setState(() {
                  // Show full recognized text instead of limiting to 7 words
                  recognizedText = result.recognizedWords;
                  speechStatus = 'Recognized: "${result.recognizedWords}"';
                  debugInfo = 'Speech result: "${result.recognizedWords}" (final: ${result.finalResult})';
                  
                  // Add to accumulated text if it's a complete sentence
                  if (result.finalResult && result.recognizedWords.isNotEmpty) {
                    allRecognizedText.add(result.recognizedWords);
                  }
                });
              },
               listenFor: Duration(minutes: 10), // Listen for up to 10 minutes
               pauseFor: Duration(seconds: 7), // Auto-stop after ~7s of silence
              partialResults: true,
              localeId: 'en_US',
              onSoundLevelChange: (level) {
                setState(() {
                  debugInfo = 'Sound level: $level (${DateTime.now().millisecondsSinceEpoch})';
                });
              },
            );
          } else {
            setState(() {
              speechStatus = 'Permission denied';
              debugInfo = 'Speech-to-text permission denied. Please grant microphone permission.';
            });
          }
        } else {
          setState(() {
            speechStatus = 'Not available';
            debugInfo = 'Speech-to-text not available on this device';
          });
        }
      } catch (e) {
        debugPrint('Error starting speech recognition: $e');
        setState(() {
          debugInfo = 'Error starting speech recognition: $e';
        });
        // Retry after delay if we should keep listening
        if (_shouldKeepListening) {
          Future.delayed(Duration(milliseconds: 2000), () {
            if (_shouldKeepListening) {
              startContinuousListening(setState);
            }
          });
        }
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Auto-start recording on first build
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!_autoStarted) {
                _autoStarted = true;
                try {
                  if (await _audioRecorder.hasPermission()) {
                    final directory = await getApplicationDocumentsDirectory();
                    final fileName = 'memo_${DateTime.now().millisecondsSinceEpoch}.wav';
                    recordingPath = path.join(directory.path, fileName);
                    await _audioRecorder.start(
                      const RecordConfig(
                        encoder: AudioEncoder.wav,
                        sampleRate: 16000,
                        numChannels: 1,
                      ),
                      path: recordingPath!,
                    );
                    setState(() {
                      isRecording = true;
                      isPaused = false;
                    });
                    durationTimer?.cancel();
                    durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
                      setState(() {
                        recordingDuration = Duration(seconds: recordingDuration.inSeconds + 1);
                      });
                    });

                    // Start silence detection via speech-to-text if available
                    _shouldKeepListening = true;
                    try {
                      await startContinuousListening(setState);
                    } catch (_) {}
                  }
                } catch (e) {
                  debugPrint('Auto-start recording error: $e');
                }
              }
            });

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              content: Container(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Recording status
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            isRecording ? Icons.mic : Icons.mic_none,
                            size: 60,
                            color: isRecording ? Colors.red : Colors.grey.shade600,
                          ),
                          SizedBox(height: 10),
                          Text(
                            !isRecording 
                                ? 'Tap mic to start recording' 
                                : (isPaused 
                                    ? 'Recording paused - tap to resume' 
                                    : 'Listening...'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: (isRecording && !isPaused) ? Colors.green : Colors.grey.shade700,
                            ),
                          ),
                          if (isRecording) ...[
                            SizedBox(height: 10),
                            Text(
                              _formatDuration(recordingDuration),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    
                    // Speech-to-text display (temporary live text only)
                    if (recognizedText.isNotEmpty) ...[
                      SizedBox(height: 15),
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.record_voice_over,
                              color: Colors.blue.shade600,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                recognizedText,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.blue.shade800,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    // Debug info for speech-to-text (removed visual block)
                    if (false) ...[
                      SizedBox(height: 10),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.bug_report,
                                  size: 16,
                                  color: Colors.grey.shade600,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Debug Info',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                            if (speechStatus.isNotEmpty) ...[
                              Text(
                                'Status: $speechStatus',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 2),
                            ],
                            if (debugInfo.isNotEmpty) ...[
                              Text(
                                debugInfo,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: speechAvailable ? Colors.green : Colors.red,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Available: $speechAvailable',
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                ),
                                SizedBox(width: 12),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: speechPermission ? Colors.green : Colors.red,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Permission: $speechPermission',
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    // Playback section (when recording is paused or stopped and we have a recording)
                    if ((isPaused || !isRecording) && recordingPath != null) ...[
                      SizedBox(height: 15),
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.audiotrack,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  isPaused ? 'Recording Paused' : 'Recording Complete',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            if (playbackTotal > Duration.zero)
                              Text(
                                '${_formatDuration(playbackPos)} / ${_formatDuration(playbackTotal)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade600,
                                ),
                              ),
                            SizedBox(height: 8),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () async {
                                if (!isPlaying) {
                                  try {
                                    setState(() { isPlaying = true; });
                                    // removed debug info
                                    
                                    // Enhanced audio playback with comprehensive error handling
                                    await _audioPlayer.stop();
                                    
                                    // Validate file first
                                    final sourceFile = File(recordingPath!);
                                    if (!await sourceFile.exists()) { return; }
                                    final sourceSize = await sourceFile.length();
                                    if (sourceSize == 0) { return; }
                                    
                                    // removed debug info
                                    
                                    bool playbackStarted = false;
                                    String errorLog = '';
                                    String effectivePath = recordingPath!;
                                    
                                    // If paused, prefer previewing using BytesSource or a temp copy
                                    if (isPaused) {
                                      try {
                                        final raw = await sourceFile.readAsBytes();
                                        final bytes = _ensurePlayableWav(
                                          raw,
                                          sampleRate: 16000,
                                          numChannels: 1,
                                          bitsPerSample: 16,
                                        );
                                        if (bytes.isNotEmpty) {
                                          await _audioPlayer.setReleaseMode(ReleaseMode.stop);
                                          await _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);
                                          await _audioPlayer.setVolume(1.0);
                                          await _audioPlayer.play(BytesSource(bytes));
                                          setState(() { isPlaying = true; });
                                          playbackStarted = true;
                                        }
                                      } catch (e) {
                                        errorLog += 'Paused BytesSource: $e; ';
                                      }
                                    }
                                    
                                    // Prefer MediaPlayer for file playback on Android/iOS
                                    if (!playbackStarted) {
                                      try {
                                        await _audioPlayer.setReleaseMode(ReleaseMode.stop);
                                        await _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);
                                        await _audioPlayer.setVolume(1.0);
                                        await _audioPlayer.play(DeviceFileSource(effectivePath));
                                        setState(() { isPlaying = true; });
                                        playbackStarted = true;
                                      } catch (e) {
                                        errorLog += 'DeviceFileSource (MediaPlayer): $e; ';
                                      }
                                    }
                                    
                                    // Strategy 3: UrlSource
                                    if (!playbackStarted) {
                                      try {
                                        await _audioPlayer.play(UrlSource('file://$effectivePath'));
                                        setState(() { isPlaying = true; });
                                        playbackStarted = true;
                                      } catch (e) {
                                        errorLog += 'UrlSource: $e; ';
                                      }
                                    }
                                    
                                    // Strategy 4: BytesSource
                                    if (!playbackStarted) {
                                      try {
                                        final bytes = await sourceFile.readAsBytes();
                                        await _audioPlayer.play(BytesSource(bytes));
                                        setState(() { isPlaying = true; });
                                        playbackStarted = true;
                                      } catch (e) {
                                        errorLog += 'BytesSource: $e; ';
                                      }
                                    }
                                    
                                    if (!playbackStarted) {
                                      setState(() { isPlaying = false; debugInfo = 'Playback failed'; });
                                      return;
                                    }
                                    
                                    // Get duration after a short delay to allow file to load
                                    Future.delayed(Duration(milliseconds: 500), () async {
                                      try {
                                        final duration = await _audioPlayer.getDuration();
                                        if (duration != null) { /* no-op */ }
                                      } catch (e) {
                                        // ignore
                                      }
                                    });
                                    
                                    // Listen for completion
                                    _audioPlayer.onPlayerComplete.listen((_) { setState(() { isPlaying = false; }); });
                                    
                                    // Listen for state changes
                                    _audioPlayer.onPlayerStateChanged.listen((state) {
                                      setState(() { isPlaying = state == PlayerState.playing; });
                                      
                                      // Try to get duration when player is ready
                                      if (state == PlayerState.playing) {
                                        Future.delayed(Duration(milliseconds: 100), () async {
                                          try {
                                            final duration = await _audioPlayer.getDuration();
                                            if (duration != null && duration != Duration.zero) {
                                              setState(() {
                                                debugInfo = 'Audio duration: ${_formatDuration(duration)}';
                                              });
                                            }
                                          } catch (e) {
                                            // Ignore duration errors
                                          }
                                        });
                                      }
                                    });
                                    
                                  } catch (e) {
                                    setState(() {
                                      debugInfo = 'Error playing audio: $e';
                                    });
                                  }
                                } else {
                                  try {
                                    await _audioPlayer.stop();
                                    setState(() {
                                      isPlaying = false;
                                      debugInfo = 'Audio playback stopped';
                                    });
                                  } catch (e) {
                                    setState(() {
                                      debugInfo = 'Error stopping audio: $e';
                                    });
                                  }
                                }
                              },
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isPlaying ? Colors.red : Colors.blue,
                                ),
                                child: Icon(
                                  isPlaying ? Icons.stop : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Mic button
                    GestureDetector(
                      onTap: () async {
                        if (!isRecording) {
                          // Start recording
                          try {
                            if (await _audioRecorder.hasPermission()) {
                              final directory = await getApplicationDocumentsDirectory();
                              // Use WAV 16k mono for live Vosk feeding
                              final fileName = 'memo_${DateTime.now().millisecondsSinceEpoch}.wav';
                              recordingPath = path.join(directory.path, fileName);
                              
                              await _audioRecorder.start(
                                const RecordConfig(
                                  encoder: AudioEncoder.wav,
                                  sampleRate: 16000,
                                  numChannels: 1,
                                ),
                                path: recordingPath!,
                              );
                              
                              setState(() {
                                isRecording = true;
                                isPaused = false;
                              });
                              // Start duration timer
                              durationTimer = Timer.periodic(Duration(seconds: 1), (timer) {
                                setState(() {
                                  recordingDuration = Duration(seconds: recordingDuration.inSeconds + 1);
                                });
                              });
                              // Start Vosk model and begin tailing the WAV for live transcription
                              // Removed Vosk live transcription; recording only
                            }
                          } catch (e) {
                            print('Error starting recording: $e');
                          }
                        } else if (isRecording && !isPaused) {
                               // Pause recording
                               try {
                                 await _audioRecorder.pause();
                                 durationTimer?.cancel();
                                 speechTimeoutTimer?.cancel();

                                 setState(() {
                                   isPaused = true;
                                   debugInfo = 'Recording paused';
                                 });
                               } catch (e) {
                                 print('Error pausing recording: $e');
                               }
                        } else if (isPaused) {
                          // Resume recording
                          try {
                            await _audioRecorder.resume();
                            
                            setState(() {
                              isPaused = false;
                            });
                            
                            // Resume duration timer
                            durationTimer = Timer.periodic(Duration(seconds: 1), (timer) {
                              setState(() {
                                recordingDuration = Duration(seconds: recordingDuration.inSeconds + 1);
                              });
                            });
                            // Keep speech-to-text disabled during recording
                          } catch (e) {
                            print('Error resuming recording: $e');
                          }
                        } else {
                               // Stop recording completely
                               try {
                                 await _audioRecorder.stop();
                                 durationTimer?.cancel();
                                 speechTimeoutTimer?.cancel();

                                 setState(() {
                                   isRecording = false;
                                   isPaused = false;
                                   debugInfo = 'Recording stopped';
                                 });
                               } catch (e) {
                                 print('Error stopping recording: $e');
                               }
                        }
                      },
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isRecording 
                              ? (isPaused ? Colors.orange : Colors.red) 
                              : Colors.grey.shade600,
                        ),
                        child: Icon(
                          !isRecording 
                              ? Icons.mic 
                              : isPaused 
                                  ? Icons.play_arrow 
                                  : Icons.pause,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    
                         // Cancel button
                         TextButton(
                           onPressed: () async {
                             try {
                               if (isRecording || isPaused) {
                                 final stoppedPath = await _audioRecorder.stop();
                                 if (stoppedPath != null) {
                                   recordingPath = stoppedPath;
                                 }
                               }
                               if (isPlaying) {
                                 await _audioPlayer.stop();
                               }
                             } catch (_) {}
                             _shouldKeepListening = false;
                             await _speechToText.stop();
                             durationTimer?.cancel();
                             speechTimeoutTimer?.cancel();
                             Navigator.pop(context);
                           },
                           child: Text('Cancel'),
                         ),
                    
                     // OK button
                     ElevatedButton(
                       onPressed: recordingPath != null ? () async {
                         try {
                           // Ensure recording is finalized before saving/closing
                           if (isRecording || isPaused) {
                             final stoppedPath = await _audioRecorder.stop();
                             if (stoppedPath != null) {
                               recordingPath = stoppedPath;
                             }
                             isRecording = false;
                             isPaused = false;
                           }
                           if (isPlaying) {
                             await _audioPlayer.stop();
                           }
                         } catch (_) {}

                         _shouldKeepListening = false;
                         await _speechToText.stop();
                         durationTimer?.cancel();
                         speechTimeoutTimer?.cancel();

                         // Validate non-empty recording
                         try {
                           if (recordingPath != null) {
                             final f = File(recordingPath!);
                             final len = await f.length();
                             if (len == 0) {
                               ScaffoldMessenger.of(context).showSnackBar(
                                 SnackBar(content: Text('Recording failed (0 bytes). Please try again.')),
                               );
                               return;
                             }
                           }
                         } catch (_) {}

                         Navigator.pop(context);
                         _showMemoSettingsPopup(recordingPath!, 'm4a');
                       } : null,
                       child: Text('OK'),
                     ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showTextMemoBottomSheet(BuildContext context) async {
    final TextEditingController textController = TextEditingController();
    bool isListening = false;
    bool _shouldKeepListening = false;
    bool _sttInitialized = false;

    Future<void> _startListen(Function setState) async {
      if (!_shouldKeepListening) return;
      await _speechToText.listen(
        onResult: (result) {
          setState(() {
            if (result.finalResult) {
              if (textController.text.isNotEmpty && !textController.text.endsWith(' ')) {
                textController.text += ' ';
              }
              if (result.recognizedWords.isNotEmpty) {
                textController.text += result.recognizedWords;
              }
            } else {
              final currentText = textController.text;
              if (result.recognizedWords.isNotEmpty) {
                if (currentText.isEmpty) {
                  textController.text = result.recognizedWords;
                } else {
                  final words = currentText.split(' ');
                  words[words.length - 1] = result.recognizedWords;
                  textController.text = words.join(' ');
                }
              }
            }
          });
        },
        listenFor: const Duration(minutes: 10),
        pauseFor: const Duration(seconds: 30),
        partialResults: true,
        localeId: 'en_US',
        listenMode: ListenMode.dictation,
      );
    }

    Future<void> _ensureInit(Function setState) async {
      if (_sttInitialized) return;
      final available = await _speechToText.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && _shouldKeepListening) {
            // Immediately re-listen without re-initialize to avoid flicker
            Future.microtask(() => _startListen(setState));
          }
        },
        onError: (error) {
          if (_shouldKeepListening) {
            Future.delayed(const Duration(milliseconds: 500), () => _startListen(setState));
          }
        },
      );
      _sttInitialized = available;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (context, setState) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.keyboard),
                              tooltip: 'keyboardInput',
                              onPressed: () {},
                            ),
                            BlinkingMicWidget(
                              isListening: isListening,
                              tooltip: 'voiceInput',
                              onPressed: () async {
                                if (!isListening) {
                                  setState(() {
                                    isListening = true;
                                    _shouldKeepListening = true;
                                  });
                                  await _ensureInit(setState);
                                  await _startListen(setState);
                                } else {
                                  _shouldKeepListening = false;
                                  await _speechToText.stop();
                                  setState(() => isListening = false);
                                }
                              },
                            ),
                            if (isListening)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  'listening',
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            _shouldKeepListening = false;
                            await _speechToText.stop();
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                    TextField(
                      controller: textController,
                      maxLines: 5,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Type your note here...',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            _shouldKeepListening = false;
                            await _speechToText.stop();
                            final note = textController.text.trim();
                            if (note.isNotEmpty) {
                              // Save text memo to file first
                              try {
                                final directory = await getApplicationDocumentsDirectory();
                                final fileName = 'memo_${DateTime.now().millisecondsSinceEpoch}.txt';
                                final file = File('${directory.path}/$fileName');
                                await file.writeAsString(note);
                                Navigator.pop(context);
                                _showMemoSettingsPopup(file.path, 'txt');
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error saving memo: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          child: Text('OK'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }


  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  // Ensures a partial WAV is playable by fixing or adding a header
  Uint8List _ensurePlayableWav(
    Uint8List inputBytes, {
    int sampleRate = 16000,
    int numChannels = 1,
    int bitsPerSample = 16,
  }) {
    if (inputBytes.length < 44) {
      return inputBytes;
    }

    bool hasRiff = inputBytes[0] == 0x52 && inputBytes[1] == 0x49 && inputBytes[2] == 0x46 && inputBytes[3] == 0x46; // RIFF
    bool hasWave = inputBytes[8] == 0x57 && inputBytes[9] == 0x41 && inputBytes[10] == 0x56 && inputBytes[11] == 0x45; // WAVE

    Uint8List writeable = Uint8List.fromList(inputBytes);

    int totalSize = writeable.length;
    int dataStartIndex = -1;
    // Find 'data' chunk robustly
    for (int i = 12; i <= totalSize - 8; i++) {
      if (writeable[i] == 0x64 && writeable[i + 1] == 0x61 && writeable[i + 2] == 0x74 && writeable[i + 3] == 0x61) {
        dataStartIndex = i + 4; // size field position
        break;
      }
    }

    void writeUint32LE(int offset, int value) {
      writeable[offset] = value & 0xFF;
      writeable[offset + 1] = (value >> 8) & 0xFF;
      writeable[offset + 2] = (value >> 16) & 0xFF;
      writeable[offset + 3] = (value >> 24) & 0xFF;
    }

    if (hasRiff && hasWave && dataStartIndex >= 0) {
      int dataSize = totalSize - (dataStartIndex + 4);
      writeUint32LE(4, totalSize - 8); // RIFF chunk size
      writeUint32LE(dataStartIndex, dataSize);
      return writeable;
    }

    // If no valid header, construct a new 44-byte WAV header for PCM and prepend
    int bytesPerSample = bitsPerSample ~/ 8;
    int byteRate = sampleRate * numChannels * bytesPerSample;
    int subchunk2Size = totalSize;
    int chunkSize = 36 + subchunk2Size;

    final header = BytesBuilder();
    // RIFF
    header.add([0x52, 0x49, 0x46, 0x46]);
    header.add([
      chunkSize & 0xFF,
      (chunkSize >> 8) & 0xFF,
      (chunkSize >> 16) & 0xFF,
      (chunkSize >> 24) & 0xFF,
    ]);
    // WAVE
    header.add([0x57, 0x41, 0x56, 0x45]);
    // fmt 
    header.add([0x66, 0x6D, 0x74, 0x20]);
    header.add([0x10, 0x00, 0x00, 0x00]); // Subchunk1Size 16
    header.add([0x01, 0x00]); // PCM
    header.add([numChannels & 0xFF, (numChannels >> 8) & 0xFF]);
    header.add([
      sampleRate & 0xFF,
      (sampleRate >> 8) & 0xFF,
      (sampleRate >> 16) & 0xFF,
      (sampleRate >> 24) & 0xFF,
    ]);
    header.add([
      byteRate & 0xFF,
      (byteRate >> 8) & 0xFF,
      (byteRate >> 16) & 0xFF,
      (byteRate >> 24) & 0xFF,
    ]);
    int blockAlign = numChannels * bytesPerSample;
    header.add([blockAlign & 0xFF, (blockAlign >> 8) & 0xFF]);
    header.add([bitsPerSample & 0xFF, (bitsPerSample >> 8) & 0xFF]);
    // data
    header.add([0x64, 0x61, 0x74, 0x61]);
    header.add([
      subchunk2Size & 0xFF,
      (subchunk2Size >> 8) & 0xFF,
      (subchunk2Size >> 16) & 0xFF,
      (subchunk2Size >> 24) & 0xFF,
    ]);

    final bb = BytesBuilder();
    bb.add(header.toBytes());
    bb.add(writeable);
    return bb.toBytes();
  }

  void _showMemoSettingsPopup(String filePath, String extension) async {
    final now = DateTime.now();
    String prefix = _generateFileNamePrefix(now);
    String fileName = prefix;
    String selectedFolderPath = folderPathNotifier.value;
    final TextEditingController fileNameController = TextEditingController(text: fileName);
    ValueNotifier<bool> isOkEnabled = ValueNotifier(false);
    final ValueNotifier<String?> _temporarySelectedFolderPath = ValueNotifier(null);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        // Select all text when dialog opens
        WidgetsBinding.instance.addPostFrameCallback((_) {
          fileNameController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: fileNameController.text.length,
          );
        });
        
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              titlePadding: EdgeInsetsGeometry.zero,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: fileNameController,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: 'Enter file name',
                              border: InputBorder.none,
                              suffixIcon: BlinkingMicSuffixIcon(
                                isListening: false, // This is for file naming, not continuous listening
                                onPressed: () async {
                                  bool available = await _speechToText.initialize(
                                    onStatus: (status) => print('Speech status: $status'),
                                    onError: (error) => print('Speech error: $error'),
                                  );

                                  if (available) {
                                    _speechToText.listen(
                                      onResult: (result) {
                                        final spokenName = result.recognizedWords.replaceAll(' ', '_');
                                        fileNameController.text = spokenName;
                                        fileName = spokenName;
                                        isOkEnabled.value = (fileName.trim().isNotEmpty || fileName != prefix) ||
                                            (selectedFolderPath != folderPathNotifier.value);
                                      },
                                    );
                                  }
                                },
                              ),
                            ),
                            onChanged: (value) {
                              fileName = value;
                              isOkEnabled.value = (fileName.trim().isNotEmpty ||
                                      fileName != prefix) ||
                                  (selectedFolderPath != folderPathNotifier.value);
                            },
                          ),
                        ),
                        ValueListenableBuilder<String?>(
                          valueListenable: _temporarySelectedFolderPath,
                          builder: (context, tempPath, _) {
                            final displayPath = tempPath ?? folderPathNotifier.value;
                            return Container(
                              width: double.infinity,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                displayPath, 
                                style: TextStyle(color: Colors.black),
                                textAlign: TextAlign.start,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Divider(thickness: 1, height: 1),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            titlePadding: EdgeInsetsGeometry.zero,
                            title: Stack(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text("Confirm Delete", style: Theme.of(context).textTheme.titleLarge),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: IconButton(
                                    icon: Icon(Icons.close),
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                ),
                              ],
                            ),
                            backgroundColor: Colors.white,
                            actions: [
                              TextButton(
                                onPressed: () async {
                                  File(filePath).deleteSync();
                                  Navigator.pop(context);
                                  Navigator.pop(context);
                                },
                                child: Text("Confirm", style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        },
                      ),
                      _buildVerticalDivider(),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.black),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                      ),
                      _buildVerticalDivider(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () async {
                              final saveFolder = selectedFolderPath.isNotEmpty
                                  ? selectedFolderPath
                                  : folderPathNotifier.value;
                              final saveName = fileName.isNotEmpty
                                  ? fileName
                                  : path.basenameWithoutExtension(filePath);
                              
                              String savePath = "$saveFolder/$saveName.$extension";

                              try {
                                File(filePath).copySync(savePath);
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Memo saved successfully!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error saving memo: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                            child: Text("OK"),
                          ),
                          SizedBox(width: 8),
                          IconButton(
                            icon: Icon(Icons.folder, color: Colors.blue),
                            onPressed: () async {
                              final selectedFolder = await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => file_manager.FileManager(showCancelBtn: true, updateFolderPath: false)),
                              );

                              if (selectedFolder != null) {
                                selectedFolderPath = selectedFolder;
                                _temporarySelectedFolderPath.value = selectedFolder;
                                print("Selected folder (temporary): $selectedFolderPath");
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _generateFileNamePrefix(DateTime now) {
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = now.year.toString();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    return '${day}_${month}_${year}_${hour}_${minute}_${second}';
  }


  Widget _buildVerticalDivider() {
    return Container(
      height: 24,
      width: 1,
      color: Colors.grey.shade300,
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: MediaQuery.of(context).size.height * 0.60,
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.only(top: 10, bottom: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/app_icon_home.png',
                          height: 80, // Reduced from 80
                          width: 80,  // Reduced from 80
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 60,
                              width: 60,
                              color: Colors.grey[300],
                              child: Icon(Icons.image, color: Colors.grey),
                            );
                          },
                        ),
                        SizedBox(width: 8), // Reduced from 12
                        Text(
                          "RedTree",
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 48, // Reduced from 48
                            fontFamily: 'Times New Roman',
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Scenic Image - Reduced size
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      child: Image.asset(
                        'assets/img_redtree.jpeg',
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: double.infinity,
                            color: Colors.grey[300],
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.image, size: 50, color: Colors.grey),
                                  Text('Image not found', style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  
                  // Capture and Manage Text - Equal top/bottom spacing
                  SizedBox(height: 20),
                  Container(
                    padding: EdgeInsets.symmetric(vertical: 0),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: "Capture",
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                              fontFamily: 'Times New Roman',
                              letterSpacing: 5.0,
                            ),
                          ),
                          TextSpan(
                            text: " & ",
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 18,
                              fontFamily: 'Times New Roman',
                              letterSpacing: 2,
                            ),
                          ),
                          TextSpan(
                            text: "Manage",
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                              fontFamily: 'Times New Roman',
                              letterSpacing: 5.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                ],
              ),
            ),

            // Middle Section - Interactive Elements (Proper vertical stacking)
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    // First Row of Icons (Capture)
                    Container(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildIconButton(
                            icon: Icons.camera_alt_outlined,
                            label: "Shoot",
                            onTap: () => _openCamera(context),
                          ),
                          _buildIconButton(
                            icon: Icons.edit_note_outlined,
                            label: "Note",
                            onTap: () => _showMemoOptions(context),
                          ),
                          _buildIconButton(
                            icon: Icons.mic_outlined,
                            label: "Dictate",
                            onTap: () {
                              // TODO: Implement dictate functionality
                            },
                          ),
                          _buildIconButton(
                            icon: Icons.push_pin_outlined,
                            label: "Annotate",
                            onTap: () {
                              // TODO: Implement annotate functionality
                            },
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 12),
                    // Second Row of Icons (Manage)
                    Container(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildIconButton(
                            icon: Icons.folder_outlined,
                            label: "File",
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => file_manager.FileManager(),
                                ),
                              );
                            },
                          ),
                          _buildIconButton(
                            icon: Icons.cloud_sync_outlined,
                            label: "Sync",
                            onTap: () {
                              // TODO: Implement sync functionality
                            },
                          ),
                          _buildIconButton(
                            icon: Icons.search_outlined,
                            label: "Search",
                            onTap: () {
                              // TODO: Implement search functionality
                            },
                          ),
                          _buildIconButton(
                            icon: Icons.settings_outlined,
                            label: "Config",
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ParametersScreen(
                                    camera: widget.camera,
                                    onDelayChanged: (delay) {
                                      // Handle delay change
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Login/Logout Button at bottom
            Container(
              padding: EdgeInsets.only(bottom: 20),
              child: ValueListenableBuilder<bool>(
                valueListenable: isLoggedInNotifier,
                builder: (context, isLoggedIn, child) {
                  return GestureDetector(
                    onTap: () async {
                      if (isLoggedIn) {
                        // Logout
                        await _logout();
                      } else {
                        // Navigate to Login
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LoginScreen(),
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.zero,
                        border: Border.all(color: Colors.black, width: 1),
                      ),
                      child: Text(
                        isLoggedIn ? "logout".tr : "login".tr,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Times New Roman',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min, // Minimize vertical space
        children: [
          Container(
            width: 65, // Smaller icons
            height: 65,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 1), // Thinner border
              color: Colors.white,
            ),
            child: Icon(
              icon,
              color: Colors.grey.shade600, // Slightly light dark color
              size: 30, // Smaller icons
            ),
          ),
          SizedBox(height: 6), // Reduced spacing between icon and label
          Text(
            label,
            style: TextStyle(
              color: Color(0xFFe81b1b),
              fontSize: 14,
              fontWeight: FontWeight.normal,
              fontFamily: 'Times New Roman',
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
