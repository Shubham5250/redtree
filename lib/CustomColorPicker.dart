import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomColorPicker extends StatefulWidget {
  final Color? currentColor;
  final Function(Color) onColorSelected;
  final String title;

  const CustomColorPicker({
    Key? key,
    this.currentColor,
    required this.onColorSelected,
    this.title = 'Choose Color',
  }) : super(key: key);

  @override
  State<CustomColorPicker> createState() => _CustomColorPickerState();
}

class _CustomColorPickerState extends State<CustomColorPicker> with TickerProviderStateMixin {
  late Color _selectedColor;
  late TabController _tabController;
  
  // Text controllers for RGBO and Hex values
  late TextEditingController _rgboController;
  late TextEditingController _hexController;
  
  // Color picker state
  Offset _pickerPosition = Offset(0.5, 0.5); // Normalized position (0-1)
  bool _isDragging = false;
  double _hue = 0.0; // 0-360
  double _saturation = 1.0; // 0-1
  double _lightness = 0.5; // 0-1

  // Default colors list
  List<Color> _defaultColors = [
    Colors.amber,
    Colors.blue,
    Colors.green,
    Colors.red,
    Colors.purple,
    Colors.orange,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
    Colors.brown,
    Colors.grey,
    Colors.cyan,
    Colors.lime,
    Colors.deepOrange,
    Colors.lightBlue,
    Colors.deepPurple,
  ];

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.currentColor ?? Colors.amber;
    _tabController = TabController(length: 2, vsync: this);
    
    // Initialize text controllers
    _rgboController = TextEditingController(text: '${_selectedColor.red},${_selectedColor.green},${_selectedColor.blue},255');
    _hexController = TextEditingController(text: _colorToHex(_selectedColor));
    
    // Initialize picker position and HSL values based on current color
    _updatePickerPositionFromColor(_selectedColor);
    _updateHSLFromColor(_selectedColor);
    
    _loadDefaultColors();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _rgboController.dispose();
    _hexController.dispose();
    super.dispose();
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  Color _hexToColor(String hex) {
    try {
      hex = hex.replaceAll('#', '');
      if (hex.length == 6) {
        hex = 'FF$hex'; // Add alpha if not present
      }
      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      return Colors.black;
    }
  }

  Future<void> _loadDefaultColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final defaultColorValues = prefs.getStringList('default_colors') ?? [];
      
