import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProgressDialog {
  static BuildContext? _dialogContext;
  static Function(void Function())? _setState;
  static int _completed = 0;
  static int _total = 0;

  static void show(BuildContext context, int totalFiles) {
    _completed = 0;
    _total = totalFiles;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        _dialogContext = context;
        return StatefulBuilder(
          builder: (context, setState) {
            _setState = setState;
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
                      'Dialog Title',
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
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Processing files...".tr),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: _completed / _total,
                  ),
                  const SizedBox(height: 8),
                  Text("$_completed of $_total completed".tr),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static void updateProgress(int current, int total) {
    _completed = current;
    _total = total;
    _setState?.call(() {});
  }

  static void dismiss() {
    if (_dialogContext != null && _dialogContext!.mounted) {
      Navigator.of(_dialogContext!).pop();
    }
    _dialogContext = null;
    _setState = null;
  }
}