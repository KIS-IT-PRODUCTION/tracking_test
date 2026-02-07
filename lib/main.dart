import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:js_util' as js_util;
import 'dart:async';

const String _viewTypeDiv = 'tracked-div-element';
const String _viewTypeInput = 'tracked-input-element';

final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

void main() {
  initWebTracking();
  runApp(const MyApp());
}

void initWebTracking() {
  ui_web.platformViewRegistry.registerViewFactory(_viewTypeDiv, (int viewId, {Object? params}) {
    return html.DivElement()..id = 'flutter-proxy-div-${(params as Map)['id']}'..style.display = 'none';
  });

  ui_web.platformViewRegistry.registerViewFactory(_viewTypeInput, (int viewId, {Object? params}) {
    return html.InputElement()..id = 'flutter-proxy-input-${(params as Map)['id']}'..type = 'hidden';
  });

  Future.delayed(const Duration(seconds: 1), () {
    _callJs('initTracker', []);
  });
}

void _callJs(String method, List<dynamic> args) {
  try {
    if (js_util.hasProperty(html.window, 'flutterBridge')) {
      final bridge = js_util.getProperty(html.window, 'flutterBridge');
      js_util.callMethod(bridge, method, args);
    }
  } catch (e) {
    print('JS Bridge Error: $e');
  }
}

// --- NAVIGATION ---
class TrackingNavigationObserver extends RouteObserver<ModalRoute<dynamic>> {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route.settings.name != null) _callJs('triggerUrlChange', [route.settings.name]);
  }
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute?.settings.name != null) _callJs('triggerUrlChange', [previousRoute!.settings.name]);
  }
}

// --- BUTTON ---
class WebTrackedBtn extends StatelessWidget {
  final String id;
  final Widget child;
  final VoidCallback? onTap;

  const WebTrackedBtn({super.key, required this.id, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) {
        _callJs('triggerClick', [id, details.globalPosition.dx.toInt(), details.globalPosition.dy.toInt()]);
        if (onTap != null) {
          Future.delayed(const Duration(milliseconds: 100), () {
            onTap!();
          });
        }
      },
      child: Stack(
        children: [
          Positioned.fill(child: Opacity(opacity: 0, child: HtmlElementView(viewType: _viewTypeDiv, creationParams: {'id': id}))),
          child,
        ],
      ),
    );
  }
}

// --- INPUT (CORRECT DATA SENDING) ---
class WebTrackedInput extends StatefulWidget {
  final String id;
  final TextEditingController controller;
  final String label;

  const WebTrackedInput({super.key, required this.id, required this.controller, required this.label});

  @override
  State<WebTrackedInput> createState() => _WebTrackedInputState();
}

class _WebTrackedInputState extends State<WebTrackedInput> {
  final FocusNode _focusNode = FocusNode();
  String _lastText = "";
  // Додаємо трекінг стану фокусу, щоб уникнути дублікатів
  bool _wasFocused = false; 

  @override
  void initState() {
    super.initState();
    _lastText = widget.controller.text;
    widget.controller.addListener(_onControllerChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    // Відправляємо подію тільки якщо стан реально змінився
    if (_focusNode.hasFocus != _wasFocused) {
      _wasFocused = _focusNode.hasFocus;
      _callJs('setFocus', [widget.id, _wasFocused]);
    }
  }

  void _onControllerChanged() {
    final text = widget.controller.text;
    if (text == _lastText) return; 

    final selection = widget.controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;

    if (text.length < _lastText.length) {
      _callJs('pressBackspace', [widget.id, text, start, end]);
    } else {
       String newChar = "";
       if (text.isNotEmpty && start > 0) {
          newChar = text.substring(start - 1, start);
       } else if (text.isNotEmpty) {
          newChar = text.substring(text.length - 1);
       }
       _callJs('typeChar', [widget.id, text, newChar, start, end]);
    }
    _lastText = text;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(height: 1, width: 1, child: HtmlElementView(viewType: _viewTypeInput, creationParams: {'id': widget.id})),
        TextField(
          controller: widget.controller, 
          focusNode: _focusNode, 
          decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder()),
          onTap: () {
            // Гарантуємо, що фокус встановлено
            if (!_focusNode.hasFocus) {
               FocusScope.of(context).requestFocus(_focusNode);
            }
          },
        ),
      ],
    );
  }
}

