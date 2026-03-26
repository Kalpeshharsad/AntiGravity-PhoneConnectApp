import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const AntigravityMobileApp());
}

class AntigravityMobileApp extends StatelessWidget {
  const AntigravityMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Antigravity Mobile',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blueAccent,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E293B),
          elevation: 0,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  WebSocketChannel? _channel;
  bool _isConnected = false;
  Uint8List? _lastScreenshot;
  final TextEditingController _msgController = TextEditingController();
  Timer? _refreshTimer;
  Size _remoteViewportSize = const Size(1440, 900);
  String _debugStatus = 'Connect to start';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _urlController.text = prefs.getString('server_url') ?? '';
    _passwordController.text = prefs.getString('server_password') ?? '';
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', _urlController.text);
    await prefs.setString('server_password', _passwordController.text);
  }

  void _connect() {
    if (_urlController.text.isEmpty) return;
    
    _saveSettings();
    final url = _urlController.text.replaceFirst('http', 'ws');
    
    try {
      setState(() => _debugStatus = 'Opening socket...');
      _channel = WebSocketChannel.connect(Uri.parse(url));
      setState(() => _isConnected = true);
      
      _channel!.stream.listen((message) {
        try {
          final data = jsonDecode(message);
          if (data['type'] == 'screenshot') {
            setState(() {
              _lastScreenshot = base64Decode(data['data']);
              _debugStatus = 'Snapshot received (${_lastScreenshot!.length} bytes)';
              if (data['viewport'] != null) {
                _remoteViewportSize = Size(
                  data['viewport']['width'].toDouble(),
                  data['viewport']['height'].toDouble(),
                );
              }
            });
          } else if (data['type'] == 'error') {
            setState(() => _debugStatus = 'Server Error: ${data['message']}');
            _showError(data['message']);
          }
        } catch (e) {
          setState(() => _debugStatus = 'Parse Error: $e');
        }
      }, onDone: () {
        setState(() {
          _isConnected = false;
          _debugStatus = 'Connection closed';
        });
        _refreshTimer?.cancel();
      }, onError: (err) {
        setState(() {
          _isConnected = false;
          _debugStatus = 'Socket Error: $err';
        });
        _showError(err.toString());
      });

      // Start periodic refresh for smoothness
      _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (_isConnected) {
          _sendAction({'type': 'get_screenshot'});
        }
      });
    } catch (e) {
      setState(() => _debugStatus = 'Connect Exception: $e');
      _showError(e.toString());
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _sendAction(dynamic action) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(action));
    }
  }

  void _onTapDown(TapDownDetails details, BoxConstraints constraints) {
    if (_lastScreenshot == null) return;

    final Size containerSize = Size(constraints.maxWidth, constraints.maxHeight);
    final Size imageSize = _remoteViewportSize;

    // Calculate the actual rect where the image is displayed (BoxFit.contain)
    double aspect = imageSize.width / imageSize.height;
    double containerAspect = containerSize.width / containerSize.height;

    double displayWidth, displayHeight, offsetX, offsetY;
    if (aspect > containerAspect) {
      displayWidth = containerSize.width;
      displayHeight = displayWidth / aspect;
      offsetX = 0;
      offsetY = (containerSize.height - displayHeight) / 2;
    } else {
      displayHeight = containerSize.height;
      displayWidth = displayHeight * aspect;
      offsetX = (containerSize.width - displayWidth) / 2;
      offsetY = 0;
    }

    // Convert local tap to image-relative tap
    double relativeX = details.localPosition.dx - offsetX;
    double relativeY = details.localPosition.dy - offsetY;

    // Check if tap was inside the image
    if (relativeX < 0 || relativeX > displayWidth || relativeY < 0 || relativeY > displayHeight) {
      return;
    }

    // Map to remote desktop coordinates
    double desktopX = (relativeX / displayWidth) * imageSize.width;
    double desktopY = (relativeY / displayHeight) * imageSize.height;

    _sendAction({
      'type': 'remote_touch',
      'x': desktopX,
      'y': desktopY,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ANTIGRAVITY'),
        actions: [
          IconButton(
            icon: Icon(_isConnected ? Icons.link : Icons.link_off),
            color: _isConnected ? Colors.green : Colors.red,
            onPressed: () {
              if (_isConnected) {
                _channel?.sink.close();
              } else {
                _connect();
              }
            },
          )
        ],
      ),
      body: Column(
        children: [
          if (!_isConnected)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                color: const Color(0xFF1E293B),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _urlController,
                        decoration: const InputDecoration(labelText: 'Server URL (ex: http://192.168.1.5:3000)'),
                      ),
                      TextField(
                        controller: _passwordController,
                        decoration: const InputDecoration(labelText: 'Password'),
                        obscureText: true,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _connect,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                        child: const Text('Connect to Antigravity'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: Container(
              color: Colors.black,
              child: _lastScreenshot == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(color: Colors.blueAccent),
                          const SizedBox(height: 20),
                          Text(_debugStatus, 
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 14)
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return GestureDetector(
                          onTapDown: (details) => _onTapDown(details, constraints),
                          child: Image.memory(
                            _lastScreenshot!,
                            gaplessPlayback: true,
                            fit: BoxFit.contain,
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                          ),
                        );
                      },
                    ),
            ),
          ),
          // Status Bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: const Color(0xFF0F172A),
            child: Text(_debugStatus, 
              style: const TextStyle(fontSize: 10, color: Colors.white38, fontStyle: FontStyle.italic)
            ),
          ),
          if (_isConnected)
            Container(
              padding: const EdgeInsets.all(8.0),
              color: const Color(0xFF1E293B),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (val) {
                        if (val.isNotEmpty) {
                          _sendAction({'type': 'inject_message', 'text': val});
                          _msgController.clear();
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.blueAccent),
                    onPressed: () {
                      if (_msgController.text.isNotEmpty) {
                        _sendAction({'type': 'inject_message', 'text': _msgController.text});
                        _msgController.clear();
                      }
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
