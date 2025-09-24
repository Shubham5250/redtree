import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;
import 'package:path/path.dart' as p;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'BlinkingMicWidget.dart';

import 'SearchIndex.dart';
import 'globals.dart';


class NoteUtils {
  // static Future<void> showNoteInputModal(
  //     BuildContext context,
  //     String imagePath,
  //     Function(String, String) onNoteSubmitted, {
  //       String initialText = '',
  //       bool isEditing = false,
  //     })
  // async {
  //   final TextEditingController noteController = TextEditingController(text: initialText);
  //   final speech = stt.SpeechToText();
  //   bool _isListening = false;
  //
  //   await showModalBottomSheet(
  //     context: context,
  //     isScrollControlled: true,
  //     shape: const RoundedRectangleBorder(
  //       borderRadius: BorderRadius.zero, // no radius at all
  //     ),
  //     clipBehavior: Clip.antiAlias, // ensure shape is app
  //     builder: (context) {
  //       return Padding(
  //         padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
  //         child: StatefulBuilder(
  //           builder: (context, setState) {
  //             return Padding(
  //               padding: const EdgeInsets.all(16),
  //               child: Column(
  //                 mainAxisSize: MainAxisSize.min,
  //                 children: [
  //                   Row(
  //                     children: [
  //                       IconButton(
  //                         icon: const Icon(Icons.keyboard),
  //                         tooltip: 'keyboardInput'.tr,
  //                         onPressed: () {},
  //                       ),
  //                       IconButton(
  //                         icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
  //                         color: _isListening ? Colors.red : null,
  //                         tooltip: 'voiceInput'.tr,
  //                         onPressed: () async {
  //                           if (!_isListening) {
  //                             final available = await speech.initialize(
  //                               onStatus: (status) => debugPrint('Speech status: $status'),
  //                               onError: (error) => debugPrint('Speech error: $error'),
  //                             );
  //
  //                             if (available) {
  //                               setState(() => _isListening = true);
  //                               speech.listen(
  //                                 onResult: (result) {
  //                                   if (result.finalResult) {
  //                                     noteController.text = result.recognizedWords;
  //                                   }
  //                                 },
  //                               );
  //                             }
  //                           } else {
  //                             speech.stop();
  //                             setState(() => _isListening = false);
  //                           }
  //                         },
  //                       ),
  //                       if (_isListening)
  //                         Padding(
  //                           padding: const EdgeInsets.only(left: 8),
  //                           child: Text(
  //                             'listening'.tr,
  //                             style: const TextStyle(color: Colors.red),
  //                           ),
  //                         ),
  //                     ],
  //                   ),
  //                   TextField(
  //                     controller: noteController,
  //                     maxLines: 5,
  //                     autofocus: true,
  //                     decoration: InputDecoration(
  //                       hintText: 'typeYourNoteHere'.tr,
  //                       border: const OutlineInputBorder(),
  //                       suffixIcon: noteController.text.isNotEmpty
  //                           ? IconButton(
  //                         icon: const Icon(Icons.clear),
  //                         onPressed: () => noteController.clear(),
  //                       )
  //                           : null,
  //                     ),
  //                   ),
  //                   const SizedBox(height: 16),
  //                   Row(
  //                     mainAxisAlignment: MainAxisAlignment.end,
  //                     children: [
  //                       TextButton(
  //                         onPressed: () => Navigator.pop(context),
  //                         child: Text('cancel'.tr),
  //                       ),
  //                       const SizedBox(width: 8),
  //                       ElevatedButton(
  //                         onPressed: () {
  //                           final note = noteController.text.trim();
  //                           if (note.isNotEmpty) {
  //                             onNoteSubmitted(imagePath, note);
  //                             saveNoteToFile(imagePath, note);
  //                             Fluttertoast.showToast(
  //                               msg: isEditing ? 'noteUpdated'.tr : 'noteSaved'.tr,
  //                               toastLength: Toast.LENGTH_SHORT,
  //                             );
  //                           }
  //                           Navigator.pop(context);
  //                         },
  //                         child: Text(isEditing ? 'update'.tr : 'save'.tr),
  //                       ),
  //                     ],
  //                   ),
  //                 ],
  //               ),
  //             );
  //           },
  //         ),
  //       );
  //     },
  //   );
  // }

