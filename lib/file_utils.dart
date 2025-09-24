import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'FileManager.dart';
import 'SearchIndex.dart';
import 'note_utils.dart';
import 'package:get/get.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import 'BlinkingMicWidget.dart';
import 'TextEditorScreen.dart';

import 'globals.dart';

class FileUtils {
  static Future<void> showPopupMenu(
      BuildContext context,
      File file,
      CameraDescription camera,
      TapDownDetails? tapDetails, {
        VoidCallback? onFileChanged,
        VoidCallback? onEnterMultiSelectMode,
        VoidCallback? onFilesMoved,
        Function(String oldPath, String newPath)? onFileRenamed,

      }) async {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        overlay.size.width - 160, 60, 20,
        overlay.size.height - 60,
      ),
      items: [
        PopupMenuItem(value: 'annotate', height: 28, child: Text('annotate'.tr)),
        PopupMenuItem(value: 'open', height: 28, child: Text('open'.tr)),
        if (file.path.toLowerCase().endsWith('.txt'))
          PopupMenuItem(value: 'edit', height: 28, child: Text('edit'.tr)),
        PopupMenuItem(value: 'rename', height: 28, child: Text('rename'.tr)),
        PopupMenuItem(value: 'duplicate', height: 28, child: Text('duplicate'.tr)),
        PopupMenuItem(value: 'select', height: 28, child: Text('select'.tr)),
        PopupMenuItem(value: 'move', height: 28, child: Text('moveTo'.tr)),
        PopupMenuItem(value: 'share', height: 28, child: Text('share'.tr)),
        PopupMenuItem(value: 'suppress', height: 28, child: Text('suppress'.tr)),
      ],
    );

    switch (result) {
      case 'annotate':
        NoteUtils.showNoteInputModal(
          context,
          file.path,
              (imagePath, noteText) {
            NoteUtils.addOrUpdateNote(imagePath, noteText, mediaNotesNotifier);
          },
        );
        break;

      case 'edit':
        if (file.path.toLowerCase().endsWith('.txt')) {
          try {
            final content = await file.readAsString();
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TextEditorScreen(
                  textFile: file,
                  initialContent: content,
                ),
              ),
            );
            onFileChanged?.call();
          } catch (e) {
            Fluttertoast.showToast(msg: "failedToReadFile".tr);
          }
        }
        break;

      case 'open':
        final parentDir = file.parent;
        final mediaFiles = parentDir
            .listSync()
            .whereType<File>()
            .where((f) {
              final name = p.basename(f.path);
              if (name.startsWith('.')) return false;
              final lower = f.path.toLowerCase();
              // Include supported media + audio + standalone txt files
              final isMedia = lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') ||
                  lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.webm') || lower.endsWith('.avi');
              final isAudio = lower.endsWith('.mp3') || lower.endsWith('.m4a');
              final isStandaloneTxt = lower.endsWith('.txt') && !_isSidecarNoteForAnyMedia(f.path);
              return isMedia || isAudio || isStandaloneTxt;
            })
            .toList();

        final index = mediaFiles.indexWhere((f) => f.path == file.path);
        if (index != -1) {

          final viewerResult = await Navigator.push<Map<String, dynamic>>(
            context,
            MaterialPageRoute(
              builder: (_) => FullScreenMediaViewer(
                mediaFiles: mediaFiles,
                initialIndex: index,
                camera: camera,
              ),
            ),
          );

          if (viewerResult != null) {
            final hasChanges = viewerResult['hasChanges'] as bool? ?? false;
            final renamedFiles = viewerResult['renamedFiles'] as Map<String, String>? ?? {};
            final folderContentChanged = viewerResult['folderContentChanged'] as bool? ?? false;

            if (hasChanges && renamedFiles.isNotEmpty) {
              for (final entry in renamedFiles.entries) {
                onFileRenamed?.call(entry.key, entry.value);
              }
              onFileChanged?.call();
            }

            if (hasChanges && folderContentChanged) {
              onFileChanged?.call();

            }
          }


          // Defer note loading and UI updates to avoid blocking navigation
          Future.delayed(Duration(milliseconds: 1000), () async {
            await NoteUtils.loadAllNotes("/storage/emulated/0");
            mediaNotesNotifier.notifyListeners();
          });
          
          if (viewerResult == true) {
            // Defer file change callback to avoid blocking navigation
            Future.delayed(Duration(milliseconds: 500), () {
              onFileChanged?.call();
            });
          }
        } else {
          Fluttertoast.showToast(msg: "File not found in media list".tr);
        }
        break;


      case 'rename':
        final oldPath = file.path;

        final renamed = await showRenameDialog(
          context,
          file,
          onMoveRequested: () async {
            Fluttertoast.showToast(
              msg: "Select destination folder".tr,
              toastLength: Toast.LENGTH_LONG,
            );

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => FileManager(
                  selectedPaths: [file.path],
                  enableFolderSelection: true,
                  onFilesMoved: () {
                      onFileChanged?.call();
                      onFilesMoved?.call();
                  }
                ),
              ),
            );
          },
        );
        if (renamed != null) {

        IndexManager.instance.updateForRename(
          oldPath,
          renamed.path,
          renamed is Directory,
        );
        onFileChanged?.call();}

        break;
      case 'duplicate':
        final newFile = await duplicateFile(context, file);
        if (newFile != null) {
          await IndexManager.instance.updateForDuplicate(newFile.path, newFile is Directory);
          onFileChanged?.call();
        }
        break;

      case 'select':
        onEnterMultiSelectMode?.call();
        break;
      case 'move':

        Fluttertoast.showToast(
          msg: "Select destination folder".tr,
          toastLength: Toast.LENGTH_LONG,
        );

      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => FileManager(
              selectedPaths: [file.path],
              enableFolderSelection: true,
              onFilesMoved:() {

            onFileChanged?.call();
            onFilesMoved?.call();

            }
            ),
          ),  (route) => route.isFirst,

      );


        break;
      case 'share':
        await shareFile(context, file);
        break;
      case 'suppress':
        final deleted = await deleteFile(context, file);
        if (deleted != null) {
          IndexManager.instance.updateForDelete(file.path);
          onFileChanged?.call();
        }
        break;

    }
  }




  static Future<File?> deleteFile(BuildContext context, File file) async {
    try {
      await file.delete();

      // Delete corresponding sidecar note: baseName + .txt
      final noteFile = File(p.withoutExtension(file.path) + '.txt');
      if (await noteFile.exists()) {
        await noteFile.delete();
      }
      mediaNotesNotifier.value.remove(file.path);
      mediaReloadNotifier.value++;

      Fluttertoast.showToast(msg: "fileDeleted".tr);
      return file;
    } catch (_) {
      Fluttertoast.showToast(msg: "fileDeleteFailed".tr);
      return null;
    }
  }

  // Helper: detect if a .txt is a sidecar note for any media sibling
  static bool _isSidecarNoteForAnyMedia(String txtPath) {
    if (!txtPath.toLowerCase().endsWith('.txt')) return false;
    final base = p.withoutExtension(txtPath);
    const mediaExts = ['.jpg', '.jpeg', '.png', '.mp4', '.mov', '.webm', '.avi', '.mp3', '.m4a'];
    for (final ext in mediaExts) {
      if (File(base + ext).existsSync() || File(base + ext.toUpperCase()).existsSync()) {
        return true;
      }
    }
    return false;
  }


  static Future<File?> showRenameDialog(
      BuildContext context,
      File file, {
        VoidCallback? onMoveRequested,
      }) async {
    final controller = TextEditingController(text: p.basenameWithoutExtension(file.path));
    bool moveRequested = false;
    File? renamedFile;
    final speech = stt.SpeechToText();
    bool _isListening = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        // Select all text when dialog opens
        WidgetsBinding.instance.addPostFrameCallback((_) {
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          );
        });
        
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              titlePadding: EdgeInsetsGeometry.zero,
              title: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      "rename".tr,
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
              content: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'Enter file name',
                  suffixIcon: BlinkingMicSuffixIcon(
                    isListening: _isListening,
                    onPressed: () async {
                      if (!_isListening) {
                        bool available = await speech.initialize(
                          onStatus: (status) => print('Speech status: $status'),
                          onError: (error) => print('Speech error: $error'),
                        );

                        if (available) {
                          setState(() => _isListening = true);
                          speech.listen(
                            onResult: (result) {
                              final spokenName = result.recognizedWords.replaceAll(' ', '_');
                              controller.text = spokenName;
                            },
                          );
                        }
                      } else {
                        speech.stop();
                        setState(() => _isListening = false);
                      }
                    },
                  ),
                ),
                onTap: () {
                  // Clear selection and place cursor at tapped position
                  // The default behavior will handle cursor placement
                },
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    moveRequested = true;
                    Navigator.pop(_, true);
                  },
                  child: Text("move".tr),
                ),
                TextButton(
                  onPressed: () async {
                    final newPath = p.join(
                      p.dirname(file.path),
                      controller.text + p.extension(file.path),
                    );
                    try {
                      final renamed = await file.rename(newPath);
                      mediaReloadNotifier.value++;
                      Fluttertoast.showToast(msg: "renameSuccess".tr);
                      renamedFile = renamed;
                      Navigator.pop(_, true);
                    } catch (_) {
                      Fluttertoast.showToast(msg: "renameFailed".tr);
                      Navigator.pop(context, false);
                    }
                  },
                  child: Text("ok".tr),
                ),
              ],
            );
          },
        );
      },
    );

    if (moveRequested && confirmed == true) {
      onMoveRequested?.call();
      return null;
    }

    return renamedFile;
  }




  static Future<File?> duplicateFile(BuildContext context, File file) async {
    try {
      String baseName = p.basenameWithoutExtension(file.path);
      String extension = p.extension(file.path);
      String dir = p.dirname(file.path);
      int copyNumber = 1;
      String newPath;

      do {
        newPath = p.join(dir, "$baseName ($copyNumber)$extension");
        copyNumber++;
      } while (File(newPath).existsSync());

      final newFile = await file.copy(newPath);

      await Future.delayed(Duration(milliseconds: 300));

      mediaReloadNotifier.value++;
      await Future.delayed(Duration(milliseconds: 100));
      mediaReloadNotifier.value++;

      Fluttertoast.showToast(msg: "duplicated".tr);
      return newFile;
    } catch (e) {
      debugPrint('❌ Duplication error: $e');
      Fluttertoast.showToast(msg: "duplicationFailed".tr);
      return null;
    }
  }

  static Future<bool> moveFileTo(BuildContext context, File file, String destinationPath) async {
    try {
      if (!await file.exists()) {
        Fluttertoast.showToast(msg: "sourceFileNotFound".tr);
        return false;
      }

      final sourceDir = p.dirname(file.path);
      destinationPath = p.normalize(destinationPath);

      if (sourceDir == destinationPath) {
        Fluttertoast.showToast(msg: "fileInSameFolder".tr);
        return false;
      }

      final newPath = p.join(destinationPath, p.basename(file.path));

      try {
        if (!await Directory(destinationPath).exists()) {
          await Directory(destinationPath).create(recursive: true);
        }
      } catch (e) {
        debugPrint('Directory creation error: $e');
        Fluttertoast.showToast(msg: "cannotCreateDestination".tr);
        return false;
      }

      if (await File(newPath).exists()) {
        final shouldOverwrite = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            titlePadding: EdgeInsetsGeometry.zero,

            title: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'fileExists'.tr,
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
            content: Text('overwriteConfirmation'.tr),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(_, true),
                child: Text('overwrite'.tr),
              ),
            ],
          ),
        );
        if (shouldOverwrite != true) return false;
      }

      try {
        await file.rename(newPath);
      } catch (e) {
        debugPrint('Rename failed, trying copy+delete: $e');
        try {
          await file.copy(newPath);
          await file.delete();
        } catch (copyError) {
          debugPrint('Copy failed: $copyError');
          if (await File(newPath).exists()) {
            try {
              await File(newPath).delete();
            } catch (cleanupError) {
              debugPrint('Cleanup failed: $cleanupError');
            }
          }
          rethrow;
        }
      }

      final notePath = p.withoutExtension(file.path) + '.txt';
      if (await File(notePath).exists()) {
        try {
          final newNotePath = p.withoutExtension(newPath) + '.txt';
          await File(notePath).rename(newNotePath);

          final noteContent = mediaNotesNotifier.value[file.path] ?? '';

          mediaNotesNotifier.value = {
            ...mediaNotesNotifier.value,
            newPath: noteContent,
          };
          mediaNotesNotifier.value.remove(file.path);

          IndexManager.instance.updateNoteContent(newPath, noteContent);
        } catch (noteError) {
          debugPrint('Note move failed: $noteError');
        }
      }


      mediaReloadNotifier.value++;
      Fluttertoast.showToast(msg: "fileMoved".tr);

      return true;
    } catch (e) {
      debugPrint('Move error: $e');
      Fluttertoast.showToast(msg: "fileMoveFailed");
      return false;
    }
  }


  static Future<bool> shareFile(BuildContext context, File file) async {
    try {
      if (!file.existsSync()) {
        Fluttertoast.showToast(msg: "fileNotFound".tr);
        return false;
      }

      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/${p.basename(file.path)}'; // ✅ Fixed
      final tempFile = await file.copy(tempPath);

      await Share.shareXFiles([XFile(tempFile.path)], text: 'shareMessage'.tr);
      return true;
    } catch (e) {
      Fluttertoast.showToast(msg: "shareError ${e.toString()}");
      print("shareError $e");
      return false;
    }
  }

  static Future<void> openFullScreen(BuildContext context, File file, List<File> mediaFiles) async {
    final initialIndex = mediaFiles.indexOf(file);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenMediaViewer(
          mediaFiles: mediaFiles,
          initialIndex: initialIndex,
        ),
      ),
    );

    await NoteUtils.loadAllNotes("/storage/emulated/0");
    mediaNotesNotifier.notifyListeners();
  }



  static Future<bool> isFolderAccessible(String folderPath) async {
    try {
      if (folderPath.isEmpty) return false;
      final directory = Directory(folderPath);
      return await directory.exists();
    } catch (e) {
      return false;
    }
  }

  static void showFolderMovedSnackBar(BuildContext context, String folderPath) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Folder path "$folderPath" has been moved. Please define a new path.'),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'SET PATH',
          onPressed: () {

          },
        ),
      ),
    );
  }

  /// Automatically creates the RedTree folder if it doesn't exist
