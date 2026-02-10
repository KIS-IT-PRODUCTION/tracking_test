import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web; // Для реєстрації view factory
import 'dart:js_util' as js_util;
import 'dart:async';

// Константи для типів HTML елементів
const String _viewTypeDiv = 'tracked-div-element';
const String _viewTypeInput = 'tracked-input-element';

// Глобальний обсервер навігації
final TrackingNavigationObserver routeObserver = TrackingNavigationObserver();

void main() {
  // Ініціалізуємо трекінг перед запуском
  initWebTracking();
  runApp(const MyApp());
}

// --- ІНІЦІАЛІЗАЦІЯ ---
void initWebTracking() {
  // 1. Реєструємо DIV (для кнопок)
  ui_web.platformViewRegistry.registerViewFactory(_viewTypeDiv, (int viewId, {Object? params}) {
    final id = (params as Map)['id'];
    // Реєструємо елемент в JS "на майбутнє"
    Future.delayed(Duration.zero, () => _callJs('registerElement', [id]));
    
    return html.DivElement()
      ..id = 'proxy-div-$id'
      ..style.width = '100%'
      ..style.height = '100%';
  });

  // 2. Реєструємо INPUT (для текстових полів)
  ui_web.platformViewRegistry.registerViewFactory(_viewTypeInput, (int viewId, {Object? params}) {
    final id = (params as Map)['id'];
    Future.delayed(Duration.zero, () => _callJs('registerElement', [id]));
    
    return html.InputElement()
      ..id = 'proxy-input-$id'
      ..type = 'hidden'; // Прихований, бо ми малюємо свій TextField зверху
  });

  // 3. Запускаємо логіку трекера з затримкою (щоб сторінка встигла прогрузитись)
  Future.delayed(const Duration(milliseconds: 1000), () {
    _callJs('initTracker', []);
  });
}

// --- JS BRIDGE (БЕЗПЕЧНИЙ ВИКЛИК) ---
void _callJs(String method, List<dynamic> args) {
  try {
    if (js_util.hasProperty(html.window, 'flutterBridge')) {
      final bridge = js_util.getProperty(html.window, 'flutterBridge');
      js_util.callMethod(bridge, method, args);
    } else {
      print('JS Bridge not found yet (waiting...)');
    }
  } catch (e) {
    print('JS Bridge Error calling $method: $e');
  }
}

// --- NAVIGATION OBSERVER ---
class TrackingNavigationObserver extends RouteObserver<ModalRoute<dynamic>> {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _handleTransition(previousRoute, route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _handleTransition(route, previousRoute);
  }

  void _handleTransition(Route<dynamic>? from, Route<dynamic>? to) {
    String? fromName = from?.settings.name;
    String? toName = to?.settings.name;

    fromName ??= 'null';
    toName ??= 'unknown';

    // Повідомляємо JS про зміну сторінки
    _callJs('handleNavigation', [fromName, toName]);
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
        // 1. Клік в JS
        _callJs('triggerClick', [
          id, 
          details.globalPosition.dx.toInt(), 
          details.globalPosition.dy.toInt()
        ]);
        
        // 2. Клік у Flutter
        if (onTap != null) {
          onTap!(); 
        }
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0, // Невидимий, але існує в DOM
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
    _callJs('setFocus', [widget.id, _focusNode.hasFocus]);
  }

  void _onControllerChanged() {
    final text = widget.controller.text;
    if (text == _lastText) return; 

    // Використовуємо універсальний метод оновлення (надійніше)
    bool isBackspace = text.length < _lastText.length;
    _callJs('updateInput', [widget.id, text, isBackspace]);
    
    _lastText = text;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Прихований HTML інпут для трекера
        SizedBox(height: 1, width: 1, child: HtmlElementView(viewType: _viewTypeInput, creationParams: {'id': widget.id})),
        
        // Реальний Flutter інпут
        TextField(
          controller: widget.controller, 
          focusNode: _focusNode, 
          decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder()),
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
      // Обмежуємо частоту подій (раз на 100мс)
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

// --- APP & PAGES ---

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracking Final',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: '/',
      navigatorObservers: [routeObserver], // ПІДКЛЮЧЕННЯ OBSERVER
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
                  const SizedBox(height: 20),
                  
                  WebTrackedInput(id: 'login_input_field', label: 'Логін', controller: _loginController),
                  
                  const SizedBox(height: 20),
                  WebTrackedBtn(
                    id: 'login_btn_top', 
                    onTap: () => Navigator.pushNamed(context, '/finish'),
                    child: ElevatedButton(
                      onPressed: null, // Вимкнено, бо WebTrackedBtn обробляє клік
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
                  const Text("Скрольте вниз для тесту...", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 20),
                  
                  ...List.generate(10, (index) {
                    return Container(
                      height: 100, 
                      margin: const EdgeInsets.only(bottom: 10),
                      color: Colors.grey[200],
                      alignment: Alignment.center,
                      child: Text("Блок #$index"),
                    );
                  }),
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
            const Text("Дані відправлені!", style: TextStyle(fontSize: 18)),
            const SizedBox(height: 30),
            WebTrackedBtn(
              id: 'back_btn',
              onTap: () => Navigator.pop(context),
              child: ElevatedButton(
                  onPressed: null, 
                  child: const Text("Назад")
              ),
            ),
          ],
        ),
      ),
    );
  }
}