      if (defaultColorValues.isNotEmpty) {
        final loadedColors = defaultColorValues
            .map((value) => Color(int.parse(value)))
            .toList();
        setState(() {
          _defaultColors = loadedColors;
        });
      }
    } catch (e) {
      print('Error loading default colors: $e');
    }
  }

  Future<void> _saveDefaultColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final colorValues = _defaultColors.map((c) => c.value.toString()).toList();
      await prefs.setStringList('default_colors', colorValues);
    } catch (e) {
      print('Error saving default colors: $e');
    }
  }

  Future<void> _addToDefaultColors(Color color) async {
    // Check if color already exists in default colors
    final exists = _defaultColors.any((c) => c.value == color.value);
    
    if (!exists) {
      setState(() {
        _defaultColors.insert(0, color); // Add to beginning
        // Keep only last 20 colors to prevent list from growing too large
        if (_defaultColors.length > 20) {
          _defaultColors = _defaultColors.take(20).toList();
        }
      });
      await _saveDefaultColors();
    }
  }

  Future<void> _showDeleteColorDialog(Color color) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero, // Squared corners
        ),
        titlePadding: EdgeInsetsGeometry.zero,
        title: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Delete Color',
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
            Text('Are you sure you want to delete this color from the default colors?'),
            SizedBox(height: 16),
            // Show the color being deleted
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade400, width: 2),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteColorFromDefaults(color);
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteColorFromDefaults(Color color) async {
    setState(() {
      _defaultColors.removeWhere((c) => c.value == color.value);
    });
    await _saveDefaultColors();
  }

  void _updateColorFromRGBOString() {
    try {
      final parts = _rgboController.text.split(',');
      if (parts.length == 4) {
        final red = int.parse(parts[0].trim()).clamp(0, 255);
        final green = int.parse(parts[1].trim()).clamp(0, 255);
        final blue = int.parse(parts[2].trim()).clamp(0, 255);
        final opacity = int.parse(parts[3].trim()).clamp(0, 255);
        
        final newColor = Color.fromARGB(opacity, red, green, blue);
        setState(() {
          _selectedColor = newColor;
        });
        
        // Update picker position
        _updatePickerPositionFromColor(newColor);
        
        // Update hex field
        _hexController.text = _colorToHex(newColor);
      }
    } catch (e) {
      // Invalid input, keep current color
    }
  }

  void _updateColorFromHex() {
    try {
      final newColor = _hexToColor(_hexController.text);
      setState(() {
        _selectedColor = newColor;
      });
      
      // Update picker position
      _updatePickerPositionFromColor(newColor);
      
      // Update RGBO field
      _rgboController.text = '${newColor.red},${newColor.green},${newColor.blue},${(newColor.opacity * 255).round()}';
    } catch (e) {
      // Invalid hex, keep current color
    }
  }

  void _selectColor(Color color) {
    setState(() {
      _selectedColor = color;
    });
    
    // Update picker position
    _updatePickerPositionFromColor(color);
    
    // Update text fields
    _rgboController.text = '${color.red},${color.green},${color.blue},${(color.opacity * 255).round()}';
    _hexController.text = _colorToHex(color);
  }

  void _updatePickerPositionFromColor(Color color) {
    // Convert RGB to HSL to get position
    final hsl = _rgbToHsl(color.red, color.green, color.blue);
    final x = hsl[0] / 360.0; // Hue (0-1)
    final y = 1.0 - hsl[2]; // Lightness (inverted, 0-1)
    _pickerPosition = Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
  }

  void _updateHSLFromColor(Color color) {
    final hsl = _rgbToHsl(color.red, color.green, color.blue);
    _hue = hsl[0];
    _saturation = hsl[1];
    _lightness = hsl[2];
  }

  void _updateColorFromHSL() {
    final newColor = _hslToRgb(_hue, _saturation, _lightness);
    setState(() {
      _selectedColor = newColor;
    });
    
    // Update text fields
    _rgboController.text = '${newColor.red},${newColor.green},${newColor.blue},255';
    _hexController.text = _colorToHex(newColor);
    
    // Update picker position
    _pickerPosition = Offset(_saturation, 1.0 - _lightness);
  }

  List<double> _rgbToHsl(int r, int g, int b) {
    final red = r / 255.0;
    final green = g / 255.0;
    final blue = b / 255.0;

    final max = [red, green, blue].reduce((a, b) => a > b ? a : b);
    final min = [red, green, blue].reduce((a, b) => a < b ? a : b);
    final diff = max - min;

    double hue = 0;
    double saturation = 0;
    double lightness = (max + min) / 2;

    if (diff != 0) {
      saturation = lightness > 0.5 ? diff / (2 - max - min) : diff / (max + min);

      if (max == red) {
        hue = (green - blue) / diff + (green < blue ? 6 : 0);
      } else if (max == green) {
        hue = (blue - red) / diff + 2;
      } else {
        hue = (red - green) / diff + 4;
      }
      hue /= 6;
    }

    return [hue * 360, saturation, lightness];
  }

  Widget _buildCustomColorTab() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Prevent scroll when dragging the color picker
        return _isDragging;
      },
      child: SingleChildScrollView(
        padding: EdgeInsets.all(8),
        child: Column(
          children: [
            // Saturation and Lightness picker
            Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: _buildSaturationLightnessPicker(),
            ),
            SizedBox(height: 12),
            
            // Hue slider with simple line and triangle
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Color Range', style: TextStyle(fontWeight: FontWeight.w500)),
                SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final sliderWidth = constraints.maxWidth;
                    final triangleSize = 16.0;
                    final halfTriangleSize = triangleSize / 2;
                    
                    return Container(
                      height: 30,
                      child: Stack(
                        children: [
                          // Color gradient line
                          Container(
                            height: 4,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              gradient: LinearGradient(
                                colors: [
                                  Colors.red,
                                  Colors.orange,
                                  Colors.yellow,
                                  Colors.green,
                                  Colors.cyan,
                                  Colors.blue,
                                  Colors.purple,
                                  Colors.red,
                                ],
                              ),
                            ),
                          ),
                          // Triangle slider
                          Positioned(
                            left: ((_hue / 360.0) * sliderWidth - halfTriangleSize).clamp(0.0, sliderWidth - triangleSize),
                            child: GestureDetector(
                              onPanStart: (details) {
                                setState(() {
                                  _isDragging = true;
                                });
                              },
                              onPanUpdate: (details) {
                                final RenderBox box = context.findRenderObject() as RenderBox;
                                final localPosition = box.globalToLocal(details.globalPosition);
                                // Calculate position relative to the actual slider width
                                final newHue = (localPosition.dx / sliderWidth).clamp(0.0, 1.0) * 360.0;
                                setState(() {
                                  _hue = newHue;
                                  _updateColorFromHSL();
                                });
                              },
                              onPanEnd: (details) {
                                setState(() {
                                  _isDragging = false;
                                });
                              },
                              onTapDown: (details) {
                                // Do nothing on tap down - just prevent default behavior
                              },
                              child: Container(
                                width: triangleSize,
                                height: triangleSize,
                                child: CustomPaint(
                                  painter: TrianglePainter(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            SizedBox(height: 12),
            
            // RGBO input in single line
            TextField(
              controller: _rgboController,
              decoration: InputDecoration(
                labelText: 'RGBO (R,G,B,O)',
                border: OutlineInputBorder(),
                hintText: '255,0,0,255',
              ),
              onChanged: (_) => _updateColorFromRGBOString(),
            ),
            SizedBox(height: 8),
            
            // Hex input
            TextField(
              controller: _hexController,
              decoration: InputDecoration(
                labelText: 'Hex Color',
                border: OutlineInputBorder(),
                hintText: '#FF0000',
              ),
              onChanged: (_) => _updateColorFromHex(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultColorsTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Default Colors',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _defaultColors.length,
            itemBuilder: (context, index) {
              final color = _defaultColors[index];
              final isSelected = color.value == _selectedColor.value;
              
              return GestureDetector(
                onTap: () => _selectColor(color),
                onLongPress: () => _showDeleteColorDialog(color),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: isSelected 
                        ? Border.all(color: Colors.black, width: 3)
                        : Border.all(color: Colors.grey.shade300, width: 1),
                  ),
                  child: isSelected 
                      ? Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSaturationLightnessPicker() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pickerWidth = constraints.maxWidth;
        final pickerHeight = constraints.maxHeight;
        final circleSize = 24.0;
        final halfCircleSize = circleSize / 2;
        
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white,
                _hslToRgb(_hue, 1.0, 0.5),
              ],
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.0),
                  Colors.black.withOpacity(0.5),
                ],
              ),
            ),
            child: Stack(
              children: [
                // Draggable circle - only responds to direct touch
                Positioned(
                  left: (_pickerPosition.dx * pickerWidth - halfCircleSize).clamp(0.0, pickerWidth - circleSize),
                  top: (_pickerPosition.dy * pickerHeight - halfCircleSize).clamp(0.0, pickerHeight - circleSize),
                  child: GestureDetector(
                    onPanStart: (details) {
                      setState(() {
                        _isDragging = true;
                      });
                    },
                    onPanUpdate: (details) {
                      final RenderBox box = context.findRenderObject() as RenderBox;
                      final localPosition = box.globalToLocal(details.globalPosition);
                      _updateSaturationLightnessFromPosition(localPosition, pickerWidth, pickerHeight);
                    },
                    onPanEnd: (details) {
                      setState(() {
                        _isDragging = false;
                      });
                    },
                    onTapDown: (details) {
                      // Do nothing on tap down - just prevent default behavior
                    },
                    child: Container(
                      width: circleSize,
                      height: circleSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _updateSaturationLightnessFromPosition(Offset localPosition, double pickerWidth, double pickerHeight) {
    // Calculate position relative to the actual picker dimensions
    final x = (localPosition.dx / pickerWidth).clamp(0.0, 1.0);
    final y = (localPosition.dy / pickerHeight).clamp(0.0, 1.0);
    
    setState(() {
      _pickerPosition = Offset(x, y);
      _saturation = x;
      _lightness = 1.0 - y;
    });
    
    _updateColorFromHSL();
  }

  Color _hslToRgb(double h, double s, double l) {
    h = h / 360.0;
    double r, g, b;

    if (s == 0) {
      r = g = b = l; // achromatic
    } else {
      double hue2rgb(double p, double q, double t) {
        if (t < 0) t += 1;
        if (t > 1) t -= 1;
        if (t < 1/6) return p + (q - p) * 6 * t;
        if (t < 1/2) return q;
        if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
        return p;
      }

      double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
      double p = 2 * l - q;
      r = hue2rgb(p, q, h + 1/3);
      g = hue2rgb(p, q, h);
      b = hue2rgb(p, q, h - 1/3);
    }

    return Color.fromARGB(255, (r * 255).round(), (g * 255).round(), (b * 255).round());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero, // Squared corners
      ),
      content: Container(
        width: 500,
        height: 500,
        child: Column(
          children: [
            Row(
              children: [
                // Default tab (first)
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _tabController.index = 0;
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _tabController.index == 0 ? Colors.blue : Colors.grey.shade300,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.color_lens),
                          SizedBox(width: 8),
                          Text('Default', style: TextStyle(
                            fontWeight: _tabController.index == 0 ? FontWeight.bold : FontWeight.normal,
                          )),
                        ],
                      ),
                    ),
                  ),
                ),
                // Custom tab (second)
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _tabController.index = 1;
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _tabController.index == 1 ? Colors.blue : Colors.grey.shade300,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: _selectedColor,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade400, width: 1),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text('Custom', style: TextStyle(
                            fontWeight: _tabController.index == 1 ? FontWeight.bold : FontWeight.normal,
                          )),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: AbsorbPointer(
                absorbing: _isDragging,
                child: IndexedStack(
                  index: _tabController.index,
                  children: [
                    _buildDefaultColorsTab(), // Index 0 - Default tab
                    _buildCustomColorTab(),   // Index 1 - Custom tab
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            _addToDefaultColors(_selectedColor);
            widget.onColorSelected(_selectedColor);
            Navigator.of(context).pop();
          },
          child: Text('OK'),
        ),
      ],
    );
  }
}

class TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(size.width / 2, 0);
    path.lineTo(0, size.height);
    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
