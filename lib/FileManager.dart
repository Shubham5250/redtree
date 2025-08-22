import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:RedTree/Parameters.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_treeview/flutter_treeview.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get_utils/get_utils.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'ProgressDialog.dart';
import 'SearchIndex.dart';
import 'file_utils.dart';
import 'globals.dart';
import 'package:path/path.dart' as p;
import 'image_crop.dart';
import 'main.dart';
import 'note_utils.dart';
import 'package:image/image.dart' as img;

class FileManager extends StatefulWidget {
  final bool showCancelBtn;
  final bool updateFolderPath;
  final List<String> selectedPaths;
  final bool enableFolderSelection;
  final VoidCallback? onFilesMoved;
  final bool isDestinationSelection;
  final Function(String oldPath, String newPath)? onFileRenamed;

  final void Function(String folderPath)? onFolderSelected;

  const FileManager({super.key, this.showCancelBtn = false,  this.updateFolderPath = false, this.enableFolderSelection = false, this.onFolderSelected,  this.selectedPaths = const [],this.onFileRenamed, this.onFilesMoved,     this.isDestinationSelection = false,
  });

  @override
  State<FileManager> createState() => _FileManagerState();
}

class _FileManagerState extends State<FileManager> {
  TreeViewController? _treeViewController = TreeViewController(children: []);
  bool _isFolderSelectionMode = false;
  String? _destinationFolderPath;
  bool _doubleTapDetected = false;


  late final CameraDescription camera;
  final ValueNotifier<String> _searchQuery = ValueNotifier<String>('');

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<Node> _originalNodes = [];
  late Key _treeKey = UniqueKey();
  bool _isMoveMode = false;
  String? _moveSourcePath;
  List<String> _selectedForMove = [];
   String rootPath = "/storage/emulated/0";

  List<IndexedEntry> _allIndexedEntries = [];

  List<String> expandedFolders = [];
  bool _expandedFoldersLoaded = false;
  bool _searchInProgress = false;

  bool isLoading = true;
  final Set<String> loadedFolders = {};
  String?
      _targetMediaFolderPath;
  bool _okPressed = false;
  final String defaultFolderPath = folderPathNotifier.value;
  final Map<String, List<Node>> folderContentsCache = {};

  final ScrollController _scrollController = ScrollController();
  List<Node<dynamic>> _filteredNodes = [];
  List<Node> _fullTreeNodes = [];
  bool _isMultiSelectMode = false;
  Set<String> _selectedFilePaths = {};
  List<String> _selectedFolderPaths = [];

  int _treeReloadKey = 0;

  File? _selectedFile;

  bool isAwaitingMultiFileMove = false;

  final ValueNotifier<bool> isIndexing = ValueNotifier<bool>(true);

  @override
  void initState() {
    super.initState();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is List<String>) {
      _selectedForMove = args;
      _isMoveMode = true;
    }
    if (widget.selectedPaths.isNotEmpty) {
      _enterMoveMode(widget.selectedPaths);
    }


    WidgetsBinding.instance.addPostFrameCallback((_) {
      validateFolderPath(context);
    });
    refreshTreeView();
    _initializeTree(folderPathNotifier.value);

    availableCameras().then((cameras) {
      setState(() {
        camera = cameras.first;
      });
    });
    folderPathNotifier.addListener(_handleFolderPathChange);
    _searchQuery.addListener(_handleSearchChange);


