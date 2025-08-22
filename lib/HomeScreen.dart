import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:RedTree/globals.dart'; // <-- import your globals
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart' as main_screen;
import 'FileManager.dart' as file_manager;

class HomeScreen extends StatefulWidget {
  final CameraDescription camera;

  const HomeScreen({Key? key, required this.camera}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _openCamera(BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => main_screen.MainScreen(
          camera: widget.camera,
          dateFormatNotifier: dateFormatNotifier, // from globals.dart
          timeFormatNotifier: timeFormatNotifier, // from globals.dart
        ),
      ),
    );
  }


  @override
  void initState() {
    super.initState();
    _loadRedTreeStates();
  }

  Future<void> _loadRedTreeStates() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('folderPath') ?? "/storage/emulated/0/Download";
    setState(() {
      folderPathNotifier.value = savedPath;
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // const SizedBox(height: 40),
            Spacer(),

            Text(
              "RedTree",
              style: TextStyle(
                color: Colors.red,

                fontWeight: FontWeight.bold,
                fontSize: MediaQuery.of(context).size.width * 0.15,

              ),
            ),
            SizedBox(height: 40),

            Image.asset(
              'assets/app_icon_home.png',
              height: 240,
              width: 240,
              fit: BoxFit.contain,
            ),
            SizedBox(height: 40),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _openCamera(context),
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.red, width: 2),
                    ),
                    child: Icon(Icons.camera_alt,
                        color: Colors.red, size: 80),
                  ),
                ),
                const SizedBox(width: 40),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => file_manager.FileManager()),
                    );
                  },
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.red, width: 2),
                    ),
                    child: Icon(Icons.folder,
                        color: Colors.red, size: 80),
                  ),
                ),
              ],
            ),
            Spacer(),
            Text(
              "Powered By RedTree",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 18),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.black,
                      width: 1,
                    ),
                  ),
                );
              }),
            ),

            Spacer(),


          ],
        ),
      ),
    );
  }
}
