import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:js_util' as js_util;
import 'dart:async';

// --- КОНСТАНТИ ---
const String _viewTypeDiv = 'tracked-div-element';
const String _viewTypeInput = 'tracked-input-element';

/// Ініціалізація (Викликати в main)
void initWebTracking() {
  // 1. ЗАПУСК JS-ЧАСТИНИ
  // Чекаємо 1.5 секунди, щоб Flutter повністю завантажився і очистив Body.
  // Потім ми викликаємо JS, який відновить інпути і завантажить трекер.
  Future.delayed(const Duration(milliseconds: 1500), () {
    _callJs('initTracker', []);
  });

  // 2. Реєстрація елементів (Кнопок)
  ui_web.platformViewRegistry.registerViewFactory(_viewTypeDiv, (int viewId, {Object? params}) {
    final id = (params as Map)['id'];
    
    Future.delayed(Duration.zero, () => _callJs('registerElement', [id]));
      
    return html.DivElement()
      ..id = 'proxy-$id' // Унікальний ID для Flutter
      ..style.width = '100%'
      ..style.height = '100%';
  });

  // 3. Реєстрація елементів (Інпутів)
  ui_web.platformViewRegistry.registerViewFactory(_viewTypeInput, (int viewId, {Object? params}) {
    final id = (params as Map)['id'];
    Future.delayed(Duration.zero, () => _callJs('registerElement', [id]));
    return html.InputElement()
      ..id = 'proxy-input-$id'
      ..type = 'text';
  });
}

// --- JS HELPER ---
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

/// Віджет кнопки
class WebTrackedBtn extends StatelessWidget {
  final String id;
  final Widget child;
  final VoidCallback? onTap;

  const WebTrackedBtn({super.key, required this.id, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: (details) {
        // Передаємо координати кліку
        _callJs('triggerClick', [
          id, 
          details.globalPosition.dx.toInt(), 
          details.globalPosition.dy.toInt()
        ]);
        if (onTap != null) onTap!();
      },
      behavior: HitTestBehavior.translucent, 
      child: Stack(
        children: [
          // Невидимий шар для реєстрації у платформі
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: HtmlElementView(viewType: _viewTypeDiv, creationParams: {'id': id}),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Віджет Інпуту
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
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder()),
        ),
      ],
    );
  }
}

/// Віджет Скролу
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
      if (now - _lastEventTime > 200) {
        _lastEventTime = now;
        _callJs('triggerScroll', []);
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