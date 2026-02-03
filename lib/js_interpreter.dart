import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

class JSInterpreter {
  static final Map<String, html.Element> _activeTags = {};

  static void initialize() {
    // Реєструємо порожній віджет, він нам потрібен лише для зайняття місця у Flutter
    ui_web.platformViewRegistry.registerViewFactory(
      'tracked-tag',
      (int viewId, {Object? params}) => html.DivElement(),
    );
  }

  /// Цей метод тепер створює реальний тег у Body документа
  static void registerGlobalTag(String id, double x, double y, double width, double height) {
    if (_activeTags.containsKey(id)) {
      _activeTags[id]!.remove();
    }

    final element = html.DivElement()
      ..id = 'el_$id'
      ..setAttribute('data-ts1-id', id)
      ..style.position = 'absolute'
      ..style.left = '${x}px'
      ..style.top = '${y}px'
      ..style.width = '${width}px'
      ..style.height = '${height}px'
      ..style.zIndex = '99999'
      ..style.pointerEvents = 'none' // Щоб не перехоплював кліки у Flutter
      ..style.backgroundColor = 'transparent';

    html.document.body?.append(element);
    _activeTags[id] = element;
    print('JS Interpreter: Global tag registered for $id');
  }

  static void triggerPointerEvent(String id, String eventType) {
    final element = html.document.getElementById('el_$id');
    if (element != null) {
      element.dispatchEvent(html.MouseEvent(eventType, canBubble: true));
    } else {
      print('JS Interpreter Error: Element el_$id not found in global DOM');
    }
  }
static void updateAllPositions() {
  _activeTags.forEach((id, element) {
    // Ми можемо викликати оновлення через GlobalKey, 
    // але простіше просто синхронізувати позиції при скролі
    // Якщо кнопок багато, можна додати логіку перерахунку RenderBox
  });
}
  /// Оновлює значення в прихованому полі
  static void updateInputValue(String id, String value) {
    final element = html.document.getElementById('el_$id');
    if (element is html.InputElement) {
      element.value = value;
      // Скрипт Bibber слухає ці події для аналізу швидкості друку
      element.dispatchEvent(html.KeyEvent('keydown'));
      element.dispatchEvent(html.Event('input'));
    }
  }

  /// Оновлення Client ID
  static void updateClientId(String newId) {
    final el = html.document.getElementById('ts1-client-id');
    if (el != null) {
      el.setAttribute('value', newId);
    }
    // Дублюємо в localStorage, бо скрипт може брати дані звідти напряму
    html.window.localStorage['ts1_client_id'] = newId;
  }
  
  /// Емуляція нативного скролу
  static void syncScroll() {
    html.window.dispatchEvent(html.Event('scroll'));
  }
}