    _initializeIndexAndSearch();

  }

  @override
  void dispose() {
    _searchQuery.removeListener(_handleSearchChange);
    _searchController.dispose();
    super.dispose();
  }



  Future<List<String>> loadExpandedFolders() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('expandedFolders') ?? [];
  }



  Future<void> _initializeIndexAndSearch() async {
    final cachedEntries = await IndexManager.instance.loadIndexFromDisk();
    if (cachedEntries.isNotEmpty) {
      IndexManager.instance.setEntries(cachedEntries);
      isIndexing.value = false;
      _handleSearchChange();
    }


    IndexManager.instance.indexFileSystemRecursively("/storage/emulated/0").then((_) async {
      print("✅ Index ready.");
      isIndexing.value = false;
      _handleSearchChange();
      await IndexManager.instance.saveIndexToDisk();
    });
  }





  void _handleSearchChange() {
    final query = _searchQuery.value.trim().toLowerCase();

    if (query.isEmpty) {
      setState(() {
        _searchInProgress = false;
        _filteredNodes = _treeViewController!.children;
      });
      return;
    }

    if (isIndexing.value) {
      setState(() {
        _searchInProgress = true;
        _filteredNodes = [];
      });

      Future.doWhile(() async {
        await Future.delayed(Duration(milliseconds: 500));
        if (!isIndexing.value) {
          final matches = IndexManager.instance.search(query);
          setState(() {
            _searchInProgress = false;
            _filteredNodes = buildSearchTree(matches);
          });
          return false;
        }
        return true;
      });

      return;
    }

    final matches = IndexManager.instance.search(query);
    setState(() {
      _searchInProgress = false;
      _filteredNodes = buildSearchTree(matches);
    });
  }

  List<Node> buildSearchTree(List<IndexedEntry> matches) {
    const basePath = '/storage/emulated/0';
    final Map<String, Node> nodeMap = {};

    for (final entry in matches) {
      final relativePath = entry.path.replaceFirst(basePath, '').replaceAll(RegExp(r'^/'), '');
      final parts = p.split(relativePath);
      String currentPath = basePath;
      Node? parent;

      for (final part in parts) {
        currentPath = p.join(currentPath, part);

        if (!nodeMap.containsKey(currentPath)) {
          final newNode = Node(
            key: currentPath,
            label: part,
            children: [],
            expanded: true,
            data: {'isFile': !entry.isFolder},
          );
          nodeMap[currentPath] = newNode;

          if (parent != null) {
            parent.children!.add(newNode);
          }
        }

        parent = nodeMap[currentPath];
      }
    }

    return nodeMap.values
        .where((node) => !nodeMap.values.any((n) => n.children!.contains(node)))
        .toList();
  }


  Future<void> validateFolderPath(BuildContext context) async {
    final currentPath = folderPathNotifier.value;

    if (!await FileUtils.isFolderAccessible(currentPath)) {
      if (context.mounted) {
        FileUtils.showFolderMovedSnackBar(context, currentPath);
        folderPathNotifier.value = '';
      }
    }
  }



  void _handleFolderPathChange() {
    if (folderPathNotifier.value.isNotEmpty) {
      _refreshTree(folderPathNotifier.value).then((_) {
        Navigator.pop(context);
      });
    }
  }


  Future<void> _initializeTree(String fullPath) async {
    setState(() => isLoading = true);
    await requestStoragePermission();
    _targetMediaFolderPath = fullPath;

    if (!_expandedFoldersLoaded) {
      List<String> savedExpanded = await loadExpandedFolders();
      expandedFolders.clear();
      expandedFolders.addAll(savedExpanded);
      _expandedFoldersLoaded = true;
    }

    await _refreshTree(fullPath);

  }


  Future<List<Node>> _loadFolderTreeRecursively(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) return [];

    List<FileSystemEntity> entities;
    try {
      entities = directory.listSync();
    } catch (e) {
      debugPrint('⚠️ Skipping inaccessible folder: $path, error: $e');
      return [];
    }

    final List<Node> children = [];

    for (var entity in entities) {
      if (p.basename(entity.path).startsWith('.')) continue;

      if (entity is Directory) {
        final subChildren = await _loadFolderTreeRecursively(entity.path);
        children.add(Node(
          key: entity.path,
          label: p.basename(entity.path),
          children: subChildren,
          expanded: false,
          data: {'loaded': true},
        ));
      } else if (entity is File) {
        children.add(Node(
          key: entity.path,
          label: p.basename(entity.path),
          data: {'isFile': true},
        ));
      }
    }

    return children;
  }



  Future<void> _refreshTree(String path) async {
    if (!mounted) return;

    if (!_expandedFoldersLoaded) {
      expandedFolders.clear();
      List<String> parts = path.split('/');
      String currentPath = '';

      for (int i = 1; i < parts.length; i++) {
        currentPath += '/' + parts[i];
        expandedFolders.add(currentPath);
      }
    }

    setState(() => isLoading = true);
    final rootDir = Directory("/storage/emulated/0");
    List<Node> nodes = await _buildFileTree(rootDir);

    if (mounted) {
      setState(() {

        _treeViewController = TreeViewController(
          children: nodes,
          selectedKey: path,
        );
        _originalNodes = List<Node>.from(nodes);

        isLoading = false;
      });
    }
  }


  Future<void> moveItem(String sourcePath) async {
    setState(() {
      _isMoveMode = true;
      _moveSourcePath = sourcePath;
      _selectedForMove = [sourcePath];
    });

    Fluttertoast.showToast(msg: "selectDestinationFromTree".tr);
  }


  void  _enterMoveMode(List<String> pathsToMove) {
    setState(() {
      _isMoveMode = true;
      _selectedForMove = List.from(pathsToMove);
    });
  }


  Future<void> _confirmAndMove(String destinationPath) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("confirmMove".tr),
            SizedBox(height: 4),
            Text(
              destinationPath,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 4),

          ],
        ),
        duration: Duration(minutes: 3),
        action: SnackBarAction(
          label: 'moveFolder'.tr,
          onPressed: () async {
            await _executeMoveOperation(destinationPath);

            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
        actionOverflowThreshold: 1,
      ),
    );

  }

  Future<void> _executeMoveOperation(String destinationPath) async {
    setState(() => isLoading = true);

    try {
      final affectedPaths = <String>{
        p.dirname(_selectedForMove.first),
        destinationPath
      };

      for (var sourcePath in _selectedForMove) {
        final isDirectory = Directory(sourcePath).existsSync();
        final isFile = File(sourcePath).existsSync();

        if (!isDirectory && !isFile) continue;

        final itemName = p.basename(sourcePath);
        final newPath = p.join(destinationPath, itemName);


        await Directory(destinationPath).create(recursive: true);

        if (isDirectory) {
          await _moveDirectory(Directory(sourcePath), Directory(newPath));
        } else {
          await FileUtils.moveFileTo(context, File(sourcePath), destinationPath);
        }
      }

      await Future.delayed(Duration(milliseconds: 500));


      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => FileManager(
            selectedPaths: [],
            enableFolderSelection: false,
          ),
        ),
      );
      setState(() {});

      if (widget.onFilesMoved != null) {
        widget.onFilesMoved!();
      }

      Fluttertoast.showToast(msg: "itemsMovedSuccess".tr);
    } catch (e) {
      debugPrint('Move error: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          _isMoveMode = false;
          _selectedForMove.clear();
        });
      }
    }
  }


  void _cancelMoveMode() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (mounted) {
      setState(() {
        _isMoveMode = false;
        _selectedForMove.clear();
      });
    }
    Fluttertoast.showToast(msg: "moveCancelled".tr);
  }

  Future<void> _moveDirectory(Directory source, Directory destination) async {
    try {
      await source.rename(destination.path);
      debugPrint('Directory renamed successfully');
    } catch (e) {
      debugPrint('Rename failed, trying copy+delete: $e');
      await _copyDirectory(source, destination);

      final copiedFiles = await Directory(destination.path).list().toList();
      if (copiedFiles.isEmpty) {
        throw Exception('No files were copied to destination');
      }

      await source.delete(recursive: true);
      debugPrint('Directory moved via copy+delete');
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    try {
      if (!await destination.exists()) {
        await destination.create(recursive: true);
      }

      await for (var entity in source.list(recursive: false)) {
        final newPath = p.join(destination.path, p.basename(entity.path));

        if (entity is Directory) {
          await _copyDirectory(entity, Directory(newPath));
        } else if (entity is File) {
          await entity.copy(newPath);
        }
      }
    } catch (e) {
      debugPrint('Copy directory error: $e');
      if (await destination.exists()) {
        await destination.delete(recursive: true);
      }
      rethrow;
    }
  }


  Future<void> refreshTreeView({String? targetPath}) async {
    if (!mounted) return;

    setState(() => isLoading = true);

    try {
      final path = targetPath ?? folderPathNotifier.value;
      final rootDir = Directory(path);


      final List<Node<dynamic>> nodes = await _buildFileTree(Directory(path));

      if (mounted) {
        setState(() {
          _treeViewController = TreeViewController(
            children: nodes,
            selectedKey: path,
          );
          isLoading = false;
        });
        _treeKey = UniqueKey();
      }
    } catch (e) {
      debugPrint('Refresh error: $e');
      if (mounted) {
        setState(() => isLoading = false);
        Fluttertoast.showToast(msg: "refreshFailed".tr);
      }
    }
  }



  Future<List<Node<dynamic>>> _buildFileTree(Directory directory) async {
    List<Node<dynamic>> nodes = [];

    try {
      final entities = await directory.list().toList();

      final folders = entities.whereType<Directory>()
          .where((d) => !d.path.startsWith('.'));

      for (var folder in folders) {
        final shouldExpand = expandedFolders.contains(folder.path);
        final List<Node<dynamic>> children = shouldExpand
            ? await _buildFileTree(folder)
            : <Node<dynamic>>[];

        nodes.add(Node<dynamic>(
          key: folder.path,
          label: p.basename(folder.path),
          expanded: shouldExpand,
          children: children,
          icon: _isMoveMode && !_selectedForMove.contains(folder.path)
              ? Icons.folder_special
              : Icons.folder,
          data: {
            'loaded': shouldExpand,
            'isMoveTarget': _isMoveMode && !_selectedForMove.contains(folder.path),
            'isExpanded': shouldExpand,
          },
        ));
      }

      final files = entities.where((e) => !e.path.startsWith('.') && _isMediaFile(e.path));
      for (var file in files) {
        nodes.add(Node<dynamic>(
          key: file.path,
          label: p.basename(file.path),
          data: {'isFile': true},
        ));
      }

      nodes.sort((a, b) {
        final aIsFolder = a.children != null;
        final bIsFolder = b.children != null;
        if (aIsFolder && !bIsFolder) return -1;
        if (!aIsFolder && bIsFolder) return 1;
        return a.label.compareTo(b.label);
      });

    } catch (e) {
      debugPrint('Error building tree: ${directory.path} - $e');
    }

    return nodes;
  }




  Future<List<Node>> _loadFolderContents(String path) async {
    final dir = Directory(path);
    final List<Node> children = [];
        final mediaFiles = <FileSystemEntity>[];

    try {
      final entities = dir.listSync();

      if (entities.isEmpty) {
        Fluttertoast.showToast(msg: "folderIsEmpty".tr);
        return []; // prevents expansion and down-arrow
      }


      for (final entity in entities) {
        final entityPath = entity.path;


        if (mediaFiles.isNotEmpty) {
          children.add(Node(
            key: '$entityPath/__loading__',
            label: 'Loading...',
            data: {'isLoading': true},
          ));
        }



        if (entity is Directory) {
          children.add(Node(
            key: entityPath,
            label: entityPath.split('/').last,
            children: [],
            expanded: false,
            data: {'loaded': false},
          ));
        } else if (_isMediaFile(entityPath)) {
          children.add(Node(
            key: entityPath,
            label: entityPath.split('/').last,
            data: {'isFile': true},
          ));
        }
      }

      if (children.isEmpty) {
        Fluttertoast.showToast(msg: "folderIsEmpty".tr);
      }

    } catch (e) {
      print('❌ Error loading contents for $path: $e');
      Fluttertoast.showToast(msg: "failedToReadFolder".tr);
    }

    return children;
  }

  Future<void> handleExternalFileRename(String oldPath, String newPath) async {
    final parentPath = p.dirname(oldPath);

    setState(() {
      _treeViewController = _treeViewController!.copyWith(
        children: _updateNodeForRename(
          _treeViewController!.children,
          oldPath,
          newPath,
        ),
      );

      _treeKey = UniqueKey();
    });
  }

  List<Node> _updateNodeForRename(
      List<Node> nodes,
      String oldPath,
      String newPath,
      ) {
    return nodes.map((node) {
      if (node.key == oldPath) {
        return node.copyWith(
          key: newPath,
          label: p.basename(newPath),
        );
      } else if (node.children.isNotEmpty) {
        return node.copyWith(
          children: _updateNodeForRename(
            node.children,
            oldPath,
            newPath,
          ),
        );
      }
      return node;
    }).toList();
  }



  Widget _nodeBuilder(BuildContext context, Node node) {
    final isFolder = Directory(node.key).existsSync();
    final data = node.data;

    if (node.data is Map && (node.data as Map)['isLoading'] == true) {
      return Padding(
        padding: const EdgeInsets.only(left: 36.0),
        child: Row(
          children: const [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text("Loading..."),
          ],
        ),
      );
    }

    final isFile = data is Map && data['isFile'] == true;
    final isSelected = _isMultiSelectMode
        ? (isFile && _selectedFilePaths.contains(node.key)) ||
        (!isFile && _selectedFolderPaths.contains(node.key))
        : _treeViewController!.selectedKey == node.key;


    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (_doubleTapDetected) return;

          if (_isMultiSelectMode) {
            setState(() {
              if (isFile) {
                if (_selectedFilePaths.contains(node.key)) {
                  _selectedFilePaths.remove(node.key);
                } else {
                  _selectedFilePaths.add(node.key);
                }
              } else {
                if (_selectedFolderPaths.contains(node.key)) {
                  _selectedFolderPaths.remove(node.key);
                } else {
                  _selectedFolderPaths.add(node.key);
                }
              }

              _treeViewController = _treeViewController!.copyWith(
                children: List<Node>.from(_treeViewController!.children),
                selectedKey: null,
              );
            });
          }

          else {
            if (isFile) {
              setState(() {
                _treeViewController =
                    _treeViewController!.copyWith(selectedKey: node.key);
              });

              FileUtils.showPopupMenu(
                context,
                File(node.key),
                camera,
                null,
                onFileChanged: () => _reloadFileParent(node.key),
                onFilesMoved: () => _initializeTree(folderPathNotifier.value),
                onEnterMultiSelectMode: () {
                  setState(() {
                    _isMultiSelectMode = true;
                    _selectedFilePaths.add(node.key);
                    _treeViewController =
                        _treeViewController!.copyWith(selectedKey: node.key);
                  });
                },
              );
            } else {
              _handleNodeTap(node.key);
              setState(() {
                selectedFolderPathNotifier.value = node.key;
                _treeViewController =
                    _treeViewController!.copyWith(selectedKey: node.key);
              });
            }
          }
        });
      },

      onDoubleTap: () {
        _doubleTapDetected = true;
        _handleNodeDoubleTap(node);
        Future.delayed(const Duration(milliseconds: 300), () {
          _doubleTapDetected = false;
        });
      },
      onLongPress: () {
        if (isFolder) _showFolderOptions(node.key, node);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueGrey.shade400 : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            if (isFolder)
              Icon(
                node.expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                size: 24,
                color: Colors.grey,
              )
            else
              const SizedBox(width: 24),
            const SizedBox(width: 4),
            Icon(
              isFolder ? Icons.folder : Icons.insert_drive_file,
              color: isFolder ? Colors.amber : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    node.label.length > 22 ? '${node.label.substring(0, 22)}...' : node.label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (!isFolder)
                    ValueListenableBuilder<Map<String, String>>(
                      valueListenable: mediaNotesNotifier,
                      builder: (context, mediaNotes, _) {
                        final hasNote = mediaNotes.containsKey(node.key);
                        return hasNote
                            ? IconButton(
                          icon: const Icon(Icons.article, color: Colors.orange),
                          onPressed: () => showNoteDialog(context, node.key),
                        )
                            : const SizedBox.shrink();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }




  Future<void> _handleNodeDoubleTap(Node node) async {
    final isFile = node.data is Map && node.data['isFile'] == true;
    // showDialog(
    //   context: context,
    //   barrierDismissible: false,
    //   builder: (context) => Center(
    //     child: CircularProgressIndicator(),
    //   ),
    // );
    if (isFile) {
      final file = File(node.key);
      final parentDir = file.parent;
      final mediaFiles = parentDir
          .listSync()
          .whereType<File>()
          .where((f) => _isMediaFile(f.path) && !p.basename(f.path).startsWith('.'))
          .toList();
      // Navigator.pop(context);
      final index = mediaFiles.indexWhere((f) => f.path == file.path);


      if (index != -1) {
        // Navigator.push(
        //   context,
        //   MaterialPageRoute(
        //     builder: (_) => FullScreenMediaViewer(
        //       mediaFiles: mediaFiles,
        //       initialIndex: index,
        //       camera: camera,
        //     ),
        //   ),
        // ).then((_) async {
        // Navigate and wait for result
        final result = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(
            builder: (_) => FullScreenMediaViewer(
              mediaFiles: mediaFiles,
              initialIndex: index,
              camera: camera,
            ),
          ),
        );

        // Handle the result when coming back
        if (result != null) {
          final hasChanges = result['hasChanges'] as bool? ?? false;
          final renamedFiles = result['renamedFiles'] as Map<String, String>? ?? {};
          final folderContentChanged = result['folderContentChanged'] as bool? ?? false;
          final duplicatedFiles = result['duplicatedFiles'] as List? ?? [];

          if (hasChanges && renamedFiles.isNotEmpty) {
            for (final entry in renamedFiles.entries) {
              await handleExternalFileRename(entry.key, entry.value);
            }
          }
            if ( hasChanges && folderContentChanged) {
              await _reloadFileParent(file.path);
            }

          if ( duplicatedFiles.isNotEmpty) {
            if (duplicatedFiles.isNotEmpty) {
              print("🔄 Reloading folder due to duplicated files: $duplicatedFiles");

              await Future.delayed(Duration(milliseconds: 100));
              await _forceReloadFolderWithDuplicates(file.path, duplicatedFiles);
            } else {
              await _reloadFileParent(file.path);
            }
          }

        }

        _loadNotesAsync();

      }
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FolderMediaViewer(folderPath: node.key, camera: camera),
        ),
      );
    }
  }
  void _loadNotesAsync() {
    Future(() async {
      try {
        await NoteUtils.loadAllNotes("/storage/emulated/0");
        if (mounted) {
          setState(() {
            // triggers rebuild, so notes icon appears again
          });
        }
      } catch (e) {
        print('Error loading notes: $e');
      }
    });
  }

  Future<void> _forceReloadFolderWithDuplicates(String filePath, List<dynamic> duplicatedFiles) async {
    final parentPath = p.dirname(filePath);
    if (!mounted) return;

    print("🔄 Force reloading folder: $parentPath for duplicates");


    loadedFolders.remove(parentPath);

    await Future.delayed(Duration(milliseconds: 200));

    try {

      final updatedChildren = await _loadFolderContents(parentPath);

      if (!mounted) return;

      setState(() {
        _treeViewController = _treeViewController!.copyWith(
          children: _updateNodeChildren(
            _treeViewController!.children,
            parentPath,
            updatedChildren,
            isLoaded: true,
            forceExpand: true,
          ),
        );

        _treeKey = UniqueKey();
      });

      print("✅ Folder reloaded successfully, found ${updatedChildren.length} items");
    } catch (e) {
      print("❌ Error force reloading folder: $e");
      // Fallback to regular reload
      await _reloadFileParent(filePath);
    }
  }

  // void _handleNodeDoubleTap(Node node) {
  //   final isFile = node.data is Map && node.data['isFile'] == true;
  //
  //   if (isFile) {
  //     final file = File(node.key);
  //     final parentDir = file.parent;
  //     final mediaFiles = parentDir
  //         .listSync()
  //         .whereType<File>()
  //         .where((f) => _isMediaFile(f.path) && !p.basename(f.path).startsWith('.'))
  //         .toList();
  //     final index = mediaFiles.indexWhere((f) => f.path == file.path);
  //
  //     if (index != -1) {
  //       Navigator.push(
  //         context,
  //         MaterialPageRoute(
  //           builder: (_) => FullScreenMediaViewer(
  //             mediaFiles: mediaFiles,
  //             initialIndex: index,
  //             camera: camera,
  //           ),
  //         ),
  //       );
  //     }
  //   } else {
  //     Navigator.push(
  //       context,
  //       MaterialPageRoute(
  //         builder: (_) => FolderMediaViewer(folderPath: node.key, camera: camera),
  //       ),
  //     );
  //   }
  // }



  bool _isMediaFile(String path) {
    return path.endsWith(".jpg") ||
        path.endsWith(".jpeg") ||
        path.endsWith(".png") ||
        path.endsWith(".mp4") ||
        path.endsWith(".mov");
  }


  List<Node> _updateNodeChildren(
      List<Node> nodes,
      String parentKey,
      List<Node> newChildren, {
        bool isLoaded = false,
        bool forceExpand = false,
      }) {
    return nodes.map((node) {
      if (node.key == parentKey) {
        final shouldExpand = forceExpand || newChildren.isNotEmpty;
        print("🔵 inserting loading node for ${node.key}");

        return node.copyWith(
          children: [...newChildren],
          expanded: shouldExpand,
          data: {
            ...(node.data is Map ? node.data as Map : {}),
            'loaded': isLoaded,
          },
        );
      } else if (node.children.isNotEmpty) {
        return node.copyWith(
          children: _updateNodeChildren(
            node.children,
            parentKey,
            newChildren,
            isLoaded: isLoaded,
            forceExpand: forceExpand,
          ),
        );
      }
      return node;
    }).toList();
  }




  Future<void> _handleNodeTap(String key, {bool isDoubleTap = false}) async {
    print('🟢 Node tapped: $key');
    selectedFolderPathNotifier.value = key;

    final tappedNode = _findNode(_treeViewController!.children, key);
    if (tappedNode == null) return;

    final isFolder = Directory(key).existsSync();
    final data = tappedNode.data;
    if (_isMoveMode && isFolder) {
      if (isFolder) {
        await _expandFolderForMove(key);

        _confirmAndMove(key);

      }
      return;
    }
    if (_isMultiSelectMode && isAwaitingMultiFileMove && isFolder) {
      await _expandFolderForMove(key);

      ProgressDialog.show(context, _selectedFilePaths.length);

      try {
        int completed = 0;
        for (final path in _selectedFilePaths.toList()) {
          await FileUtils.moveFileTo(context, File(path), key);

          completed++;
          ProgressDialog.updateProgress(completed, _selectedFilePaths.length);
        }


        mediaReloadNotifier.value++;

      } catch (e) {
        Fluttertoast.showToast(msg: "Error moving files: ${e.toString()}".tr);
      } finally {
        ProgressDialog.dismiss();
        mediaReloadNotifier.value++;
        setState(() {
          isAwaitingMultiFileMove = false;
        });

        _exitMultiSelectMode();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => FileManager(
              selectedPaths: [],
              enableFolderSelection: false,
            ),
          ),
        );
        setState(() {});
        return;
      }
    }

    if (widget.enableFolderSelection && isFolder) {
      if (widget.onFolderSelected != null) {
        widget.onFolderSelected!(key);
      } else {
        Navigator.of(context).pop(widget.isDestinationSelection ? true : key);
      }
      return;
    }

    if (isDoubleTap && isFolder) {
      _openFolderMediaViewer(key);
      return;
    }

    final isCurrentlyExpanded = expandedFolders.contains(key);


    if (isCurrentlyExpanded) {


      setState(() {
        expandedFolders.remove(key);
        _treeViewController = _treeViewController!.copyWith(
          children: _toggleNodeExpansion(_treeViewController!.children, key),
          selectedKey: key,
        );
      });
      await saveExpandedFolders(expandedFolders);
      return;
    }


    double? scrollOffset;
    if (_scrollController.hasClients) {
      scrollOffset = _scrollController.offset;
    }


    final loadingNode = Node(
      key: '$key/__loading__',
      label: 'Loading...',
      data: {'isLoading': true},
    );
    _treeKey = UniqueKey();
    _handleExpansionToggle(key);


    await Future.delayed(const Duration(milliseconds: 20));
    if (_scrollController.hasClients && scrollOffset != null) {
      _scrollController.jumpTo(scrollOffset);
    }

    final children = await _loadFolderContents(key);

    if (widget.showCancelBtn) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('selectedFolder $key'.tr),
          duration: const Duration(days: 1),
          action: SnackBarAction(
            label: 'ok'.tr,
            onPressed: () => _onOkPressed(key),
          ),
        ),
      );
    }

    if (children.isEmpty) {
      setState(() {
        _treeViewController = _treeViewController!.copyWith(
          children: _updateNodeChildren(
            _treeViewController!.children,
            key,
            [],
            isLoaded: true,
            forceExpand: false,
          ),
          selectedKey: key,
        );
      });
      expandedFolders.remove(key);
      await saveExpandedFolders(expandedFolders);

      return;
    }


    setState(() {
      _treeViewController = _treeViewController!.copyWith(
        children: _updateNodeChildren(
          _treeViewController!.children,
          key,
          children,
          isLoaded: true,
          forceExpand: true,
        ),
        selectedKey: key,
      );
    });


    await Future.delayed(const Duration(milliseconds: 10));
    if (_scrollController.hasClients && scrollOffset != null) {
      _scrollController.jumpTo(scrollOffset);
    }
  }

  Future<void> _expandFolderForMove(String path) async {
    if (expandedFolders.contains(path)) return;


    setState(() {
      _treeViewController = _treeViewController!.copyWith(
          children: _updateNodeChildren(
          _treeViewController!.children,
          path,
          [Node(key: '$path/__loading__', label: 'Loading...')],
      isLoaded: false,
      forceExpand: true,
      ));
    });


    final children = await _loadFolderContents(path);

    setState(() {
      _treeViewController = _treeViewController!.copyWith(
        children: _updateNodeChildren(
          _treeViewController!.children,
          path,
          children,
          isLoaded: true,
          forceExpand: true,
        ),
      );
    });
    await saveExpandedFolders(expandedFolders);

  }




  void _onOkPressed(String? key) {
    _okPressed = true;

    final chosenPath = key ?? defaultFolderPath;

    if (widget.updateFolderPath) {
      folderPathNotifier.value = chosenPath;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    Navigator.pop(context, chosenPath);

    selectedFolderPathNotifier.value = null;

    Fluttertoast.showToast(
      msg: 'storingAt $chosenPath'.tr,
      toastLength: Toast.LENGTH_SHORT,
    );
  }

  void _handleSnackBarOnBack() {
    if (!_okPressed && widget.showCancelBtn) {

      _onOkPressed(defaultFolderPath);
    }
  }



  void _openFolderMediaViewer(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FolderMediaViewer(folderPath: path, camera: camera),
      ),
    );
  }


  Node? _findNode(List<Node> nodes, String key) {
    for (final node in nodes) {
      if (node.key == key) return node;
      if (node.children.isNotEmpty) {
        final found = _findNode(node.children, key);
        if (found != null) return found;
      }
    }
    return null;
  }


  loadFileStructure(String path) async {
    setState(() {
      isLoading = true;
    });
    Directory rootDir = Directory(path);
    List<Node> nodes = await _buildFileTree(rootDir);

    setState(() {
      _treeViewController = TreeViewController(
        children: nodes,
        selectedKey: path,
      );
      isLoading = false;
    });
  }



  void _showFolderOptions(String folderPath, Node node) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.add),
            title: Text("newFolder".tr),
            onTap: () async {
              Navigator.pop(context);
              final newPath = await _createNewFolder(folderPath);
              if (newPath != null) {
                await IndexManager.instance.updateForNewFolder(newPath);
              }
            },
          ),

          ListTile(
            leading: Icon(Icons.add),
            title: Text("open".tr),
            onTap: () async {
              Navigator.pop(context);
              _handleNodeDoubleTap(node);             },
          ),
          ListTile(
            leading: Icon(Icons.edit),
            title: Text("rename".tr),
              onTap: () async {
                Navigator.pop(context);
                final newPath =  await _renameFolder(folderPath);
                if (newPath != null && newPath != folderPath) {
                  await IndexManager.instance.updateForFolderRename(folderPath, newPath);
                }
              }

          ),
          ListTile(
            leading: Icon(Icons.select_all_sharp),
            title: Text('select'.tr),
            onTap: () async {
              Navigator.pop(context);
              setState(() {
                _isMultiSelectMode = true;
                _selectedFolderPaths.add(folderPath);
                _treeViewController = _treeViewController!.copyWith(selectedKey: node.key);
              });
            },
          ),
          ListTile(
            leading: Icon(Icons.drive_file_move),
            title: Text("moveFolder".tr),
            onTap: () async {
              Navigator.pop(context);
              moveItem(folderPath);

            },
          ),
          ListTile(
            leading: Icon(Icons.delete),
            title: Text("suppress".tr),
            onTap: () async {
              Navigator.pop(context);
              final deleted = await _deleteFolder(folderPath);
              if (deleted) {
                await IndexManager.instance.updateForDelete(folderPath);
              }
            },
          ),
        ],
      ),
    );
  }



  Future<String?> _createNewFolder(String parentFolderPath) async {
    final TextEditingController _folderNameController = TextEditingController();

    final result = await showDialog<String>(
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
                  'createNewFolder'.tr,
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
          controller: _folderNameController,
          autofocus: true,
          decoration: InputDecoration(hintText: 'enterFolderName'.tr),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () {
              final folderName = _folderNameController.text.trim();
              if (folderName.isNotEmpty) {
                Navigator.pop(context, folderName);
              }
            },
            child: Text('createFolder'.tr),
          ),
        ],
      ),
    );

    if (result != null) {
      final newFolderPath = p.join(parentFolderPath, result);
      final newFolder = Directory(newFolderPath);

      if (!newFolder.existsSync()) {
        try {
          newFolder.createSync(recursive: true);
          loadedFolders.remove(parentFolderPath);


          List<Node> updatedChildren = await _loadFolderContents(parentFolderPath);
          List<Node> updatedNodes = _updateNodeChildren(
            _treeViewController!.children,
            parentFolderPath,
            updatedChildren,
            isLoaded: true,
          ).map((node) {
            return node.key == parentFolderPath
                ? node.copyWith(
              expanded: true,
              data: {'loaded': true},
            )
                : node;
          }).toList();

          setState(() {
            _treeViewController = _treeViewController!.copyWith(
              children: updatedNodes,
              selectedKey: _treeViewController?.selectedKey,
            );
          });

          Fluttertoast.showToast(msg: "Folder '$result' created");
          return newFolderPath;
        } catch (e) {
          Fluttertoast.showToast(msg: "Failed to create folder: $e");
        }
      } else {
        Fluttertoast.showToast(msg: "folderExists".tr);
      }
    }

    return null;
  }




  Future<void> _suppressSelectedFiles() async {
    if (_selectedFilePaths.isEmpty) return;

    final confirmed = await _showBatchConfirmationDialog(
      context,
      title: "Delete ${_selectedFilePaths.length} files?".tr,
      message: "This action cannot be undone".tr,
      confirmText: "Delete All".tr,
    );

    if (!confirmed) return;

    ProgressDialog.show(context, _selectedFilePaths.length);

    try {
      int completed = 0;
      for (final path in _selectedFilePaths.toList()) {
        await FileUtils.deleteFile(context, File(path));
        completed++;
        ProgressDialog.updateProgress(completed, _selectedFilePaths.length);
      }


      mediaReloadNotifier.value++;

    } catch (e) {
      Fluttertoast.showToast(msg: "Error deleting files".tr);
    } finally {
      ProgressDialog.dismiss();
      mediaReloadNotifier.value++;
      _exitMultiSelectMode();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => FileManager(
            selectedPaths: [],
            enableFolderSelection: false,
          ),
        ),
      );
      setState(() {});
    }
  }


  Future<void> _duplicateSelectedFiles() async {
    if (_selectedFilePaths.isEmpty) return;

    final confirmed = await _showBatchConfirmationDialog(
      context,
      title: "Duplicate ${_selectedFilePaths.length} files?".tr,
      message: "duplicateWarning".tr,
      confirmText: "duplicateAll".tr,
    );

    if (!confirmed) return;

    ProgressDialog.show(context, _selectedFilePaths.length);

    try {
      int completed = 0;
      for (final path in _selectedFilePaths.toList()) {
        await FileUtils.duplicateFile(context, File(path));
        completed++;
        ProgressDialog.updateProgress(completed, _selectedFilePaths.length);
      }


      mediaReloadNotifier.value++;

    } catch (e) {
      Fluttertoast.showToast(msg: "Error duplicating files".tr);
    } finally {
      ProgressDialog.dismiss();
      mediaReloadNotifier.value++;

      _exitMultiSelectMode();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => FileManager(
            selectedPaths: [],
            enableFolderSelection: false,
          ),
        ),
      );
      setState(() {});
    }
  }


  Future<void> _moveSelectedFiles() async {
    if (_selectedFilePaths.isEmpty) return;

    Fluttertoast.showToast(
      msg: "Tap a folder to move ${_selectedFilePaths.length} files".tr,
      toastLength: Toast.LENGTH_LONG,
    );

    setState(() {
      isAwaitingMultiFileMove = true;
    });

  }


  Future<void> _duplicateFolder(String folderPath) async {
    try {
      final src = Directory(folderPath);
      if (!src.existsSync()) {
        Fluttertoast.showToast(msg: "folderNotFound".tr);
        return;
      }

      final parentPath = src.parent.path;
      final baseName = p.basename(folderPath);

      String candidateName = baseName;
      String newPath = p.join(parentPath, candidateName);
      int copyIndex = 1;

      while (Directory(newPath).existsSync()) {
        candidateName = '$baseName ($copyIndex)';
        newPath = p.join(parentPath, candidateName);
        copyIndex++;
      }

      await Directory(newPath).create(recursive: true);

      await for (final entity in src.list(recursive: true, followLinks: false)) {
        final relative = p.relative(entity.path, from: src.path);
        final destPath = p.join(newPath, relative);

        if (entity is File) {
          final destDir = Directory(p.dirname(destPath));
          if (!destDir.existsSync()) {
            destDir.createSync(recursive: true);
          }
          await entity.copy(destPath);
        } else if (entity is Directory) {
          final d = Directory(destPath);
          if (!d.existsSync()) {
            d.createSync(recursive: true);
          }
        }
      }

      loadedFolders.remove(parentPath);
      final updatedChildren = await _loadFolderContents(parentPath);
      final updatedNodes = _updateNodeChildren(
        _treeViewController!.children,
        parentPath,
        updatedChildren,
        isLoaded: true,
      ).map((node) {
        return node.key == parentPath
            ? node.copyWith(expanded: true, data: {'loaded': true})
            : node;
      }).toList();

      setState(() {
        _treeViewController =
            _treeViewController!.copyWith(children: updatedNodes, selectedKey: _treeViewController?.selectedKey);
      });

      try {
        await IndexManager.instance.updateForNewFolder(newPath);
      } catch (_) {}

      try {
        mediaReloadNotifier.value++;
      } catch (_) {}

      Fluttertoast.showToast(msg: "folderDuplicated".trArgs([baseName]));
    } catch (e) {
      Fluttertoast.showToast(msg: "folderDuplicateFailed".tr + ": $e");
    }
  }


  Future<void> _suppressSelectedItems() async {
    final fileCount = _selectedFilePaths.length;
    final folderCount = _selectedFolderPaths.length;
    final total = fileCount + folderCount;
    if (total == 0) return;

    final confirmed = await _showBatchConfirmationDialog(
      context,
      title: "Delete $total items?".tr,
      message: "This action cannot be undone".tr,
      confirmText: "Delete All".tr,
    );
    if (!confirmed) return;

    ProgressDialog.show(context, total);
    try {
      int completed = 0;

      for (final path in _selectedFilePaths.toList()) {
        await FileUtils.deleteFile(context, File(path));
        completed++;
        ProgressDialog.updateProgress(completed, total);
      }

      for (final folderPath in _selectedFolderPaths.toList()) {
        await _deleteFolder(folderPath);
        completed++;
        ProgressDialog.updateProgress(completed, total);
      }

      mediaReloadNotifier.value++;
    } catch (e) {
      Fluttertoast.showToast(msg: "Error deleting items".tr + ": $e");
    } finally {
      ProgressDialog.dismiss();
      mediaReloadNotifier.value++;

      _exitMultiSelectMode();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => FileManager(
            selectedPaths: [],
            enableFolderSelection: false,
          ),
        ),
      );
      setState(() {});
    }
  }

  Future<void> _duplicateSelectedItems() async {
    final fileCount = _selectedFilePaths.length;
    final folderCount = _selectedFolderPaths.length;
    final total = fileCount + folderCount;
    if (total == 0) return;

    final confirmed = await _showBatchConfirmationDialog(
      context,
      title: "Duplicate $total items?".tr,
      message: "duplicateWarning".tr,
      confirmText: "duplicateAll".tr,
    );
    if (!confirmed) return;

    ProgressDialog.show(context, total);
    try {
      int completed = 0;

      for (final path in _selectedFilePaths.toList()) {
        await FileUtils.duplicateFile(context, File(path));
        completed++;
        ProgressDialog.updateProgress(completed, total);
      }

      for (final folderPath in _selectedFolderPaths.toList()) {
        await _duplicateFolder(folderPath);
        completed++;
        ProgressDialog.updateProgress(completed, total);
      }

      mediaReloadNotifier.value++;
    } catch (e) {
      Fluttertoast.showToast(msg: "Error duplicating items".tr + ": $e");
    } finally {
      ProgressDialog.dismiss();
      mediaReloadNotifier.value++;

      _exitMultiSelectMode();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => FileManager(
            selectedPaths: [],
            enableFolderSelection: false,
          ),
        ),
      );
      setState(() {});
    }
  }

  Future<void> _moveSelectedItems() async {
    final fileCount = _selectedFilePaths.length;
    final folderCount = _selectedFolderPaths.length;
    final total = fileCount + folderCount;
    if (total == 0) return;

    setState(() {
      _isMoveMode = true;
      _selectedForMove = [
        ..._selectedFilePaths,
        ..._selectedFolderPaths,
      ];
      isAwaitingMultiFileMove = _selectedFilePaths.isNotEmpty;
      _isMultiSelectMode = false;
    });

    Fluttertoast.showToast(
      msg: "Tap a folder to move $total items".tr,
      toastLength: Toast.LENGTH_LONG,
    );
  }

  Future<bool> _showBatchConfirmationDialog(
      BuildContext context, {
        required String title,
        required String message,
        required String confirmText,
      }) async {
    return await showDialog<bool>(
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
                title,
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

        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("cancel".tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    ) ?? false;
  }



  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedFilePaths.clear();
      _selectedFolderPaths.clear();

      isAwaitingMultiFileMove = false;

    });
  }


  Future<void> saveExpandedFolders(List<String> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('expandedFolders', folders);
  }




  Future<String?> _renameFolder(String folderPath) async {
    final parentDir = Directory(folderPath).parent.path;
    final oldName = p.basename(folderPath);

    final controller = TextEditingController(text: oldName);

    final newPath = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),

          titlePadding: EdgeInsetsGeometry.zero,
          title: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('renameFolder'.tr,
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
            decoration: InputDecoration(hintText: "newFolderName".tr),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('cancel'.tr),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                moveItem(folderPath);
              },
              child: Text('move'.tr),
            ),
            TextButton(
              onPressed: () {
                final newName = controller.text.trim();
                if (newName.isNotEmpty && newName != oldName) {
                  final renamedPath = '$parentDir/$newName';
                  try {
                    Directory(folderPath).renameSync(renamedPath);
                    Fluttertoast.showToast(msg: "folderRenameSuccess".tr);
                    Navigator.pop(context, renamedPath);
                  } catch (e) {
                    Fluttertoast.showToast(msg: "renameFailed".tr);
                    Navigator.pop(context); // just close
                  }
                }
              },
              child: Text('rename'.tr),
            ),
          ],
        );
      },
    );

    if (newPath != null && newPath != folderPath) {

      loadedFolders.remove(parentDir);

      final updatedChildren = await _loadFolderContents(parentDir);
      final updatedNodes = _updateNodeChildren(
        _treeViewController!.children,
        parentDir,
        updatedChildren,
        isLoaded: true,
      ).map((node) {
        return node.key == parentDir
            ? node.copyWith(expanded: true, data: {'loaded': true})
            : node;
      }).toList();

      setState(() {
        _treeViewController = _treeViewController!.copyWith(
          children: updatedNodes,
          selectedKey: _treeViewController?.selectedKey,
        );
      });
    }

    return newPath;
  }



  Future<bool> _deleteFolder(String folderPath) async {
    final deletedFolderName = p.basename(folderPath);
    final parentPath = Directory(folderPath).parent.path;

    try {
      final normalizedPath = p.normalize(folderPath);

      final folder = Directory(normalizedPath);
      if (!folder.existsSync()) {
        Fluttertoast.showToast(msg: "folderNotFound".tr);
        return false;
      }

      folder.deleteSync(recursive: true);

      loadedFolders.remove(parentPath);

      final updatedChildren = await _loadFolderContents(parentPath);

      final updatedNodes = _updateNodeChildren(
        _treeViewController!.children,
        parentPath,
        updatedChildren,
        isLoaded: true,
      ).map((node) {
        return node.key == parentPath
            ? node.copyWith(expanded: true, data: {'loaded': true})
            : node;
      }).toList();

      setState(() {
        _treeViewController = _treeViewController!.copyWith(
          children: updatedNodes,
          selectedKey: _treeViewController?.selectedKey,
        );
      });

      IndexManager.instance.removeByPathPrefix(normalizedPath);

      Fluttertoast.showToast(msg: "folderDeleteSuccess".tr);
      return true;
    } catch (e) {
      Fluttertoast.showToast(msg: "folderDeleteFailed".tr + ": $e");
      return false;
    }
  }




  Future<void> requestStoragePermission() async {
    if (!Platform.isAndroid) return;

    if (await Permission.manageExternalStorage.isGranted ||
        await Permission.storage.isGranted) {
      print("✅ Storage permission already granted.");
      loadFileStructure(folderPathNotifier.value);

      return;
    }

    if (await Permission.manageExternalStorage.isDenied ||
        await Permission.manageExternalStorage.isRestricted) {
      final status = await Permission.manageExternalStorage.request();
      if (status.isGranted) {
        print("✅ Manage External Storage granted.");
        loadFileStructure(folderPathNotifier.value);

        return;
      } else if (status.isPermanentlyDenied) {
        print("⚠️ Permission permanently denied.");

        await openAppSettings();
        return;
      }
    }

    final fallbackStatus = await Permission.storage.request();
    if (fallbackStatus.isGranted) {
      print("✅ Storage permission granted.");
      loadFileStructure(folderPathNotifier.value);
    } else {
      print("❌ Storage permission denied.");
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_treeViewController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    print('TreeView children: ${_treeViewController!.children}');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mediaNotesNotifier.value.isEmpty) {
        loadNotesFromFolder(folderPathNotifier.value);
      }
    });

    return WillPopScope(
      onWillPop: () async {
        if (_isMoveMode) {
          _cancelMoveMode();
          return false;
        }
        _handleSnackBarOnBack();

        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          shadowColor: Colors.grey,
          title: _isSearching
              ? TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'searchPlaceholder'.tr,
              border: InputBorder.none,
              hintStyle: TextStyle(color: Colors.black54),
            ),
            style: TextStyle(color: Colors.black),
            onChanged: (value) => _searchQuery.value = value.toLowerCase(),
          )
              : Text('fileManager'.tr),

            actions: [
              ValueListenableBuilder<bool>(
                valueListenable: isIndexing,
                builder: (context, indexing, _) {
                  return  IconButton(
                    icon: Icon(_isSearching ? Icons.close : Icons.search),
                    onPressed: () {
                      setState(() {
                        _isSearching = !_isSearching;
                        if (!_isSearching) {
                          _searchController.clear();
                          _searchQuery.value = '';
                        }
                      });
                    },
                  );
                },
              ),
            ]


        ),

        bottomNavigationBar: _isMultiSelectMode
            ? BottomAppBar(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Delete (suppress)
              TextButton.icon(
                onPressed: (_selectedFilePaths.isEmpty && _selectedFolderPaths.isEmpty)
                    ? null
                    : _suppressSelectedItems,
                icon: const Icon(Icons.delete),
                label: Text("suppress".tr),
              ),

              // Move
              TextButton.icon(
                onPressed: (_selectedFilePaths.isEmpty && _selectedFolderPaths.isEmpty)
                    ? null
                    : _moveSelectedItems,
                icon: const Icon(Icons.drive_file_move),
                label: Text("move".tr),
              ),

              TextButton.icon(
                onPressed: (_selectedFilePaths.isEmpty && _selectedFolderPaths.isEmpty)
                    ? null
                    : _duplicateSelectedItems,
                icon: const Icon(Icons.copy),
                label: Text("duplicate".tr),
              ),

              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitMultiSelectMode,
              ),
            ],
          ),
        )
            : null,




        backgroundColor: Colors.white,
        body: isLoading || _treeViewController == null
            ? Center(child: CircularProgressIndicator())
            : ValueListenableBuilder<String>(
            valueListenable: _searchQuery,
            builder: (context, query, _) {
              final nodesToDisplay = query.isEmpty
                  ? _treeViewController?.children
                  : _filteredNodes;

              if (_searchInProgress) {
                return Center(child: CircularProgressIndicator());
              }


              return Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.vertical,

                      child: TreeView(

                        key: _treeKey,
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,

                        controller: _treeViewController!.copyWith(
                          children: nodesToDisplay,
                        ),
                        allowParentSelect: true,
                        theme: TreeViewTheme(
                          expanderTheme: ExpanderThemeData(
                            type: ExpanderType.none,
                            modifier: ExpanderModifier.none,
                            position: ExpanderPosition.start,
                            size: 20,
                            color: Colors.blueGrey.shade400,
                          ),
                          labelStyle: TextStyle(fontSize: 16),
                          parentLabelStyle:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          colorScheme: ColorScheme.light().copyWith(
                            primary: Colors.blueGrey.shade400,
                          ),
                        ),




                        onNodeTap: (key) {
                          if (_isMultiSelectMode) return;

                          final node = _findNode(_treeViewController!.children, key);
                          if (node != null) {
                            if (_isMoveMode) {
                              print("move mode enabled");
                              final isFolder = Directory(key).existsSync();
                              if (isFolder) {
                                _showDestinationConfirmation(key);
                              } else {
                                Fluttertoast.showToast(msg: "Please select a folder".tr);
                              }
                            } else {
                              _handleNodeTap(node.key);
                              setState(() {
                                selectedFolderPathNotifier.value = node.key;
                                _treeViewController = _treeViewController!.copyWith(selectedKey: node.key);
                              });
                            }
                          }
                        }




                        ,
                          onNodeDoubleTap: (key) {
                          final node = _findNode(_treeViewController!.children, key);
                          if (node != null) _handleNodeDoubleTap(node);
                        },

                        nodeBuilder: (context, node) =>


                            _nodeBuilder(context, node),

                      ),
                    ),
                  ),
                ],
              );
            }),)
    );
  }


  Future<void> _performMoveToDestination(String destinationPath) async {
    if (_selectedForMove.isEmpty || !mounted) return;

    setState(() => isLoading = true);

    try {
      // Store parent paths that need refreshing
      final pathsToRefresh = _selectedForMove.map((p) => p.split('/').sublist(0, p.split('/').length-1).join('/')).toSet();
      pathsToRefresh.add(destinationPath);


      for (var path in _selectedForMove) {
        try {
          final isDir = Directory(path).existsSync();
          final dest = isDir
              ? Directory('$destinationPath/${p.basename(path)}')
              : File('$destinationPath/${p.basename(path)}');

          if (isDir) {
            await _moveDirectory(Directory(path), dest as Directory);
          } else {
            await FileUtils.moveFileTo(context, File(path), destinationPath);
          }
        } catch (e) {
          debugPrint('Move error for $path: $e');
        }
      }


      await Future.delayed(Duration(milliseconds: 500));


      for (var path in pathsToRefresh) {
        if (Directory(path).existsSync()) {
          await refreshTreeView(targetPath: path);
        }
      }

      Fluttertoast.showToast(msg: "moveCompleted".tr);
    } catch (e) {
      debugPrint('Move operation failed: $e');
      Fluttertoast.showToast(msg: "Move failed".tr);
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          _isMoveMode = false;
          _selectedForMove.clear();
        });
      }
    }
  }



  void _showDestinationConfirmation(String destinationPath) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Moving to: $destinationPath'),
        duration: Duration(days: 1),
        action: SnackBarAction(
          label: 'ok'.tr,
          onPressed: () async {
            await _performMoveToDestination(destinationPath);
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );

    // Show toast to guide user
    Fluttertoast.showToast(
      msg: "tapToConfirmOrSelectAnother".tr,
      toastLength: Toast.LENGTH_LONG,
    );
  }



  Future<void> loadNotesFromFolder(String folderPath) async {
    final Map<String, String> notes = {};

    void collectNotes(Directory dir) {
      try {
        final entries = dir.listSync();

        for (final entity in entries) {
          if (entity is File && entity.path.endsWith('.txt')) {
            try {
              final noteContent = entity.readAsStringSync();
              final imagePath = entity.path.replaceAll(RegExp(r'\.txt$'), '.jpg');
              notes[imagePath] = noteContent;
            } catch (e) {
              debugPrint("[ERROR] Failed to read note: ${entity.path}");
            }
          } else if (entity is Directory) {
            collectNotes(entity);
          }
        }
      } catch (e) {
        debugPrint("🚫 Skipping inaccessible folder: ${dir.path}");
      }
    }

    collectNotes(Directory(folderPath));

    mediaNotesNotifier.value = notes;
    debugPrint("[DEBUG] Loaded ${notes.length} notes recursively.");
  }



  void showNoteDialog(BuildContext context, String imagePath) {
    final note = mediaNotesNotifier.value[imagePath] ?? "noNoteFound".tr;

    showDialog(
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
                  "note".tr,
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

        content: Text(note),
        actions: [


          TextButton(
            onPressed: () {
              mediaNotesNotifier.value = {...mediaNotesNotifier.value}
                ..remove(imagePath);


              Fluttertoast.showToast(msg: "noteDeleteSuccess".tr);
              Navigator.pop(context);
            },
            child: Text("delete".tr, style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              NoteUtils.showNoteInputModal(
                context,
                imagePath,
                    (path, note) => NoteUtils.addOrUpdateNote(path, note, mediaNotesNotifier),
                initialText: note,
                isEditing: true,
              );

            },
            child: Text("edit".tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("ok".tr),
          ),
        ],
      ),
    );
  }


  List<Node> _toggleNodeExpansion(List<Node> nodes, String key) {
    return nodes.map((node) {
      if (node.key == key) {
        bool newState = !(node.expanded ?? false);
        return node.copyWith(expanded: newState);
      } else if (node.children.isNotEmpty) {
        return node.copyWith(
          children: _toggleNodeExpansion(node.children, key),
        );
      } else {
        return node;
      }
    }).toList();
  }

  void _handleExpansionToggle(String key) async {
    setState(() {
      if (expandedFolders.contains(key)) {
        expandedFolders.remove(key);
      } else {
        expandedFolders.add(key);
      }
      _treeViewController = _treeViewController!.copyWith(
        children: _toggleNodeExpansion(_treeViewController!.children, key),
      );
    });

    await saveExpandedFolders(expandedFolders);
  }


  Future<void> _reloadFileParent(String filePath) async {
    final parentPath = p.dirname(filePath);
    if (!mounted) return;

    loadedFolders.remove(parentPath);
    final updatedChildren = await _loadFolderContents(parentPath);

    setState(() {
      _treeViewController = _treeViewController!.copyWith(
        children: _updateNodeChildren(
          _treeViewController!.children,
          parentPath,
          updatedChildren,
          isLoaded: true,
        ),
      );
      _treeKey = UniqueKey();
    });

  }

}


