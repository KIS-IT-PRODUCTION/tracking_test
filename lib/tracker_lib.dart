import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

// 1. Імпортуємо Flutter стандартно, але ХОВАЄМО ті віджети, які ми переписуємо.
import 'package:flutter/material.dart' hide TextField, ElevatedButton, SingleChildScrollView;

// 2. Імпортуємо Flutter ще раз з префіксом 'material' для доступу до оригіналів.
import 'package:flutter/material.dart' as material;

// 3. Експортуємо все з Flutter, крім наших підмін.
export 'package:flutter/material.dart' hide TextField, ElevatedButton, SingleChildScrollView;

/// ==========================================================
/// TRACKER LIBRARY (WRAPPER MODE)
/// ==========================================================

/// --- 1. ІНІЦІАЛІЗАЦІЯ ---
void initTracking() {
  Future.delayed(const Duration(milliseconds: 1000), () {
    _callJs('initTracker', []);
  });
}

/// --- 2. JS INTEROP ---
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

/// --- 3. ROUTE OBSERVER ---
class TrackerRouteObserver extends RouteObserver<ModalRoute<dynamic>> {
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

/// --- 4. ElevatedButton (WRAPPER) ---
class ElevatedButton extends StatefulWidget {
  /// ID для трекера. Якщо null -> трекінг вимкнено для цієї кнопки.
  final String? dataTs1Id; 
  
  final Widget child;
  final VoidCallback onPressed;
  final ButtonStyle? style;

  const ElevatedButton({
    super.key, 
    this.dataTs1Id, // <-- ТЕПЕР НЕОБОВ'ЯЗКОВИЙ
    required this.child, 
    required this.onPressed,
    this.style,
  });

  static ButtonStyle styleFrom({
    Color? backgroundColor,
    Color? foregroundColor,
    Size? minimumSize,
    OutlinedBorder? shape,
  }) {
    return material.ElevatedButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      minimumSize: minimumSize,
      shape: shape,
    );
  }

  @override
  State<ElevatedButton> createState() => _ElevatedButtonState();
}

class _ElevatedButtonState extends State<ElevatedButton> {
  double _lastX = 0;
  double _lastY = 0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _lastX = event.position.dx;
        _lastY = event.position.dy;
      },
      child: material.ElevatedButton(
        style: widget.style,
        onPressed: () {
          // Відправляємо дані, ТІЛЬКИ якщо ID вказано
          if (widget.dataTs1Id != null) {
             _callJs('triggerClick', [widget.dataTs1Id, _lastX.toInt(), _lastY.toInt()]);
          }
          widget.onPressed();
        },
        child: widget.child,
      ),
    );
  }
}

/// --- 5. TextField (WRAPPER) ---
class TextField extends StatefulWidget {
  /// ID для трекера. Якщо null -> трекінг вимкнено для цього поля.
  final String? dataTs1Id; 
  
  final TextEditingController? controller;
  final InputDecoration? decoration;

  const TextField({
    super.key, 
    this.dataTs1Id, // <-- ТЕПЕР НЕОБОВ'ЯЗКОВИЙ
    this.controller, 
    this.decoration
  });

  @override
  State<TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<TextField> {
  final FocusNode _focusNode = FocusNode();
  late TextEditingController _controller;
  String _lastSentText = ""; 
  Timer? _debounceTimer; 

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _lastSentText = _controller.text;
    
    // Додаємо слухачі тільки якщо трекінг увімкнено (оптимізація),
    // АБО додаємо завжди, але перевіряємо ID всередині методів.
    // Безпечніше перевіряти всередині, щоб можна було змінювати ID динамічно.
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onTextChanged() {
    // Якщо ID немає - виходимо одразу, не запускаємо таймери
    if (widget.dataTs1Id == null) return;

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      _processTextChange();
    });
  }

  void _processTextChange() {
    // Подвійна перевірка
    if (widget.dataTs1Id == null) return;

    final currentText = _controller.text;
    if (currentText == _lastSentText) return;

    final selection = _controller.selection;
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
      _callJs('typeChar', [widget.dataTs1Id, currentText, charToSimulate, cursorPos, cursorPos]);
    } 
    else {
      _callJs('pressBackspace', [widget.dataTs1Id, currentText, cursorPos, cursorPos]);
    }
    _lastSentText = currentText;
  }

  void _onFocusChanged() {
    if (widget.dataTs1Id == null) return;
    _callJs('setFocus', [widget.dataTs1Id, _focusNode.hasFocus]);
  }

  @override
  Widget build(BuildContext context) {
    return material.TextField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: widget.decoration ?? const InputDecoration(border: OutlineInputBorder()),
    );
  }
}

/// --- 6. SingleChildScrollView (WRAPPER) ---
class SingleChildScrollView extends StatefulWidget {
  final Widget? child;
  final Axis scrollDirection;
  final bool reverse;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final bool? primary;
  final ScrollPhysics? physics;
  
  const SingleChildScrollView({
    super.key, 
    this.child,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.padding,
    this.controller,
    this.primary,
    this.physics,
  });

  @override
  State<SingleChildScrollView> createState() => _SingleChildScrollViewState();
}

class _SingleChildScrollViewState extends State<SingleChildScrollView> {
  int _lastReportTime = 0;

  @override
  Widget build(BuildContext context) {
    // Скрол ми трекаємо завжди, якщо використовується цей віджет.
    // Якщо треба вимкнути трекінг скролу - клієнт може використати
    // ListView або оригінальний SingleChildScrollView (через аліас).
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
      child: material.SingleChildScrollView(
        scrollDirection: widget.scrollDirection,
        reverse: widget.reverse,
        padding: widget.padding,
        controller: widget.controller,
        primary: widget.primary,
        physics: widget.physics,
        child: widget.child,
      ),
    );
  }
}