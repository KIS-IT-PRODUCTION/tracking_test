import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:js_util' as js_util;
import 'dart:async';

const String _viewTypeDiv = 'tracked-div-element';
const String _viewTypeInput = 'tracked-input-element';

// Створюємо глобальний обсервер
final TrackingNavigationObserver routeObserver = TrackingNavigationObserver();

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

// --- ОНОВЛЕНИЙ NAVIGATION OBSERVER ---
class TrackingNavigationObserver extends RouteObserver<ModalRoute<dynamic>> {
  
  // Викликається, коли ми переходимо НА нову сторінку (Push)
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _handleTransition(previousRoute, route);
  }

  // Викликається, коли ми повертаємось НАЗАД (Pop)
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    // При Pop: route - це та, що закривається, previousRoute - та, куди повертаємось
    _handleTransition(route, previousRoute);
  }

  void _handleTransition(Route<dynamic>? from, Route<dynamic>? to) {
    String? fromName = from?.settings.name;
    String? toName = to?.settings.name;

    // Якщо ми тільки запустили додаток, 'from' може бути null
    fromName ??= 'null';
    toName ??= 'unknown';

    // Викликаємо JS функцію, яка збереже дані 'from' і запустить 'to'
    _callJs('handleNavigation', [fromName, toName]);
  }
}

// --- РЕШТА КОДУ (КНОПКИ ТА ІНПУТИ) БЕЗ ЗМІН ---

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
        // 1. Спочатку відправляємо клік у JS (це відбувається миттєво)
        _callJs('triggerClick', [
          id, 
          details.globalPosition.dx.toInt(), 
          details.globalPosition.dy.toInt()
        ]);
        
        // 2. ОДРАЗУ виконуємо дію Flutter (навігацію)
        // Прибираємо Future.delayed, бо воно викликає краш при швидких переходах
        if (onTap != null) {
          onTap!(); 
        }
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0, 
              child: HtmlElementView(viewType: _viewTypeDiv, creationParams: {'id': id})
            )
          ),
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
            if (!_focusNode.hasFocus) {
               FocusScope.of(context).requestFocus(_focusNode);
            }
          },
        ),
      ],
    );
  }
}

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracking Final',
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: '/',
      navigatorObservers: [routeObserver], // Підключили наш Observer
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
                  WebTrackedInput(id: 'login_input_field', label: 'Логін', controller: _loginController),
                  const SizedBox(height: 20),
                  WebTrackedBtn(
                    id: 'login_btn_top', 
                    onTap: () => Navigator.pushNamed(context, '/finish'),
                    child: ElevatedButton(
                      onPressed: null, 
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
                  const Text("Скрольте вниз...", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 20),
                  ...List.generate(30, (index) {
                    return Container(
                      height: 100, 
                      margin: const EdgeInsets.only(bottom: 10),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: index % 2 == 0 ? Colors.blue[50] : Colors.grey[100],
                        border: Border.all(color: Colors.blue.withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text("Блок #$index\n(${(index + 1) * 100} px)", textAlign: TextAlign.center),
                    );
                  }),
                  WebTrackedBtn(
                    id: 'scroll_btn_bottom', 
                    onTap: (){}, 
                    child: ElevatedButton(
                      onPressed: null, 
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      child: const Text("ФІНІШ (НИЗ)"),
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
            const Text("Сторінка 2: Дані з 1-ї відправлені!", style: TextStyle(fontSize: 18)),
            const SizedBox(height: 30),
            WebTrackedBtn(
              id: 'back_btn',
              onTap: () => Navigator.pop(context),
              child: ElevatedButton(onPressed: null, child: const Text("Назад (Перевірка Pop)")),
            ),
          ],
        ),
      ),
    );
  }
}