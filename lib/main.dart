import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'package:flutter_web_plugins/url_strategy.dart'; 

void main() {
  usePathUrlStrategy(); 
  runApp(const MyApp());
  
  // Запускаємо ініціалізацію з невеликою затримкою
  Future.delayed(const Duration(milliseconds: 1000), () {
    _callJs('initTracker', []);
  });
}

// --- JS INTEROP ---
void _callJs(String method, List<dynamic> args) {
  try {
    if (js_util.hasProperty(html.window, 'flutterBridge')) {
      final bridge = js_util.getProperty(html.window, 'flutterBridge');
      js_util.callMethod(bridge, method, args);
    } else {
      print('JS Bridge MISSING: $method');
    }
  } catch (e) {
    print('JS Error in $method: $e');
  }
}

// --- APP ---
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracking Test',
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const TestPage(),
        '/finish': (context) => const FinishPage(),
      },
      navigatorObservers: [MyRouteObserver()],
    );
  }
}

// --- ROUTE OBSERVER ---
class MyRouteObserver extends RouteObserver<ModalRoute<dynamic>> {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route.settings.name != null) {
      _callJs('handleNavigation', [
        previousRoute?.settings.name ?? 'null', 
        route.settings.name
      ]);
    }
  }
}

// --- BUTTON ---
class TrackedElevatedButton extends StatefulWidget {
  final String id;
  final String label;
  final VoidCallback onPressed;

  const TrackedElevatedButton({
    super.key, 
    required this.id, 
    required this.label, 
    required this.onPressed
  });

  @override
  State<TrackedElevatedButton> createState() => _TrackedElevatedButtonState();
}

class _TrackedElevatedButtonState extends State<TrackedElevatedButton> {
  double _lastX = 0;
  double _lastY = 0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _lastX = event.position.dx;
        _lastY = event.position.dy;
      },
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
        ),
        onPressed: () {
          _callJs('triggerClick', [widget.id, _lastX.toInt(), _lastY.toInt()]);
          widget.onPressed();
        },
        child: Text(widget.label),
      ),
    );
  }
}

// --- INPUT (З DEBOUNCE) ---
class TrackedInput extends StatefulWidget {
  final String id;
  final TextEditingController controller;
  final String label;

  const TrackedInput({super.key, required this.id, required this.controller, required this.label});

  @override
  State<TrackedInput> createState() => _TrackedInputState();
}

class _TrackedInputState extends State<TrackedInput> {
  final FocusNode _focusNode = FocusNode();
  String _lastSentText = ""; 
  Timer? _debounceTimer; 

  @override
  void initState() {
    super.initState();
    _lastSentText = widget.controller.text;
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      _processTextChange();
    });
  }

  void _processTextChange() {
    final currentText = widget.controller.text;
    if (currentText == _lastSentText) return;

    final selection = widget.controller.selection;
    int cursorPos = selection.baseOffset;
    
    if (cursorPos < 0) cursorPos = currentText.length;
    if (cursorPos > currentText.length) cursorPos = currentText.length;

    if (currentText.length >= _lastSentText.length) {
      String charToSimulate = " ";
      if (currentText.isNotEmpty) {
         if (cursorPos > 0) {
           charToSimulate = currentText[cursorPos - 1];
         } else {
           charToSimulate = currentText[currentText.length - 1];
         }
      }
      _callJs('typeChar', [widget.id, currentText, charToSimulate, cursorPos, cursorPos]);
    } 
    else {
      _callJs('pressBackspace', [widget.id, currentText, cursorPos, cursorPos]);
    }
    
    _lastSentText = currentText;

    if (!_focusNode.hasFocus && context.mounted) {
       // _focusNode.requestFocus(); 
    }
  }

  void _onFocusChanged() {
    _callJs('setFocus', [widget.id, _focusNode.hasFocus]);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      decoration: InputDecoration(
        labelText: widget.label, 
        border: const OutlineInputBorder()
      ),
    );
  }
}

// --- SCROLL TRACKER ---
class ScrollTracker extends StatefulWidget {
  final Widget child;
  const ScrollTracker({super.key, required this.child});

  @override
  State<ScrollTracker> createState() => _ScrollTrackerState();
}

class _ScrollTrackerState extends State<ScrollTracker> {
  int _lastReportTime = 0;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final now = DateTime.now().millisecondsSinceEpoch;

        if (notification is ScrollEndNotification) {
           _callJs('triggerScroll', [notification.metrics.pixels.toInt()]);
           return false;
        }

        if (notification is ScrollUpdateNotification) {
          if (now - _lastReportTime > 100) { 
            _lastReportTime = now;
            _callJs('triggerScroll', [notification.metrics.pixels.toInt()]);
          }
        }
        return false;
      },
      child: widget.child,
    );
  }
}

// --- PAGE 1: TEST FORM ---
class TestPage extends StatefulWidget {
  const TestPage({super.key});
  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  final _ctrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Вхід в систему")),
      body: ScrollTracker(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 50),
                TrackedInput(id: 'login_field', controller: _ctrl, label: 'Логін'),
                const SizedBox(height: 20),
                TrackedElevatedButton(
                  id: 'submit_btn',
                  label: 'Увійти (Finish)',
                  onPressed: () {
                    Navigator.pushNamed(context, '/finish');
                  },
                ),
                
                // --- ЗМІНЕНО: ЗБІЛЬШЕНО ВИСОТУ ДЛЯ ТЕСТУВАННЯ СКРОЛУ ---
                const SizedBox(height: 5000), 
                // -----------------------------------------------------
                
                const Text("Footer"),
                const SizedBox(height: 50), 
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- PAGE 2: FINISH ---
class FinishPage extends StatelessWidget {
  const FinishPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Результат")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 100),
            const SizedBox(height: 20),
            const Text("Успішно!", style: TextStyle(fontSize: 24)),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Назад"),
            )
          ],
        ),
      ),
    );
  }
}