class FolderMediaViewer extends StatefulWidget {
  final String folderPath;

  final CameraDescription camera;
  FolderMediaViewer({required this.folderPath, super.key, required this.camera});

  @override
  State<FolderMediaViewer> createState() => _FolderMediaViewerState();
}

class _FolderMediaViewerState extends State<FolderMediaViewer> {
  final TextEditingController _searchController = TextEditingController();

  final ValueNotifier<String> _searchQuery = ValueNotifier<String>('');
  bool _isMultiSelectMode = false;
  Set<String> _selectedFilePaths = {};
  File? _selectedFile;
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mediaNotesNotifier.value.isEmpty) {
        loadNotesFromFolder(widget.folderPath);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'searchByNameOrNote'.tr + p.basename(widget.folderPath),
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.black),
          ),
          style: TextStyle(color: Colors.black),
          onChanged: (value) => _searchQuery.value = value,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              _searchQuery.value = '';
            },
          ),
        ],
      ),

      bottomNavigationBar: _isMultiSelectMode
          ? BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            TextButton.icon(
              onPressed: _selectedFilePaths.isEmpty ? null : _suppressSelectedFiles,
              icon: Icon(Icons.delete),
              label: Text("suppress".tr),
            ),
            TextButton.icon(
              onPressed: _selectedFilePaths.isEmpty ? null : _moveSelectedFiles,
              icon: Icon(Icons.drive_file_move),
              label: Text("move".tr),
            ),
            TextButton.icon(
              onPressed: _selectedFilePaths.isEmpty ? null : _duplicateSelectedFiles,
              icon: Icon(Icons.copy),
              label: Text("duplicate".tr),
            ),
            IconButton(
              icon: Icon(Icons.close),
              onPressed: _exitMultiSelectMode,
            )
          ],
        ),
      )
          : null,



      body: ValueListenableBuilder<int>(
        valueListenable: mediaReloadNotifier,
        builder: (context, _, __) {
          return ValueListenableBuilder<String>(
            valueListenable: _searchQuery,
            builder: (context, query, _) {
              final mediaFiles = _getMediaFiles(filter: query);

              return ValueListenableBuilder<String>(
                valueListenable: fileAspectNotifier,
                builder: (context, aspect, _) {
                  debugPrint('Current file aspect: $aspect');

                  return KeyedSubtree(
                    key: ValueKey<String>(aspect),
                    child: aspect == "list"
                        ? _buildListView(mediaFiles, mediaNotesNotifier.value)
                        : _buildGridView(mediaFiles, mediaNotesNotifier.value, aspect),
                  );
                },
              );
            },
          );
        },
      ),

    );
  }

  List<File> _getMediaFiles({String? filter}) {
    final allFiles = Directory(widget.folderPath)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) =>
    file.path.endsWith(".jpg") ||
        file.path.endsWith(".jpeg") ||
        file.path.endsWith(".png") ||
        file.path.endsWith(".mp4"))
        .toList();

    if (filter == null || filter.isEmpty) return allFiles;

    final query = filter.toLowerCase();

    return allFiles.where((file) {
      final nameMatch = p.basename(file.path).toLowerCase().contains(query);
      final noteMatch = mediaNotesNotifier.value[file.path]
          ?.toLowerCase()
          .contains(query) ??
          false;
      return nameMatch || noteMatch;
    }).toList();
  }



  Widget _buildListView(List<File> mediaFiles, Map<String, String> mediaNotes) {
    return ListView.builder(
      key: PageStorageKey<String>('list_view'),
      itemCount: mediaFiles.length,
      itemBuilder: (context, index) {
        final file = mediaFiles[index];
        final isSelected = _isMultiSelectMode
            ? _selectedFilePaths.contains(file.path)
            : _selectedFile?.path == file.path;

        return GestureDetector(
          onDoubleTap: () => FileUtils.openFullScreen(context, file, mediaFiles),

          onTap: () {
            setState(() {
              if (_isMultiSelectMode) {
                if (_selectedFilePaths.contains(file.path)) {
                  _selectedFilePaths.remove(file.path);
                } else {
                  _selectedFilePaths.add(file.path);
                }
              } else {
                _selectedFile = file;
                FileUtils.showPopupMenu(
                  context,
                  file,
                  widget.camera,
                  null,
                  onEnterMultiSelectMode: () {
                    setState(() {
                      _isMultiSelectMode = true;
                      _selectedFilePaths.add(file.path);
                    });
                  },
                );
              }
            });
          },

          child: Container(

            decoration: BoxDecoration(
              color: isSelected ? Colors.blueGrey.shade400 : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),


            child: ListTile(
              leading: file.path.endsWith(".mp4")
                  ? Icon(Icons.videocam)
                  : Icon(Icons.image),
              title: Text(file.path.split('/').last),
              trailing: _hasNote(file.path, mediaNotes)
                  ? IconButton(
                icon: Icon(Icons.article, color: Colors.orange),
                onPressed: () => showNoteDialog(context, file.path),
              )
                  : null,
            ),
          ),
        );
      },
    );
  }



  Widget _buildGridView(List<File> mediaFiles, Map<String, String> mediaNotes, String aspect) {
    final crossAxisCount = aspect == "smallImage" ? 3 : 2;

    return GridView.builder(
      key: PageStorageKey<String>('grid_view_$aspect'),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemCount: mediaFiles.length,

      itemBuilder: (context, index) {
        final file = mediaFiles[index];
        final isSelected = _isMultiSelectMode
            ? _selectedFilePaths.contains(file.path)
            : _selectedFile?.path == file.path;

        return GestureDetector(


          onTap: () {
            setState(() {
              if (_isMultiSelectMode) {
                if (_selectedFilePaths.contains(file.path)) {
                  _selectedFilePaths.remove(file.path);
                } else {
                  _selectedFilePaths.add(file.path);
                }
              } else {
                _selectedFile = file;
                FileUtils.showPopupMenu(
                  context,
                  file,
                  widget.camera,
                  null,
                  onEnterMultiSelectMode: () {
                    setState(() {
                      _isMultiSelectMode = true;
                      _selectedFilePaths.add(file.path);
                    });
                  },
                );
              }
            });
          },

          onDoubleTap: () =>FileUtils.openFullScreen(context, file, mediaFiles),
          child: Container(

            decoration: BoxDecoration(
              color: isSelected ? Colors.blueGrey.shade400 : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: file.path.endsWith(".mp4")
                          ? Icon(Icons.videocam, size: 50)
                          : Image.file(File(file.path)),
                    ),
                    SizedBox(height: 4),
                    Text(
                      file.path.split('/').last,
                      style: TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                if (_hasNote(file.path, mediaNotes))
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => showNoteDialog(context, file.path),
                      child: Icon(Icons.article, color: Colors.amber),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _hasNote(String path, Map<String, String> mediaNotes) {
    return mediaNotes.containsKey(path) && mediaNotes[path]!.isNotEmpty;
  }




  void showNoteDialog(BuildContext context, String imagePath) {
    final note = mediaNotesNotifier.value[imagePath] ?? "No note found.";

    showDialog(
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
                  "note".tr,
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
        content: Text(note),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("ok".tr),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              NoteUtils.showNoteInputModal(
                context,
                imagePath,
                    (path, note) => NoteUtils.addOrUpdateNote(path, note, mediaNotesNotifier),
                initialText: note,
                isEditing: true,
              );

            },
            child: Text("edit".tr),
          ),
          TextButton(
            onPressed: () {
              mediaNotesNotifier.value = {...mediaNotesNotifier.value}
                ..remove(imagePath);
              Fluttertoast.showToast(msg: "Note deleted successfully!");
              Navigator.pop(context);
            },
            child: Text("delete".tr, style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }


  Future<void> _suppressSelectedFiles() async {
    if (_selectedFilePaths.isEmpty) return;

    final confirmed = await _showBatchConfirmationDialog(
      context,
      title: "Delete ${_selectedFilePaths.length} files?".tr,
      message: "This action cannot be undone".tr,
      confirmText: "Delete All".tr,
    );

    if (!confirmed) return;

    ProgressDialog.show(context, _selectedFilePaths.length);

    try {
      int completed = 0;
      for (final path in _selectedFilePaths.toList()) {
        await FileUtils.deleteFile(context, File(path));
        completed++;
        ProgressDialog.updateProgress(completed, _selectedFilePaths.length);
      }

      Fluttertoast.showToast(msg: "Deleted ${_selectedFilePaths.length} files".tr);
    } catch (e) {
      Fluttertoast.showToast(msg: "Error deleting files".tr);
    } finally {
      ProgressDialog.dismiss();
      _exitMultiSelectMode();
      setState(() {});
    }
  }


  Future<void> _duplicateSelectedFiles() async {
    if (_selectedFilePaths.isEmpty) return;

    final confirmed = await _showBatchConfirmationDialog(
      context,
      title: "Duplicate ${_selectedFilePaths.length} files?".tr,
      message: "duplicateWarning".tr,
      confirmText: "duplicateAll".tr,
    );

    if (!confirmed) return;

    ProgressDialog.show(context, _selectedFilePaths.length);

    try {
      int completed = 0;
      for (final path in _selectedFilePaths.toList()) {
        await FileUtils.duplicateFile(context, File(path));
        completed++;
        ProgressDialog.updateProgress(completed, _selectedFilePaths.length);
      }

      Fluttertoast.showToast(msg: "Duplicated ${_selectedFilePaths.length} files".tr);

    } catch (e) {
      Fluttertoast.showToast(msg: "Error duplicating files".tr);
    } finally {
      ProgressDialog.dismiss();
      _exitMultiSelectMode();
      setState(() {});
    }
  }



  Future<bool> _showBatchConfirmationDialog(
      BuildContext context, {
        required String title,
        required String message,
        required String confirmText,
      }) async {
    return await showDialog<bool>(
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
                title,
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
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    ) ?? false;
  }



  Future<void> _moveSelectedFiles() async {
    if (_selectedFilePaths.isEmpty) return;

    Fluttertoast.showToast(
      msg: "Select destination folder for ${_selectedFilePaths.length} files".tr,
      toastLength: Toast.LENGTH_LONG,
    );


    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => FileManager(
          selectedPaths: _selectedFilePaths.toList(),
          enableFolderSelection: true,
          onFilesMoved: () {
            ProgressDialog.show(context, _selectedFilePaths.length);

            try {
              int completed = 0;
              for (final path in _selectedFilePaths.toList()) {
                completed++;
                ProgressDialog.updateProgress(completed, _selectedFilePaths.length);
              }

              Fluttertoast.showToast(msg: "Moved ${_selectedFilePaths.length} files".tr);
            } catch (e) {
              Fluttertoast.showToast(msg: "Error moving files".tr);
            } finally {
              ProgressDialog.dismiss();
              _exitMultiSelectMode();
              setState(() {});
            }
          },
        ),
      ),
        (route) => route.isFirst,
    );

  }


  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedFilePaths.clear();
    });
  }


  Future<void> loadNotesFromFolder(String folderPath) async {
    final dir = Directory(folderPath);
    final noteFiles = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith(".txt"))
        .toList();

    final Map<String, String> notes = {};

    for (var noteFile in noteFiles) {
      try {
        String noteContent = await noteFile.readAsString();
        String imagePath = noteFile.path.replaceAll(".txt", ".jpg");
        notes[imagePath] = noteContent;
      } catch (e) {
        print("[ERROR] Failed to read note file: ${noteFile.path}");
      }
    }

    mediaNotesNotifier.value = notes;
    print("[DEBUG] Loaded ${notes.length} notes from disk.");
  }

}