/// This function should be called during app initialization
static Future<void> ensureRedTreeFolderExists() async {
    try {
      print('🔄 Initializing RedTree folder...');
      
      if (Platform.isAndroid) {
        // First, try to request all necessary permissions
        await _requestStoragePermissions();

        // Try to create RedTree folder in multiple locations for compatibility
        String? successfulPath = await _createRedTreeFolder();
        
        if (successfulPath != null) {
          await _setDefaultStoragePath(successfulPath);
          print('✅ RedTree folder initialized at: $successfulPath');
        } else {
          // Fallback to app documents directory
          final appDir = await getApplicationDocumentsDirectory();
          final redTreeDir = Directory('${appDir.path}/RedTree');
          
          if (!await redTreeDir.exists()) {
            await redTreeDir.create(recursive: true);
          }
          
          await _setDefaultStoragePath(redTreeDir.path);
          print('✅ RedTree folder created in app directory: ${redTreeDir.path}');
        }
      } else {
        // For iOS, create folder in documents directory
        final appDir = await getApplicationDocumentsDirectory();
        final redTreeDir = Directory('${appDir.path}/RedTree');
        
        if (!await redTreeDir.exists()) {
          await redTreeDir.create(recursive: true);
        }
        
        await _setDefaultStoragePath(redTreeDir.path);
        print('✅ RedTree folder created for iOS: ${redTreeDir.path}');
      }
    } catch (e) {
      print('❌ Error initializing RedTree folder: $e');
      // Fallback to app documents directory
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final redTreeDir = Directory('${appDir.path}/RedTree');
        if (!await redTreeDir.exists()) {
          await redTreeDir.create(recursive: true);
        }
        await _setDefaultStoragePath(appDir.path);
        print('✅ Fallback: RedTree folder in app directory');
      } catch (fallbackError) {
        print('❌ Fallback storage initialization failed: $fallbackError');
      }
    }
  }

  // Request storage permissions for Android
  static Future<void> _requestStoragePermissions() async {
    try {
      if (Platform.isAndroid) {
        // Request basic storage permissions first
        final storageStatus = await Permission.storage.status;
        if (!storageStatus.isGranted) {
          await Permission.storage.request();
        }

        // For Android 11+, also request manage external storage if available
        final manageStorageStatus = await Permission.manageExternalStorage.status;
        if (!manageStorageStatus.isGranted) {
          await Permission.manageExternalStorage.request();
        }
      }
    } catch (e) {
      print('❌ Error requesting storage permissions: $e');
    }
  }

  // Try to create RedTree folder in external storage locations
  static Future<String?> _createRedTreeFolder() async {
    // List of potential locations to try
    final potentialPaths = [
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Download/RedTree',
      '/storage/emulated/0/RedTree',
      '/storage/emulated/0/Documents/RedTree',
    ];

    for (final path in potentialPaths) {
      try {
        final dir = Directory(path);
        
        // Try to create the directory
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        
        // Test if we can actually write to this directory
        final testFile = File('${dir.path}/.test');
        await testFile.writeAsString('test');
        await testFile.delete();
        
        print('✅ Successfully created and tested RedTree folder at: $path');
        return path;
      } catch (e) {
        print('⚠️ Failed to create folder at $path: $e');
        continue;
      }
    }
    
    return null;
  }

  // Set default storage path only if no custom path exists
  static Future<void> _setDefaultStoragePath(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if user has already set a custom folder path
      final existingPath = prefs.getString('folderPath');
      if (existingPath == null || existingPath.isEmpty) {
        // Only set default path if no custom path exists
        await prefs.setString('folderPath', path);
        folderPathNotifier.value = path;
        print('✅ Set default folder path: $path');
      } else {
        // User has a custom path, don't override it
        print('✅ Keeping user\'s custom folder path: $existingPath');
        // Still update the notifier to match the saved path
        if (folderPathNotifier.value != existingPath) {
          folderPathNotifier.value = existingPath;
        }
      }
    } catch (e) {
      print('❌ Error setting default storage path: $e');
    }
  }



  /// Check if the RedTree folder exists and is accessible
  Future<bool> isRedTreeFolderAccessible() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String folderPath = prefs.getString('folderPath') ?? "/storage/emulated/0/Download";
      
      final directory = Directory(folderPath);
      if (!await directory.exists()) {
        return false;
      }
      
      // Test if we can write to the directory
      final testFile = File('${directory.path}/.test');
      await testFile.writeAsString('test');
      await testFile.delete();
      return true;
    } catch (e) {
      print('❌ RedTree folder is not accessible: $e');
      return false;
    }
  }
}






