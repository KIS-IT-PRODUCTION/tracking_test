import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:js_util' as js_util;
import 'dart:async';

const String _viewTypeDiv = 'tracked-div-element';
const String _viewTypeInput = 'tracked-input-element';

// Глобальний обсервер для навігації
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

void main() {
  initWebTracking();
  runApp(const MyApp());
}

void initWebTracking() {
  ui_web.platformViewRegistry.registerViewFactory(_viewTypeDiv, (int viewId, {Object? params}) {
    final id = (params as Map)['id'];
    return html.DivElement()..id = 'flutter-proxy-div-$id'..style.display = 'none';
  });

  ui_web.platformViewRegistry.registerViewFactory(_viewTypeInput, (int viewId, {Object? params}) {
    final id = (params as Map)['id'];
    return html.InputElement()..id = 'flutter-proxy-input-$id'..type = 'hidden';
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

// --- СПЕЦІАЛЬНИЙ КЛАС ДЛЯ "sU" (ВІДСТЕЖЕННЯ СТОРІНОК) ---
class TrackingNavigationObserver extends RouteObserver<ModalRoute<dynamic>> {
  void _sendScreenView(PageRoute<dynamic> route) {
    // Отримуємо назву сторінки (наприклад "/finish")
    final String screenName = route.settings.name ?? 'unknown';
    // Викликаємо JS, щоб оновити "sU"
    _callJs('triggerUrlChange', [screenName]);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PageRoute) _sendScreenView(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute is PageRoute && route is PageRoute) {
      _sendScreenView(previousRoute);
    }
  }
}

// --- ВІДЖЕТИ ---

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
        if (onTap != null) onTap!();
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

  @override
  void initState() {
    super.initState();
    _lastText = widget.controller.text;
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    _callJs('setFocus', [widget.id, _focusNode.hasFocus]);
  }

  void _onTextChanged() {
    final newText = widget.controller.text;
    final isBackspace = newText.length < _lastText.length;
    _callJs('updateInput', [widget.id, newText, isBackspace]);
    _lastText = newText;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(height: 1, width: 1, child: HtmlElementView(viewType: _viewTypeInput, creationParams: {'id': widget.id})),
        TextField(controller: widget.controller, focusNode: _focusNode, decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder())),
      ],
    );
  }
}

// --- ВИПРАВЛЕНИЙ SCROLL TRACKER ("scr") ---
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
      // Частота оновлення 100мс (достатньо для трекера)
      if (now - _lastEventTime > 100) {
        _lastEventTime = now;
        // Передаємо поточну позицію скролу (pixels) у JS
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

// --- UI ---

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracking Complete Fix',
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: '/',
      // ВАЖЛИВО: Додаємо observer для навігації
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
      appBar: AppBar(title: const Text("Крок 1: Вхід")),
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
                  WebTrackedInput(id: 'login_input_field', label: 'Логін', controller: _loginController),
                  const SizedBox(height: 20),
                  WebTrackedBtn(
                    id: 'login_btn_top', 
                    onTap: () => Navigator.pushNamed(context, '/finish'),
                    child: ElevatedButton(onPressed: (){}, child: const Text("Увійти")),
                  ),
                  const SizedBox(height: 1000), // Довгий скрол
                  WebTrackedBtn(
                    id: 'scroll_btn', 
                    onTap: (){}, 
                    child: ElevatedButton(onPressed: (){}, child: const Text("Кнопка внизу"))
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
      body: Center(
        child: WebTrackedBtn(
          id: 'back_btn',
          onTap: () => Navigator.pop(context),
          child: ElevatedButton(onPressed: (){}, child: const Text("Назад")),
        ),
      ),
    );
  }
}