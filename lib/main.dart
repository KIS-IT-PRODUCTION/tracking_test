import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

// --- 1. РЕЄСТР ЕЛЕМЕНТІВ ---
final Map<String, html.Element> _elementRegistry = {};

void main() {
  // --- 2. ФАБРИКА ЕЛЕМЕНТІВ ---
  ui_web.platformViewRegistry.registerViewFactory(
    'tracked-tag',
    (int viewId, {Object? params}) {
      final mapParams = params as Map<String, dynamic>;
      final String id = mapParams['id'];

      final div = html.DivElement()
        ..id = id
        ..style.width = '100%'
        ..style.height = '100%'
        // Пропускаємо кліки крізь HTML, щоб Flutter не ламався
        ..style.pointerEvents = 'none' 
        ..style.backgroundColor = 'rgba(0,0,0,0)'
        ..setAttribute('data-ts1-id', id);

      _elementRegistry[id] = div;

      return div;
    },
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracking Fix',
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: '/',
      routes: {
        '/': (context) => const TestPage(),
        '/finish': (context) => const FinishPage(),
      },
    );
  }
}

// --- 3. БЕЗПЕЧНА КНОПКА (TRACKED) ---
class TrackedBtn extends StatelessWidget {
  final String id;
  final VoidCallback onTap;
  final Widget child;

  const TrackedBtn({
    super.key,
    required this.id,
    required this.onTap,
    required this.child,
  });

  void _handleTap() {
    print('Flutter: Button tapped. Triggering JS event for ID: $id');
    
    // А. Програмно створюємо подію кліку для скрипта
    if (_elementRegistry.containsKey(id)) {
      // ВИПРАВЛЕННЯ ТУТ: canBubble замість bubbles
      final event = html.MouseEvent('click', 
        view: html.window, 
        canBubble: true, 
        cancelable: true
      );
      _elementRegistry[id]?.dispatchEvent(event);
    } 

    // Б. Виконуємо логіку Flutter
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ШАР 1: HTML ТЕГ (Пропускає кліки)
        Positioned.fill(
          child: HtmlElementView(
            viewType: 'tracked-tag',
            creationParams: {'id': id},
          ),
        ),

        // ШАР 2: ВІЗУАЛЬНА КНОПКА + ПЕРЕХОПЛЮВАЧ
        GestureDetector(
          onTap: _handleTap,
          behavior: HitTestBehavior.translucent,
          child: IgnorePointer(
            child: child,
          ),
        ),
      ],
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

  void _onLoginPressed() {
    Navigator.pushNamed(context, '/finish');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Крок 1: Вхід")),
      body: SingleChildScrollView(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 40),
                const Icon(Icons.login, size: 80, color: Colors.blue),
                const SizedBox(height: 20),
                const Text("Введіть дані", style: TextStyle(fontSize: 24)),
                const SizedBox(height: 20),
                TextField(
                  controller: _loginController,
                  decoration: const InputDecoration(labelText: "Логін", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                
                // --- КНОПКА ВХОДУ ---
                TrackedBtn(
                  id: 'login_btn_top', 
                  onTap: _onLoginPressed,
                  child: ElevatedButton(
                    onPressed: () {}, 
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                    child: const Text("Увійти (Fix)"),
                  ),
                ),

                const SizedBox(height: 600),
                const Text("Скрол тест"),
                const SizedBox(height: 20),

                // --- НИЖНЯ КНОПКА ---
                TrackedBtn(
                  id: 'scroll_test_btn',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Нижня кнопка працює!")),
                    );
                  },
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text("Тестова кнопка"),
                  ),
                ),
                const SizedBox(height: 50),
              ],
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
            const Text("Успішно!", style: TextStyle(fontSize: 30, color: Colors.green)),
            const SizedBox(height: 30),
            
            SizedBox(
              width: 200, height: 50,
              child: TrackedBtn(
                id: 'finish_back_btn',
                onTap: () => Navigator.pop(context),
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text("Назад"),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}