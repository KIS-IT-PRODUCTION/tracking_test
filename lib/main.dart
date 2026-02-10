import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web; // Використовуємо ui_web для Flutter 3.10+
import 'dart:js_util' as js_util;
import 'dart:async';

// Константи для типів HTML елементів
const String _viewTypeDiv = 'tracked-div-element';
const String _viewTypeInput = 'tracked-input-element';

// Глобальний обсервер навігації
final TrackingNavigationObserver routeObserver = TrackingNavigationObserver();

void main() {
  // Ініціалізуємо трекінг
  initWebTracking();
  runApp(const MyApp());
}

// --- ІНІЦІАЛІЗАЦІЯ ---
void initWebTracking() {
  // 1. Реєструємо DIV (для кнопок)
  ui_web.platformViewRegistry.registerViewFactory(_viewTypeDiv, (int viewId, {Object? params}) {
    final id = (params as Map)['id'];
    
    // Повідомляємо JS про цей елемент
    Future.delayed(Duration.zero, () => _callJs('registerElement', [id]));
    
    final element = html.DivElement()
      ..id = 'proxy-div-$id' // Унікальний ID для Flutter DOM
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none';
      
    return element;
  });

  // 2. Реєструємо INPUT (для текстових полів)
  ui_web.platformViewRegistry.registerViewFactory(_viewTypeInput, (int viewId, {Object? params}) {
    final id = (params as Map)['id'];
    
    Future.delayed(Duration.zero, () => _callJs('registerElement', [id]));
    
    final element = html.InputElement()
      ..id = 'proxy-input-$id'
      ..type = 'hidden' // Прихований
      ..style.width = '100%'  // ВАЖЛИВО: Заповнює батьківський SizedBox
      ..style.height = '100%' // ВАЖЛИВО: Заповнює батьківський SizedBox
      ..style.border = 'none';
      
    return element;
  });

  // 3. Запускаємо логіку трекера з невеликою затримкою
  Future.delayed(const Duration(milliseconds: 500), () {
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
      print('JS Bridge: Waiting for initialization...');
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

    // Flutter іноді дає null для початкового маршруту, замінюємо на рядки
    fromName ??= 'null';
    toName ??= (toName == '/' ? 'home' : toName) ?? 'unknown';

    // Повідомляємо JS про зміну сторінки
    Future.microtask(() => _callJs('handleNavigation', [fromName, toName]));
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
      behavior: HitTestBehavior.translucent, // Ловити кліки навіть на прозорих зонах
      onTapUp: (details) {
        // 1. Передаємо координати кліку в JS
        _callJs('triggerClick', [
          id, 
          details.globalPosition.dx.toInt(), 
          details.globalPosition.dy.toInt()
        ]);
        
        // 2. Виконуємо дію у Flutter
        onTap?.call();
      },
      child: Stack(
        children: [
          // "Привид" елемента для DOM. 
          // Positioned.fill гарантує, що він має розмір, тому не буде помилки "Height not set"
          Positioned.fill(
            child: Opacity(
              opacity: 0.0, 
              child: HtmlElementView(
                viewType: _viewTypeDiv, 
                creationParams: {'id': id},
              ),
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

    bool isBackspace = text.length < _lastText.length;
    _callJs('updateInput', [widget.id, text, isBackspace]);
    
    _lastText = text;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ВИПРАВЛЕННЯ ПОМИЛКИ: 
        // Використовуємо SizedBox з фіксованим розміром (1x1 піксель).
        // Оскільки у factory ми задали width: 100%, height: 100%, 
        // елемент займе цей 1 піксель і не буде "нескінченним" для браузера.
        SizedBox(
          width: 1, 
          height: 1, 
          child: HtmlElementView(
            viewType: _viewTypeInput, 
            creationParams: {'id': widget.id}
          )
        ),
        
        TextField(
          controller: widget.controller, 
          focusNode: _focusNode, 
          decoration: InputDecoration(
            labelText: widget.label, 
            border: const OutlineInputBorder()
          ),
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
    // Реагуємо тільки на зміну позиції
    if (notification is ScrollUpdateNotification) {
      final now = DateTime.now().millisecondsSinceEpoch;
      // Троттлінг: відправляти не частіше ніж раз на 100мс
      if (now - _lastEventTime > 100) {
        _lastEventTime = now;
        _callJs('triggerScroll', [notification.metrics.pixels.toInt()]);
      }
    }
    return false; // Дозволити події спливати далі
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
      navigatorObservers: [routeObserver], // Підключаємо observer
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
  void dispose() {
    _loginController.dispose(); // Очистка пам'яті
    super.dispose();
  }

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
                  
                  WebTrackedInput(
                    id: 'login_input_field', 
                    label: 'Логін', 
                    controller: _loginController
                  ),
                  
                  const SizedBox(height: 20),
                  
                  WebTrackedBtn(
                    id: 'login_btn_top', 
                    onTap: () {
                      print("Flutter: Button Clicked");
                      Navigator.pushNamed(context, '/finish');
                    },
                    child: ElevatedButton(
                      // ВАЖЛИВО: onPressed null, щоб WebTrackedBtn перехопив жест
                      onPressed: null, 
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        disabledBackgroundColor: Colors.blue, // Робимо вигляд, що активна
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
                  onPressed: null, // Перехоплення через WebTrackedBtn
                  style: ElevatedButton.styleFrom(
                    disabledBackgroundColor: Colors.green,
                    disabledForegroundColor: Colors.white,
                  ),
                  child: const Text("Назад")
              ),
            ),
          ],
        ),
      ),
    );
  }
}