  static Future<void> showNoteInputModal(
      BuildContext context,
      String imagePath,
      Function(String, String) onNoteSubmitted, {
        String initialText = '',
        bool isEditing = false,
      }) async {
    // Load existing note if no initial text provided
    String existingNote = initialText;
    if (existingNote.isEmpty) {
      // First check if note exists in memory (notifiers)
      existingNote = mediaNotesNotifier.value[imagePath] ?? 
                    folderNotesNotifier.value[imagePath] ?? '';
      
      // If not in memory, load from file
      if (existingNote.isEmpty) {
        // Check if it's a folder note by checking if folderNotesNotifier has this path
        if (folderNotesNotifier.value.containsKey(imagePath)) {
          existingNote = await loadFolderNoteFromFile(imagePath) ?? '';
        } else {
          existingNote = await loadNoteFromFile(imagePath) ?? '';
        }
      }
    }
    
    final TextEditingController noteController = TextEditingController(text: existingNote);
    final speech = stt.SpeechToText();
    bool _isListening = false;
    bool _shouldKeepListening = false; // Flag to control continuous listening
    String _lastFinalText = ''; // Track the last final result to avoid repetition

    // Helper function to start continuous speech recognition
    Future<void> startContinuousSpeechRecognition(Function setState) async {
      if (!_shouldKeepListening) return;
      
      try {
        final available = await speech.initialize(
          onStatus: (status) {
            debugPrint('Speech status: $status');
            // Restart if engine stops
            if ((status == 'done' || status == 'notListening') && _shouldKeepListening) {
              debugPrint('Speech stopped, restarting continuous listening...');
              // Restart after a short delay
              Future.delayed(Duration(milliseconds: 500), () {
                if (_shouldKeepListening) {
                  startContinuousSpeechRecognition(setState);
                }
              });
            }
          },
          onError: (error) {
            debugPrint('Speech error: $error');
            // Restart on error if we should keep listening
            if (_shouldKeepListening) {
              debugPrint('Speech error occurred, restarting...');
              Future.delayed(Duration(milliseconds: 1000), () {
                if (_shouldKeepListening) {
                  startContinuousSpeechRecognition(setState);
                }
              });
            }
          },
        );
        
        if (available && _shouldKeepListening) {
          setState(() {
            _isListening = true;
          });
          
          await speech.listen(
            onResult: (result) {
              setState(() {
                if (result.finalResult) {
                  // Only add if it's different from the last final result to avoid repetition
                  if (result.recognizedWords != _lastFinalText && result.recognizedWords.isNotEmpty) {
                    if (noteController.text.isNotEmpty && !noteController.text.endsWith(' ')) {
                      noteController.text += ' ';
                    }
                    noteController.text += result.recognizedWords;
                    _lastFinalText = result.recognizedWords;
                  }
                } else {
                  // For partial results, show a preview but don't add to final text
                  debugPrint('Partial result: ${result.recognizedWords}');
                }
              });
            },
            listenFor: Duration(minutes: 10),
            pauseFor: Duration(seconds: 30),
            partialResults: true,
            localeId: 'en_US',
            listenMode: stt.ListenMode.dictation,
            onSoundLevelChange: (level) {
              debugPrint('Sound level: $level');
            },
          );
        } else if (!available) {
          setState(() {
            _isListening = false;
            _shouldKeepListening = false;
          });
          Fluttertoast.showToast(msg: 'Speech recognition not available');
        }
      } catch (e) {
        debugPrint('Error starting speech recognition: $e');
        // Retry after delay if we should keep listening
        if (_shouldKeepListening) {
          Future.delayed(Duration(milliseconds: 2000), () {
            if (_shouldKeepListening) {
              startContinuousSpeechRecognition(setState);
            }
          });
        }
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      clipBehavior: Clip.antiAlias,
      isDismissible: true,
      enableDrag: true,
      builder: (context) {
        // Select all text when modal opens
        WidgetsBinding.instance.addPostFrameCallback((_) {
          noteController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: noteController.text.length,
          );
        });
        
        return PopScope(
          canPop: true,
          onPopInvoked: (didPop) {
            if (didPop) {
              // Clean up continuous speech recognition when back button is pressed
              _shouldKeepListening = false;
              speech.stop();
              debugPrint('Continuous speech recognition stopped due to back button');
            }
          },
          child: Padding(
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
                              tooltip: 'keyboardInput'.tr,
                              onPressed: () {},
                            ),
                            BlinkingMicWidget(
                              isListening: _isListening,
                              tooltip: 'voiceInput'.tr,
                              onPressed: () async {
                                if (!_isListening) {
                                  // Start continuous speech recognition
                                  setState(() {
                                    _shouldKeepListening = true;
                                  });
                                  await startContinuousSpeechRecognition(setState);
                                } else {
                                  // Stop continuous speech recognition
                                  setState(() {
                                    _shouldKeepListening = false;
                                    _isListening = false;
                                  });
                                  speech.stop();
                                }
                              },
                            ),
                            if (_isListening)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  'listening'.tr,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            // Stop continuous speech recognition before closing
                            _shouldKeepListening = false;
                            speech.stop();
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                    TextField(
                      controller: noteController,
                      maxLines: 5,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'typeYourNoteHere'.tr,
                        border: const OutlineInputBorder(),
                      ),
                      onTap: () {
                        // Clear selection and place cursor at tapped position
                        // The default behavior will handle cursor placement
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            // Stop continuous speech recognition before saving
                            _shouldKeepListening = false;
                            speech.stop();
                            
                            final note = noteController.text.trim();
                            if (note.isNotEmpty) {
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (context) => const Center(child: CircularProgressIndicator()),
                              );
                              Navigator.pop(context); // Close modal
                              await onNoteSubmitted(imagePath, note);
                              Navigator.pop(context); // Close modal

                              await saveNoteToFile(imagePath, note);

                              Fluttertoast.showToast(
                                msg: isEditing ? 'noteUpdated'.tr : 'noteSaved'.tr,
                                toastLength: Toast.LENGTH_SHORT,
                              );
                            }

                          },
                          child: Text('ok'.tr),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),),
        );
      },
    );
  }

  //
  // static void saveNoteToFile(String imagePath, String note) {
  //   try {
  //     final notePath = path.withoutExtension(imagePath) + ".txt";
  //     File(notePath).writeAsStringSync(note);
  //     debugPrint('Note saved to: $notePath');
  //     mediaNotesNotifier.value = {
  //       ...mediaNotesNotifier.value,
  //       imagePath: note,
  //     };
  //     IndexManager.instance.updateNoteContent(imagePath, note);
  //
  //   } catch (e) {
  //     debugPrint('Error saving note: $e');
  //   }
  // }
  static Future<void> saveNoteToFile(String imagePath, String note) async {
    try {
      final start = DateTime.now();
      final notePath = p.withoutExtension(imagePath) + ".txt";
      await File(notePath).writeAsString(note);
      debugPrint('File write took: ${DateTime.now().difference(start).inMilliseconds}ms');

      final indexStart = DateTime.now();
      await IndexManager.instance.updateNoteContent(imagePath, note);
      debugPrint('Index update took: ${DateTime.now().difference(indexStart).inMilliseconds}ms');
    } catch (e) {
      debugPrint('Error saving note: $e');
    }
  }

  static Future<void> saveFolderNoteToFile(String folderPath, String note) async {
    try {
      final start = DateTime.now();
      final notePath = folderPath + ".txt";
      await File(notePath).writeAsString(note);
      debugPrint('Folder note file write took: ${DateTime.now().difference(start).inMilliseconds}ms');

      final indexStart = DateTime.now();
      await IndexManager.instance.updateNoteContent(folderPath, note);
      debugPrint('Folder note index update took: ${DateTime.now().difference(indexStart).inMilliseconds}ms');
    } catch (e) {
      debugPrint('Error saving folder note: $e');
    }
  }

  // static void addOrUpdateNote(
  //     String imagePath,
  //     String noteText,
  //     ValueNotifier<Map<String, String>> mediaNotesNotifier,
  //     ) {
  //   mediaNotesNotifier.value = {
  //     ...mediaNotesNotifier.value,
  //     imagePath: noteText,
  //   };
  //   IndexManager.instance.updateNoteContent(imagePath, noteText);
  //
  // }

  static Future<void> addOrUpdateNote(
      String imagePath,
      String noteText,
      ValueNotifier<Map<String, String>> mediaNotesNotifier,
      ) async {
    // Update the notifier immediately for instant UI feedback
    mediaNotesNotifier.value = {
      ...mediaNotesNotifier.value,
      imagePath: noteText,
    };
    
    // Then update the index manager in the background
    await IndexManager.instance.updateNoteContent(imagePath, noteText);
  }

  static Future<void> addOrUpdateFolderNote(
      String folderPath,
      String noteText,
      ValueNotifier<Map<String, String>> folderNotesNotifier,
      ) async {
    // Update the notifier immediately for instant UI feedback
    folderNotesNotifier.value = {
      ...folderNotesNotifier.value,
      folderPath: noteText,
    };
    
    // Then update the index manager in the background
    await IndexManager.instance.updateNoteContent(folderPath, noteText);
  }

  static Future<String?> loadNoteFromFile(String imagePath) async {
    try {
      final notePath = path.withoutExtension(imagePath) + ".txt";
      final file = File(notePath);
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      debugPrint('Error loading note: $e');
    }
    return null;
  }

  static Future<String?> loadFolderNoteFromFile(String folderPath) async {
    try {
      final notePath = path.withoutExtension(folderPath) + ".txt";
      final file = File(notePath);
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      debugPrint('Error loading folder note: $e');
    }
    return null;
  }


  static Future<void> loadAllNotes(String rootPath) async {
    Map<String, String> loadedFileNotes = {};
    Map<String, String> loadedFolderNotes = {};

    final rootDir = Directory(rootPath);

    if (!rootDir.existsSync()) return;

    final List<FileSystemEntity> allFiles = [];
    final List<Directory> allDirs = [];

    void safeCollectFiles(Directory dir) {
      try {
        for (var entity in dir.listSync(recursive: false)) {
          if (entity is File) {
            allFiles.add(entity);
          } else if (entity is Directory) {
            allDirs.add(entity);
            safeCollectFiles(entity);
          }
        }
      } catch (e) {
        debugPrint('🚫 Skipped inaccessible folder: ${dir.path} → $e');
      }
    }

    safeCollectFiles(rootDir);

    // Load file notes synchronously for better performance
    for (final entity in allFiles) {
      if (entity.path.endsWith('.txt')) {
        try {
          final noteContent = File(entity.path).readAsStringSync();
          final imagePath = entity.path.replaceAll(RegExp(r'\.txt$'), '');

          loadedFileNotes[imagePath] = noteContent;
        } catch (e) {
          debugPrint('❌ Failed to read note from ${entity.path}: $e');
        }
      }
    }

    // Load folder notes synchronously for better performance
    for (final dir in allDirs) {
      final notePath = dir.path + ".txt";
      final noteFile = File(notePath);
      if (noteFile.existsSync()) {
        try {
          final noteContent = noteFile.readAsStringSync();
          loadedFolderNotes[dir.path] = noteContent;
        } catch (e) {
          debugPrint('❌ Failed to read folder note from ${notePath}: $e');
        }
      }
    }

    // Update notifiers immediately for instant UI updates
    mediaNotesNotifier.value = loadedFileNotes;
    folderNotesNotifier.value = loadedFolderNotes;
    debugPrint("[DEBUG] Loaded ${loadedFileNotes.length} file notes and ${loadedFolderNotes.length} folder notes from disk.");
  }


  static Future<void> showNoteDialog(
      BuildContext context,
      String imagePath,
      ValueNotifier<Map<String, String>> mediaNotesNotifier,
      ) async {
    final currentNote = mediaNotesNotifier.value[imagePath] ?? await loadNoteFromFile(imagePath);
    final hasNote = currentNote != null && currentNote.isNotEmpty;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
        // contentPadding: EdgeInsetsGeometry.zero,
        titlePadding: EdgeInsetsGeometry.zero,
        title: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'note'.tr,
                style: Theme.of(context).textTheme.titleLarge,
              ),
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
        content: Text(hasNote ? currentNote! : 'noNoteFound'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('close'.tr),
          ),
          if (hasNote)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                showNoteInputModal(
                  context,
                  imagePath,
                      (path, note) => addOrUpdateNote(path, note, mediaNotesNotifier),
                  initialText: currentNote!,
                  isEditing: true,
                );
              },
              child: Text('edit'.tr),
            ),
          TextButton(
            onPressed: () {
              mediaNotesNotifier.value = {...mediaNotesNotifier.value}..remove(imagePath);
              deleteNoteFile(imagePath);
              Fluttertoast.showToast(msg: 'noteDeleted'.tr);
              Navigator.pop(context);
            },
            child: Text(
              'delete'.tr,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> showFolderNoteDialog(
      BuildContext context,
      String folderPath,
      ValueNotifier<Map<String, String>> folderNotesNotifier,
      ) async {
    final currentNote = folderNotesNotifier.value[folderPath] ?? await loadFolderNoteFromFile(folderPath);
    final hasNote = currentNote != null && currentNote.isNotEmpty;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
        titlePadding: EdgeInsetsGeometry.zero,
        title: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'folderNote'.tr,
                style: Theme.of(context).textTheme.titleLarge,
              ),
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
        content: Text(hasNote ? currentNote! : 'noNoteFound'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('close'.tr),
          ),
          if (hasNote)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                showNoteInputModal(
                  context,
                  folderPath,
                      (path, note) => addOrUpdateFolderNote(path, note, folderNotesNotifier),
                  initialText: currentNote!,
                  isEditing: true,
                );
              },
              child: Text('edit'.tr),
            ),
          TextButton(
            onPressed: () {
              folderNotesNotifier.value = {...folderNotesNotifier.value}..remove(folderPath);
              deleteFolderNoteFile(folderPath);
              Fluttertoast.showToast(msg: 'noteDeleted'.tr);
              Navigator.pop(context);
            },
            child: Text(
              'delete'.tr,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  static void deleteNoteFile(String imagePath) {
    try {
      final notePath = path.withoutExtension(imagePath) + ".txt";
      File(notePath).deleteSync();
      IndexManager.instance.updateNoteContent(imagePath, null);

    } catch (e) {
      debugPrint('Error deleting note file: $e');
    }
  }

  static void deleteFolderNoteFile(String folderPath) {
    try {
      final notePath = folderPath + ".txt";
      File(notePath).deleteSync();
      IndexManager.instance.updateNoteContent(folderPath, null);

    } catch (e) {
      debugPrint('Error deleting folder note file: $e');
    }
  }
}