class FullScreenMediaViewer extends StatefulWidget {
  final List<File> mediaFiles;
  final int initialIndex;
  final CameraDescription? camera;

  const FullScreenMediaViewer({
    required this.mediaFiles,
    required this.initialIndex,
    this.camera,
    Key? key,
  }) : super(key: key);


  @override
  State<FullScreenMediaViewer> createState() => _FullScreenMediaViewerState();
}

class _FullScreenMediaViewerState extends State<FullScreenMediaViewer> {


  late PageController _pageController;
  late int _currentIndex;
  VideoPlayerController? _videoController;
  bool _isVideoInitializing = false;
  Map<String, double> _rotationAngles = {};

  Map<String, Future<void>?> _saveFutures = {};
  double _normalizeAngle(double angle) {
    return (angle % 360 + 360) % 360;
  }
  final Map<String, String> _renamedFiles = {};
  bool _folderContentChanged = false;
  final Set<String> _duplicatedFiles = {};

  double _scale = 1.0;
  double _previousScale = 1.0;
  TransformationController _transformationController = TransformationController();
  double _rotationAngle = 0.0;
  bool _isZoomed = false;
  int _imageReloadKey = 0;
  bool _notesLoaded = false;

  bool _isImageLoading = false;
  bool _hasChanges = false;