// --- SCROLL TRACKER ---
class WebScrollTracker extends StatefulWidget {
  final Widget child;
  const WebScrollTracker({super.key, required this.child});

  @override
  State<WebScrollTracker> createState() => _WebScrollTrackerState();
}

class _WebScrollTrackerState extends State<WebScrollTracker> {
  int _lastEventTime = 0;
  
  bool _handleScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastEventTime > 100) {
        _lastEventTime = now;
        _callJs('triggerScroll', [notification.metrics.pixels.toInt()]);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScroll,
      child: widget.child,
    );
  }
}

// --- APP SHELL ---
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracking Final Fix',
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: '/',
      navigatorObservers: [TrackingNavigationObserver()], 
      routes: {
        '/': (context) => const TestPage(),
        '/finish': (context) => const FinishPage(),
      },
    );
  }
}
class TestPage extends StatefulWidget {
  const TestPage({super.key});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  final TextEditingController _loginController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Крок 1: Вхід (Довга сторінка)")),
      body: WebScrollTracker(
        child: SingleChildScrollView(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  const Icon(Icons.login, size: 80, color: Colors.blue),
                  
                  WebTrackedInput(
                    id: 'login_input_field', 
                    label: 'Логін', 
                    controller: _loginController
                  ),
                  
                  const SizedBox(height: 20),
                  
                  WebTrackedBtn(
                    id: 'login_btn_top', 
                    onTap: () => Navigator.pushNamed(context, '/finish'),
                    child: ElevatedButton(
                      onPressed: null, // null, бо обробляємо через WebTrackedBtn
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        disabledBackgroundColor: Colors.blue,
                        disabledForegroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: const Text("Увійти"),
                    ),
                  ),

                  const SizedBox(height: 50),
                  const Text("Починаємо скролити вниз...", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 20),

                  // --- ГЕНЕРАТОР КОНТЕНТУ ДЛЯ СКРОЛУ (50 блоків) ---
                  ...List.generate(50, (index) {
                    return Container(
                      height: 100, // Кожен блок 100 пікселів
                      margin: const EdgeInsets.only(bottom: 10),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: index % 2 == 0 ? Colors.blue[50] : Colors.grey[100],
                        border: Border.all(color: Colors.blue.withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "Тестовий блок контенту #$index\n(Скрол: ${(index + 1) * 100} px)",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    );
                  }),

                  const SizedBox(height: 30),
                  
                  WebTrackedBtn(
                    id: 'scroll_btn_bottom', 
                    onTap: (){
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Клікнуто в самому низу!"))
                      );
                    }, 
                    child: ElevatedButton(
                      onPressed: null, 
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green, 
                        disabledBackgroundColor: Colors.green,
                        disabledForegroundColor: Colors.white
                      ),
                      child: const Text("ФІНІШНА КНОПКА (НИЗ)"),
                    )
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FinishPage extends StatelessWidget {
  const FinishPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Крок 2: Успіх")),
      backgroundColor: Colors.green[50],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 100, color: Colors.green),
            const SizedBox(height: 20),
            const Text("Ви успішно увійшли!", style: TextStyle(fontSize: 24)),
            const SizedBox(height: 30),
            WebTrackedBtn(
              id: 'back_btn',
              onTap: () => Navigator.pop(context),
              child: ElevatedButton(onPressed: null, child: const Text("Назад")),
            ),
          ],
        ),
      ),
    );
  }
}