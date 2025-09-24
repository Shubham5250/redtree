import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:RedTree/globals.dart';

class GoogleDriveService {
  static const String _appFolderName = 'RedTree_Backup';
  static const String _metadataFileName = 'redtree_metadata.json';
  
  GoogleSignIn? _googleSignIn;
  drive.DriveApi? _driveApi;
  String? _appFolderId;

  GoogleDriveService() {
    _googleSignIn = GoogleSignIn(
      scopes: [
        'email',
        'https://www.googleapis.com/auth/drive.file',
      ],
    );
  }

  Future<bool> isSignedIn() async {
    return await _googleSignIn!.isSignedIn();
  }

  Future<bool> signIn() async {
    try {
      final GoogleSignInAccount? account = await _googleSignIn!.signIn();
      if (account == null) return false;

      final GoogleSignInAuthentication auth = await account.authentication;
      final AuthClient client = authenticatedClient(
        http.Client(),
        AccessCredentials(
          AccessToken('Bearer', auth.accessToken!, DateTime.now().add(Duration(hours: 1))),
          auth.idToken,
          ['https://www.googleapis.com/auth/drive.file'],
        ),
      );

      _driveApi = drive.DriveApi(client);
      return true;
    } catch (e) {
      print('Google Sign-in error: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn!.signOut();
    _driveApi = null;
    _appFolderId = null;
  }

  Future<String?> _getOrCreateAppFolder() async {
    if (_appFolderId != null) return _appFolderId;

    try {
      // Search for existing folder
      final response = await _driveApi!.files.list(
        q: "name='$_appFolderName' and mimeType='application/vnd.google-apps.folder' and trashed=false",
        spaces: 'drive',
      );

      if (response.files != null && response.files!.isNotEmpty) {
        _appFolderId = response.files!.first.id;
        return _appFolderId;
      }

      // Create new folder if not found
      final folder = drive.File();
      folder.name = _appFolderName;
      folder.mimeType = 'application/vnd.google-apps.folder';

      final createdFolder = await _driveApi!.files.create(folder);
      _appFolderId = createdFolder.id;
      return _appFolderId;
    } catch (e) {
      print('Error creating/finding app folder: $e');
      return null;
    }
  }

  Future<bool> uploadFile(File file, String fileName) async {
    try {
      final folderId = await _getOrCreateAppFolder();
      if (folderId == null) return false;

      final drive.File driveFile = drive.File();
      driveFile.name = fileName;
      driveFile.parents = [folderId];

      final bytes = await file.readAsBytes();
      final media = drive.Media(
        Stream.fromIterable([bytes]),
        bytes.length,
      );

      await _driveApi!.files.create(driveFile, uploadMedia: media);
      return true;
    } catch (e) {
      print('Error uploading file: $e');
      return false;
    }
  }

  Future<bool> uploadString(String content, String fileName) async {
    try {
      final folderId = await _getOrCreateAppFolder();
      if (folderId == null) return false;

      final drive.File driveFile = drive.File();
      driveFile.name = fileName;
      driveFile.parents = [folderId];

      final bytes = utf8.encode(content);
      final media = drive.Media(
        Stream.fromIterable([bytes]),
        bytes.length,
      );

      await _driveApi!.files.create(driveFile, uploadMedia: media);
      return true;
    } catch (e) {
      print('Error uploading string: $e');
      return false;
    }
  }

  Future<List<drive.File>> listFiles() async {
    try {
      final folderId = await _getOrCreateAppFolder();
      if (folderId == null) return [];

      final response = await _driveApi!.files.list(
        q: "'$folderId' in parents and trashed=false",
        spaces: 'drive',
      );

      return response.files ?? [];
    } catch (e) {
      print('Error listing files: $e');
      return [];
    }
  }

  Future<Uint8List?> downloadFile(String fileId) async {
    try {
      final response = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      return response.stream.toList().then((chunks) {
        final bytes = <int>[];
        for (final chunk in chunks) {
          bytes.addAll(chunk);
        }
        return Uint8List.fromList(bytes);
      });
    } catch (e) {
      print('Error downloading file: $e');
      return null;
    }
  }

  Future<bool> deleteFile(String fileId) async {
    try {
      await _driveApi!.files.delete(fileId);
      return true;
    } catch (e) {
      print('Error deleting file: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getMetadata() async {
    try {
      final files = await listFiles();
      final metadataFile = files.firstWhere(
        (file) => file.name == _metadataFileName,
        orElse: () => drive.File(),
      );

      if (metadataFile.id == null) return null;

      final bytes = await downloadFile(metadataFile.id!);
      if (bytes == null) return null;

      final content = utf8.decode(bytes);
      return json.decode(content);
    } catch (e) {
      print('Error getting metadata: $e');
      return null;
    }
  }

  Future<bool> saveMetadata(Map<String, dynamic> metadata) async {
    try {
      final content = json.encode(metadata);
      return await uploadString(content, _metadataFileName);
    } catch (e) {
      print('Error saving metadata: $e');
      return false;
    }
  }

  Future<bool> backupAppData() async {
    try {
      if (!await isSignedIn()) {
        throw Exception('Not signed in to Google');
      }

      final appDir = Directory(folderPathNotifier.value);
      if (!await appDir.exists()) {
        throw Exception('App directory does not exist');
      }

      final List<FileSystemEntity> files = await appDir.list(recursive: true).toList();
      final Map<String, dynamic> metadata = {
        'backupDate': DateTime.now().toIso8601String(),
        'files': <Map<String, dynamic>>[],
      };

      int successCount = 0;
      int totalCount = files.whereType<File>().length;

      for (final file in files) {
        if (file is File) {
          final relativePath = path.relative(file.path, from: appDir.path);
          final fileName = path.basename(file.path);
          
          try {
            final success = await uploadFile(file, fileName);
            if (success) {
              metadata['files'].add({
                'name': fileName,
                'path': relativePath,
                'size': await file.length(),
                'modified': await file.lastModified(),
              });
              successCount++;
            }
          } catch (e) {
            print('Error uploading file ${file.path}: $e');
          }
        }
      }

      // Save metadata
      await saveMetadata(metadata);

      return successCount == totalCount;
    } catch (e) {
      print('Error during backup: $e');
      return false;
    }
  }

  Future<bool> restoreAppData() async {
    try {
      if (!await isSignedIn()) {
        throw Exception('Not signed in to Google');
      }

      final metadata = await getMetadata();
      if (metadata == null) {
        throw Exception('No backup metadata found');
      }

      final appDir = Directory(folderPathNotifier.value);
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }

      final files = metadata['files'] as List<dynamic>;
      int successCount = 0;

      for (final fileInfo in files) {
        final fileName = fileInfo['name'] as String;
        final filePath = fileInfo['path'] as String;
        
        try {
          final files = await listFiles();
          final driveFile = files.firstWhere(
            (file) => file.name == fileName,
            orElse: () => drive.File(),
          );

          if (driveFile.id != null) {
            final bytes = await downloadFile(driveFile.id!);
            if (bytes != null) {
              final targetFile = File(path.join(appDir.path, filePath));
              await targetFile.create(recursive: true);
              await targetFile.writeAsBytes(bytes);
              successCount++;
            }
          }
        } catch (e) {
          print('Error restoring file $fileName: $e');
        }
      }

      return successCount == files.length;
    } catch (e) {
      print('Error during restore: $e');
      return false;
    }
  }
}
