import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'BlinkingMicWidget.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class TextEditorScreen extends StatefulWidget {
  final File textFile;
  final String initialContent;

  const TextEditorScreen({
    Key? key,
    required this.textFile,
    required this.initialContent,
  }) : super(key: key);

  @override
  _TextEditorScreenState createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<TextEditorScreen> {
  late TextEditingController _textController;
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialContent);
    _speech = stt.SpeechToText();
    _textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  Future<void> _saveFile() async {
    if (_isSaving) return;
    
    setState(() {
      _isSaving = true;
    });

    try {
      await widget.textFile.writeAsString(_textController.text);
      setState(() {
        _hasUnsavedChanges = false;
      });
      Fluttertoast.showToast(
        msg: 'fileSaved'.tr,
        toastLength: Toast.LENGTH_SHORT,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'saveFailed'.tr,
        toastLength: Toast.LENGTH_SHORT,
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _autoSave() async {
    if (_hasUnsavedChanges && !_isSaving) {
      await _saveFile();
    }
  }

  Future<bool> _onWillPop() async {
    if (_hasUnsavedChanges) {
      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: Text('unsavedChanges'.tr),
          content: Text('saveBeforeExit'.tr),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('discard'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('save'.tr),
            ),
          ],
        ),
      );

      if (shouldSave == true) {
        await _saveFile();
      }
    }
    return true;
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(
            widget.textFile.path.split('/').last,
            style: TextStyle(color: Colors.white),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () async {
              if (await _onWillPop()) {
                Navigator.pop(context);
              }
            },
          ),
          actions: [
            if (_hasUnsavedChanges)
              IconButton(
                icon: Icon(Icons.save, color: Colors.orange),
                onPressed: _isSaving ? null : _saveFile,
                tooltip: 'save'.tr,
              ),
            if (_isSaving)
              Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            // Toolbar with mic and save button
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[900],
              child: Row(
                children: [
                  BlinkingMicWidget(
                    isListening: _isListening,
                    tooltip: 'voiceInput'.tr,
                    onPressed: () async {
                      if (!_isListening) {
                        bool available = await _speech.initialize(
                          onStatus: (status) => print('Speech status: $status'),
                          onError: (error) => print('Speech error: $error'),
                        );

                        if (available) {
                          setState(() {
                            _isListening = true;
                          });
                          _speech.listen(
                            onResult: (result) {
                              final currentText = _textController.text;
                              final selection = _textController.selection;
                              final newText = currentText.substring(0, selection.start) +
                                  result.recognizedWords +
                                  currentText.substring(selection.end);
                              _textController.text = newText;
                              _textController.selection = TextSelection.collapsed(
                                offset: selection.start + result.recognizedWords.length,
                              );
                            },
                          );
                        }
                      } else {
                        _speech.stop();
                        setState(() {
                          _isListening = false;
                        });
                      }
                    },
                  ),
                  Spacer(),
                  if (_hasUnsavedChanges)
                    Text(
                      'unsaved'.tr,
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                ],
              ),
            ),
            // Text editor
            Expanded(
              child: Container(
                padding: EdgeInsets.all(16),
                child: TextField(
                  controller: _textController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: 'startTyping'.tr,
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    border: InputBorder.none,
                  ),
                  onChanged: (text) {
                    // Auto-save after 2 seconds of no typing
                    Future.delayed(Duration(seconds: 2), _autoSave);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