  late final CameraDescription camera;
  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _initializeCurrentMedia();
    _rotationAngle = 0.0; // reset rotation when changing media
    _transformationController.value = Matrix4.identity();
    _transformationController.addListener(_updateZoomState);
    availableCameras().then((cameras) {
      setState(() {
        camera = cameras.first;
      });
    });
    _initializeViewer();
    // final rootPath = "/storage/emulated/0";
    // NoteUtils.loadAllNotes(rootPath);

  }



  Future<void> _initializeViewer() async {
    if (mediaNotesNotifier.value.isEmpty && !_notesLoaded) {
      _notesLoaded = true;
      await loadNotesFromFolder(widget.mediaFiles[_currentIndex].path);
    }

    _initializeCurrentMedia();
  }

  @override
  void dispose() {
    _transformationController.removeListener(_updateZoomState);
    _pageController.dispose();
    _disposeVideoController();
    _transformationController.dispose();

    super.dispose();
  }

  void _disposeVideoController() {
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;
  }

  void _initializeCurrentMedia() {
    // final file = widget.mediaFiles[_currentIndex];
    // if (file.path.endsWith('.mp4')) {
    //   _isVideoInitializing = true;
    //   _disposeVideoController();
    //   _videoController = VideoPlayerController.file(file)
    //     ..initialize().
    final file = widget.mediaFiles[_currentIndex];
    if (!file.path.endsWith('.mp4')) {
      _disposeVideoController();
      return;
    }

    if (_videoController?.dataSource == file.path) return;

    _isVideoInitializing = true;
    _disposeVideoController();
    _videoController = VideoPlayerController.file(file)
      ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _isVideoInitializing = false;
              _videoController?.play();
            });
          }
        }).catchError((e) {
          if (mounted) {
            setState(() {
              _isVideoInitializing = false;
            });
          }
        });
    }
  void _updateZoomState() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final isZoomed = scale > 1.01;
    if (isZoomed != _isZoomed) {
      setState(() => _isZoomed = isZoomed);
    }
  }

  static List<int> _rotateImageInIsolate(Map<String, dynamic> params) {
    final bytes = params['bytes'] as Uint8List;
    final angle = params['angle'] as double;
    final isPng = params['isPng'] as bool;

    final image = img.decodeImage(bytes)!;
    final rotated = img.copyRotate(image, angle: angle.toInt());

    if (isPng) {
      return img.encodePng(rotated);
    } else {
      return img.encodeJpg(rotated);
    }
  }

  // void _handleMenuSelection(String value) async {
  //   final file = widget.mediaFiles[_currentIndex];
  //
  //   switch (value) {
  //     case 'rename':
  //       final renamed = await FileUtils.showRenameDialog(
  //         context,
  //         file,
  //         onMoveRequested: () async {
  //           Fluttertoast.showToast(
  //             msg: "Select destination folder".tr,
  //             toastLength: Toast.LENGTH_LONG,
  //           );
  //
  //           Navigator.pushReplacement(
  //             context,
  //             MaterialPageRoute(
  //               builder: (context) => FileManager(
  //                 selectedPaths: [file.path],
  //                 enableFolderSelection: true,
  //               ),
  //             ),
  //           );
  //
  //
  //         },
  //       );
  //
  //       break;
  //
  //     case 'annotate':
  //       NoteUtils.showNoteInputModal(
  //         context,
  //         file.path,
  //             (imagePath, noteText) {
  //           NoteUtils.addOrUpdateNote(imagePath, noteText, mediaNotesNotifier);
  //           Navigator.pop(context);
  //         },
  //       );
  //       break;
  //
  //     case 'duplicate':
  //       final success = await FileUtils.duplicateFile(context, file);
  //       if (success == true) {
  //         Navigator.pop(context);
  //       }
  //       break;
  //
  //     case 'new':
  //       Navigator.pop(context);
  //       Navigator.push(
  //         context,
  //         MaterialPageRoute(
  //           builder: (context) => MainScreen(
  //             dateFormatNotifier: dateFormatNotifier,
  //             timeFormatNotifier: timeFormatNotifier,
  //             camera: camera,
  //           ),
  //         ),
  //       );
  //       break;
  //
  //     case 'move':
  //       Navigator.pushReplacement(
  //         context,
  //         MaterialPageRoute(
  //           builder: (context) => FileManager(
  //             selectedPaths: [file.path],
  //             enableFolderSelection: true,
  //             onFilesMoved: () {
  //               Navigator.pop(context);
  //             },
  //           ),
  //         ),
  //       );
  //
  //       break;
  //
  //     case 'share':
  //       final success = await FileUtils.shareFile(context, file);
  //       if (success == true) {
  //         Navigator.pop(context);
  //       }
  //       break;
  //
  //     case 'suppress':
  //       final success = await FileUtils.deleteFile(context, file);
  //       if (success != null) {
  //         Navigator.pop(context);
  //       }
  //       break;
  //
  //     // case 'rotate':
  //     //   final filePath = file.path;
  //     //   setState(() {
  //     //     final currentAngle = _rotationAngles[filePath] ?? 0.0;
  //     //     _rotationAngles[filePath] = (currentAngle - 90.0) % 360;
  //     //   });
  //     //   break;
  //     case 'rotate':
  //       final currentFile = widget.mediaFiles[_currentIndex]; // ✅ Use the current file
  //       await _rotateAndSaveImage(currentFile, -90);
  //       setState(() {}); // Refresh UI
  //       break;
  //
  //
  //
  //     case 'crop':
  //       if (!file.path.endsWith('.jpg') &&
  //           !file.path.endsWith('.jpeg') &&
  //           !file.path.endsWith('.png')) {
  //         Fluttertoast.showToast(msg: "Only images can be cropped");
  //         return;
  //       }
  //
  //       final success = await Navigator.push<bool>(
  //         context,
  //         MaterialPageRoute(
  //           builder: (_) => ImageCropScreen(imageFile: file),
  //         ),
  //       );
  //
  //       if (success == true) {
  //         setState(() {});
  //         Fluttertoast.showToast(msg: "Image cropped successfully");
  //       }
  //       break;
  //
  //
  //   }
  // }
  void _handleMenuSelection(String value) async {
    final file = widget.mediaFiles[_currentIndex];

    switch (value) {
      case 'rename':
        final renamed = await FileUtils.showRenameDialog(
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
                  onFileRenamed: (oldPath, newPath) {
                    print("File renamed from $oldPath to $newPath");
                  },
                ),
              ),
            );
          },
        );

        if (renamed != null) {
          final oldPath = file.path;
          final newPath = renamed.path;

          await _refreshImage(newPath);
          setState(() {
            widget.mediaFiles[_currentIndex] = renamed;
            _imageReloadKey++;
            _hasChanges = true;
          });


          _renamedFiles[oldPath] = newPath;
        }
        break;

      case 'move':
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => FileManager(
              selectedPaths: [file.path],
              enableFolderSelection: true,
              onFilesMoved: () {
                Navigator.pop(context);
              },
              onFileRenamed: (oldPath, newPath) {
                print("File renamed from $oldPath to $newPath");
              },
            ),
          ),
        );
        break;

      case 'annotate':
        await NoteUtils.showNoteInputModal(
          context,
          file.path,
              (imagePath, noteText) async {
            await NoteUtils.addOrUpdateNote(imagePath, noteText, mediaNotesNotifier);
            Navigator.pop(context);
          },
        );
        break;


      case 'duplicate':
        final success = await FileUtils.duplicateFile(context, file);
        if (success == true) {
          setState(() {
            _hasChanges = true;
            _folderContentChanged = true;
            _duplicatedFiles.add(file.path);
          });

          Fluttertoast.showToast(msg: "File duplicated successfully".tr);
        }
        break;


      // case 'new':
      //   Navigator.pop(context);
      //   Navigator.push(
      //     context,
      //     MaterialPageRoute(
      //       builder: (context) => MainScreen(
      //         dateFormatNotifier: dateFormatNotifier,
      //         timeFormatNotifier: timeFormatNotifier,
      //         camera: camera,
      //       ),
      //     ),
      //   );
      //   break;

      // case 'move':
      //   Navigator.pushReplacement(
      //     context,
      //     MaterialPageRoute(
      //       builder: (context) => FileManager(
      //         selectedPaths: [file.path],
      //         enableFolderSelection: true,
      //         onFilesMoved: () {
      //           Navigator.pop(context);
      //         },
      //       ),
      //     ),
      //   );
      //   break;

      case 'share':
        final success = await FileUtils.shareFile(context, file);
        if (success == true) {
          Navigator.pop(context);
        }
        break;

      case 'suppress':
        final success = await FileUtils.deleteFile(context, file);
        if (success != null) {
          setState(() {
            _hasChanges = true;
            _folderContentChanged = true;
          });

          widget.mediaFiles.removeAt(_currentIndex);

          if (widget.mediaFiles.isEmpty) {
            Navigator.pop(context);
          } else {
            if (_currentIndex >= widget.mediaFiles.length) {
              _currentIndex = widget.mediaFiles.length - 1;
            }
            _pageController.animateToPage(
              _currentIndex,
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );

            setState(() {
              _imageReloadKey++;
            });

            Fluttertoast.showToast(msg: "File deleted successfully".tr);
          }
        }
        break;

      // case 'rotate':
      //   final currentFile = widget.mediaFiles[_currentIndex];
      //   await _rotateAndSaveImage(currentFile, -90);
      //   setState(() {
      //     _imageReloadKey++;
      //   });
      //   break;


      case 'rotate':
        final path = widget.mediaFiles[_currentIndex].path;
        _rotationAngles[path] = _normalizeAngle((_rotationAngles[path] ?? 0.0) - 90.0);
        setState(() {});
        // Fluttertoast.showToast(msg: "Rotating file...");
        _scheduleSaveForPath(path);
        break;

      case 'crop':
        if (!file.path.endsWith('.jpg') &&
            !file.path.endsWith('.jpeg') &&
            !file.path.endsWith('.png')) {
          Fluttertoast.showToast(msg: "Only images can be cropped");
          return;
        }

        final success = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ImageCropScreen(imageFile: file),
          ),
        );

        if (success == true) {
          await _refreshImage(file.path);
          setState(() {
            _imageReloadKey++;
          });
          Fluttertoast.showToast(msg: "Image cropped successfully");
        }
        break;
    }
  }


  void _scheduleSaveForPath(String path) {
    if (_saveFutures[path] != null) return;
    _saveFutures[path] = _performSaveForPath(path).whenComplete(() {
      _saveFutures[path] = null;
      if (mounted && (_rotationAngles[path] ?? 0.0) != 0.0) {
        _scheduleSaveForPath(path);
      }
    });
  }

  Future<void> _performSaveForPath(String path) async {
    final angle = _rotationAngles[path] ?? 0.0;
    if (angle == 0.0) return;

    final file = File(path);
    await _rotateAndSaveImage(file, angle);

    if (mounted) {
      setState(() {
        _rotationAngles[path] = _normalizeAngle((_rotationAngles[path] ?? 0.0) - angle);
        _imageReloadKey++;
      });
    }
  }

  //
  //
  // @override
  // Widget build(BuildContext context) {
  //   final currentFile = widget.mediaFiles[_currentIndex];
  //
  //   return Scaffold(
  //     backgroundColor: Colors.black,
  //     appBar: AppBar(
  //       title: Text(p.basename(currentFile.path)),
  //       actions: [
  //         PopupMenuButton<String>(
  //           icon: Icon(Icons.more_vert),
  //           onSelected: _handleMenuSelection,
  //           itemBuilder: (context) =>  [
  //             PopupMenuItem(value: 'annotate', height: 36, child: Text('annotate'.tr)),
  //             PopupMenuItem(value: 'rename', height: 36, child: Text('rename'.tr)),
  //             PopupMenuItem(value: 'duplicate', height: 36, child: Text('duplicate'.tr)),
  //             PopupMenuItem(value: 'new', height: 36, child: Text('new'.tr)),
  //             PopupMenuItem(value: 'move', height: 36, child: Text('moveTo'.tr)),
  //             PopupMenuItem(value: 'share', height: 36, child: Text('share'.tr)),
  //             PopupMenuItem(value: 'suppress', height: 36, child: Text('suppress'.tr)),
  //             PopupMenuItem(value: 'rotate', height: 36, child: Text('rotate'.tr)),
  //             PopupMenuItem(value: 'crop', height: 36, child: Text('crop'.tr)),
  //
  //           ],
  //         ),
  //       ],
  //     ),
  //     body: Stack(
  //       children: [
  //         PageView.builder(
  //
  //           controller: _pageController,
  //           physics: _isZoomed
  //               ? const NeverScrollableScrollPhysics()
  //               : const BouncingScrollPhysics(),
  //           itemCount: widget.mediaFiles.length,
  //           onPageChanged: (index) {
  //             setState(() {
  //               _currentIndex = index;
  //               _initializeCurrentMedia();
  //               _transformationController.value = Matrix4.identity();
  //               _isZoomed = false;
  //             });
  //           },
  //
  //           itemBuilder: (context, index) {
  //             final file = widget.mediaFiles[index];
  //             if (file.path.endsWith('.mp4')) {
  //               return _buildVideoPlayer();
  //             } else {
  //
  //               return LayoutBuilder(
  //                 builder: (context, constraints) {
  //                   return
  //
  //                     GestureDetector(
  //                       onDoubleTapDown: (details) {
  //                         final tapPosition = details.localPosition;
  //                         final scale = _transformationController.value.getMaxScaleOnAxis();
  //                         if (scale > 1.0) {
  //                           _transformationController.value = Matrix4.identity();
  //                           _isZoomed = false;
  //                         } else {
  //                           final zoom = 2.5;
  //                           final x = -tapPosition.dx * (zoom - 1);
  //                           final y = -tapPosition.dy * (zoom - 1);
  //                           _transformationController.value = Matrix4.identity()
  //                             ..translate(x, y)
  //                             ..scale(zoom);
  //                           _isZoomed = true;
  //                         }
  //                         setState(() {});
  //                       },
  //                       onScaleStart: (_) {
  //                         _previousScale = _scale;
  //                       },
  //                       onScaleUpdate: (details) {
  //                         _scale = _previousScale * details.scale;
  //                         if (_scale > 1.0) {
  //                           _isZoomed = true;
  //                         } else {
  //                           _isZoomed = false;
  //                         }
  //                         setState(() {});
  //                       },
  //                       // child: InteractiveViewer(
  //                       //   transformationController: _transformationController,
  //                       //   panEnabled: true,
  //                       //   scaleEnabled: true,
  //                       //   minScale: 1.0,
  //                       //   maxScale: 4.0,
  //                       //   child: FutureBuilder(
  //                       //     future: _refreshImage(file.path),
  //                       //     builder: (context, snapshot) {
  //                       //       return Transform.rotate(
  //                       //         angle: (_rotationAngles[file.path] ?? 0) * 3.1415926535 / 180,
  //                       //         child: Image(
  //                       //           image: FileImage(File(file.path)),
  //                       //           key: ValueKey(file.path), // refreshes on file path
  //                       //         ),
  //                       //       );
  //                       //     },
  //                       //   ),
  //                       // ),
  //                       child: InteractiveViewer(
  //                         transformationController: _transformationController,
  //                         panEnabled: true,
  //                         scaleEnabled: true,
  //                         minScale: 1.0,
  //                         maxScale: 4.0,
  //                         child: FutureBuilder(
  //                           future: _refreshImage(file.path),
  //                           builder: (context, snapshot) {
  //                             final angle = (_rotationAngles[file.path] ?? 0);
  //                             final radians = angle * 3.1415926535 / 180;
  //
  //                             return Center(
  //                               child: FittedBox(
  //                                 fit: BoxFit.contain,
  //                                 child: Transform.rotate(
  //                                   angle: radians,
  //                                   child: Image.file(
  //                                     File(file.path),
  //                                     key: ValueKey(file.path),
  //                                   ),
  //                                 ),
  //                               ),
  //                             );
  //                           },
  //                         ),
  //                       ),
  //
  //
  //                     );
  //
  //                 },
  //               );
  //
  //             }
  //           },
  //         ),
  //
  //         Positioned(
  //           bottom: MediaQuery.of(context).padding.bottom + 16,
  //           left: 0,
  //           right: 0,
  //           child: Text(
  //             "${_currentIndex + 1}/${widget.mediaFiles.length}",
  //             textAlign: TextAlign.center,
  //             style: TextStyle(color: Colors.white, fontSize: 16),
  //           ),
  //         ),
  //         if (_isVideoInitializing)
  //           Center(child: CircularProgressIndicator()),
  //       ],
  //     ),
  //   );
  // }
  @override
  Widget build(BuildContext context) {
    final currentFile = widget.mediaFiles[_currentIndex];
    final screenSize = MediaQuery.of(context).size;

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, {
          'hasChanges': _hasChanges,
          'renamedFiles': _renamedFiles,
          'folderContentChanged': _folderContentChanged,
          'duplicatedFiles': _duplicatedFiles.toList(),

        });
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          iconTheme: const IconThemeData(color: Colors.white),
      
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.basename(p.dirname(currentFile.path)),
                style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
              ),
              Text(
                p.basename(currentFile.path), // file name
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ],
          ),
          backgroundColor: Colors.black,
        ),
      
        body: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              physics: _isZoomed
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              itemCount: widget.mediaFiles.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                  _initializeCurrentMedia();
                  _transformationController.value = Matrix4.identity();
                  _isZoomed = false;
                });
              },
              itemBuilder: (context, index) {
                final file = widget.mediaFiles[index];
      
                // --- VIDEOS ---
                if (file.path.endsWith('.mp4')) {
                  return Stack(
                    children: [
                      _buildVideoPlayer(),
                      if (_isVideoInitializing)
                        const Center(child: CircularProgressIndicator(color: Colors.white)),
                    ],
                  );
                }
      
                // --- IMAGES ---
                return LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      onLongPress: () async {
                        // your popup menu logic...
                        final selected = await showMenu<String>(
                          context: context,
                          position: RelativeRect.fromLTRB(
                            screenSize.width - 10,
                            kToolbarHeight + 10,
                            0,
                            0,
                          ),
                          items: [
                            PopupMenuItem(value: 'annotate', height: 36, child: Text('annotate'.tr)),
                            PopupMenuItem(value: 'rename', height: 36, child: Text('rename'.tr)),
                            PopupMenuItem(value: 'duplicate', height: 36, child: Text('duplicate'.tr)),
                            // PopupMenuItem(value: 'new', height: 36, child: Text('new'.tr)),
                            PopupMenuItem(value: 'move', height: 36, child: Text('moveTo'.tr)),
                            PopupMenuItem(value: 'share', height: 36, child: Text('share'.tr)),
                            PopupMenuItem(value: 'suppress', height: 36, child: Text('suppress'.tr)),
                            PopupMenuItem(value: 'rotate', height: 36, child: Text('rotate'.tr)),
                            PopupMenuItem(value: 'crop', height: 36, child: Text('crop'.tr)),
                          ],
                        );
                        if (selected != null) _handleMenuSelection(selected);
                      },
                      onDoubleTapDown: (details) { final tapPosition = details.localPosition; final scale = _transformationController.value.getMaxScaleOnAxis(); if (scale > 1.0) { _transformationController.value = Matrix4.identity(); _isZoomed = false; } else { const zoom = 2.5; final x = -tapPosition.dx * (zoom - 1); final y = -tapPosition.dy * (zoom - 1); _transformationController.value = Matrix4.identity() ..translate(x, y) ..scale(zoom); _isZoomed = true; } setState(() {}); },
                      // onScaleStart: (_) => _previousScale = _scale,
                      // onScaleUpdate: (details) {
                      //   _scale = _previousScale * details.scale;
                      //   if (_scale > 1.0) {
                      //     _isZoomed = true;
                      //   } else {
                      //     _isZoomed = false;
                      //   }
                      //   setState(() {});
                      // },
      
                      child: Stack(
                        children: [
                          // FutureBuilder(
                          //   // future: Future.wait([
                          //   //   _refreshImage(file.path),
                          //   //   _getImageSize(file.path),
                          //   // ]),
                          //   builder: (context, snapshot) {
                          //     if (snapshot.connectionState == ConnectionState.waiting) {
                          //       return const Center(
                          //         child: CircularProgressIndicator(color: Colors.white),
                          //       );
                          //     }
                          //
                          //     if (!snapshot.hasData) {
                          //       return const Center(
                          //         child: Icon(Icons.error, color: Colors.red),
                          //       );
                          //     }
                          //
                          //     final angle = (_rotationAngles[file.path] ?? 0);
                          //     final imageWidget = Image.file(
                          //       File(file.path),
                          //       key: ValueKey('$_imageReloadKey-$angle-${file.path}'),
                          //       fit: BoxFit.contain,
                          //     );
                          //
                          //     return InteractiveViewer(
                          //       transformationController: _transformationController,
                          //       panEnabled: true,
                          //       scaleEnabled: true,
                          //       minScale: 1.0,
                          //       maxScale: 4.0,
                          //       child: RotatedBox(
                          //         quarterTurns: angle ~/ 90,
                          //         child: Center(child: imageWidget),
                          //       ),
                          //     );
                          //   },
                          // ),
                          _buildImage(file),
      
                        ],
                      ),
                    );
                  },
                );
              },
            ),
      
            // bottom index text
            // Positioned(
            //   bottom: MediaQuery.of(context).padding.bottom + 16,
            //   left: 0,
            //   right: 0,
            //   child: Text(
            //     // "${_currentIndex + 1}/${widget.mediaFiles.length}",
            //     textAlign: TextAlign.center,
            //     style: const TextStyle(color: Colors.white, fontSize: 16),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }

  Future<void> loadNotesFromFolder(String folderPath) async {
    final Map<String, String> notes = {};

    void collectNotes(Directory dir) {
      try {
        final entries = dir.listSync();

        for (final entity in entries) {
          if (entity is File && entity.path.endsWith('.txt')) {
            try {
              final noteContent = entity.readAsStringSync();
              final imagePath = entity.path.replaceAll(RegExp(r'\.txt$'), '.jpg');
              notes[imagePath] = noteContent;
            } catch (e) {
              debugPrint("[ERROR] Failed to read note: ${entity.path}");
            }
          } else if (entity is Directory) {
            collectNotes(entity); // 🔁 Recurse into subfolder
          }
        }
      } catch (e) {
        debugPrint("🚫 Skipping inaccessible folder: ${dir.path}");
      }
    }

    collectNotes(Directory(folderPath));

    mediaNotesNotifier.value = notes;
    debugPrint("[DEBUG] Loaded ${notes.length} notes recursively.");
  }
  Future<void> _refreshImage(String filePath) async {
    final provider = FileImage(File(filePath));
    await provider.evict();
  }


  Widget _buildImage(File file) {
    final angle = _rotationAngles[file.path] ?? 0.0;
    final normAngle = _normalizeAngle(angle);
    final quarterTurns = (normAngle / 90).toInt() % 4;

    return Stack(
      children: [
        Center(
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 1.0,
            maxScale: 4.0,
            child: RotatedBox(
              quarterTurns: quarterTurns,
              child: Image.file(
                file,
                key: ValueKey(_imageReloadKey),
                fit: BoxFit.contain,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded || frame != null) {
                    if (_isImageLoading) {
                      setState(() => _isImageLoading = false);
                    }
                    return child;
                  } else {
                    if (!_isImageLoading) {
                      setState(() => _isImageLoading = true);
                    }
                    return const SizedBox.shrink();
                  }
                },
              ),
            ),
          ),
        ),
        if (_isImageLoading)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
  // Future<void> _rotateAndSaveImage(File file, int angle) async {
  //   // Read file
  //   final bytes = await file.readAsBytes();
  //   final originalImage = img.decodeImage(bytes);
  //   if (originalImage == null) return;
  //
  //   // Rotate pixels
  //   final rotatedImage = img.copyRotate(originalImage, angle: angle);
  //
  //   // Encode back to same format
  //   List<int> encodedBytes;
  //   if (file.path.toLowerCase().endsWith('.png')) {
  //     encodedBytes = img.encodePng(rotatedImage);
  //   } else {
  //     encodedBytes = img.encodeJpg(rotatedImage);
  //   }
  //
  //   // Overwrite file
  //   await file.writeAsBytes(encodedBytes);
  //
  //   // Evict old image from cache
  //   await _refreshImage(file.path);
  //
  //   // Force UI to rebuild with new key
  //   setState(() {
  //     // _imageReloadKey = DateTime.now().millisecondsSinceEpoch;
  //     _imageReloadKey++;
  //   });
  // }


  Future<void> _rotateAndSaveImage(File file, double angle) async {
    try {
      final bytes = await file.readAsBytes();
      final isPng = file.path.toLowerCase().endsWith('.png');
      final encoded = await compute(_rotateImageInIsolate, {
        'bytes': bytes,
        'angle': angle,
        'isPng': isPng,
      });
      await file.writeAsBytes(encoded);
      await _refreshImage(file.path);
      // Fluttertoast.showToast(msg: "Rotation saved!");
    } catch (e) {
      Fluttertoast.showToast(msg: "Rotation failed: $e");
    }
  }

  Future<Size> _getImageSize(String path) async {
    final completer = Completer<Size>();
    final image = Image.file(File(path));
    image.image.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((ImageInfo info, bool _) {
        completer.complete(
          Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          ),
        );
      }),
    );
    return completer.future;
  }

  Widget _buildVideoPlayer() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return Container();
    }
    if (_isVideoInitializing)
      const Center(child: CircularProgressIndicator());

    return AspectRatio(
      aspectRatio: _videoController!.value.aspectRatio,
      child: Stack(
        children: [
          VideoPlayer(_videoController!),
          if (!_videoController!.value.isPlaying)
            Center(
              child: IconButton(
                icon: Icon(Icons.play_arrow, size: 50, color: Colors.white),
                onPressed: () {
                  _videoController?.play();
                  setState(() {});
                },
              ),
            ),
        ],
      ),
    );
  }
}


