import 'package:flutter/material.dart';
import 'js_interpreter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  JSInterpreter.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bibber Tracking Fix',
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: '/',
      routes: {
        '/': (context) => const TestPage(),
        '/finish': (context) => const FinishPage(),
      },
    );
  }
}

// --- КРОК 1: СТОРІНКА ВХОДУ ---
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
      body: NotificationListener<ScrollNotification>(
        onNotification: (scroll) {
          // Повідомляємо JS про скрол і оновлюємо позиції тегів
          JSInterpreter.syncScroll();
          return false; 
        },
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
                  const Text("Введіть дані", style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 20),
                  
                  // ТРЕКІНГ ПОЛЯ ВВЕДЕННЯ
                  TrackedBox(
                    id: 'login_input_field',
                    child: TextField(
                      controller: _loginController,
                      onChanged: (val) => JSInterpreter.updateInputValue('login_input_field', val),
                      decoration: const InputDecoration(
                        labelText: "Логін", 
                        border: OutlineInputBorder()
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // КНОПКА ВХОДУ
                  TrackedBox(
                    id: 'login_btn_top',
                    onTap: () => Navigator.pushNamed(context, '/finish'),
                    child: ElevatedButton(
                      onPressed: () {}, 
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50)
                      ),
                      child: const Text("Увійти"),
                    ),
                  ),

                  // ВЕЛИКИЙ СКРОЛ
                  const SizedBox(height: 800),
                  const Text("Тест скролу (Нижня частина)"),
                  const SizedBox(height: 20),

                  // ТЕСТОВА КНОПКА ЗНИЗУ
                  TrackedBox(
                    id: 'scroll_test_btn',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Нижня кнопка працює!"), backgroundColor: Colors.green),
                      );
                    },
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: const Text("Тестова кнопка (Tracking)"),
                    ),
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

// --- КРОК 2: СТОРІНКА УСПІХУ ---
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
            
            TrackedBox(
              id: 'finish_back_btn',
              onTap: () => Navigator.pop(context),
              child: ElevatedButton(
                onPressed: () {},
                child: const Text("Назад до входу"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- РОБОЧА ОБГОРТКА ТРЕКІНГУ ---
class TrackedBox extends StatefulWidget {
  final String id;
  final Widget child;
  final VoidCallback? onTap;

  const TrackedBox({super.key, required this.id, required this.child, this.onTap});

  @override
  State<TrackedBox> createState() => _TrackedBoxState();
}

class _TrackedBoxState extends State<TrackedBox> {
  final GlobalKey _key = GlobalKey();

  void _updateTagPosition() {
    if (!mounted) return;
    final RenderBox? renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      
      JSInterpreter.registerGlobalTag(
        widget.id, 
        position.dx, 
        position.dy, 
        size.width, 
        size.height
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateTagPosition());
  }

  @override
  Widget build(BuildContext context) {
    // Використовуємо NotificationListener для відстеження скролу саме цього елемента
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _updateTagPosition();
        return false;
      },
      child: Listener(
        key: _key,
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          _updateTagPosition(); // Оновлюємо позицію прямо перед кліком для точності
          JSInterpreter.triggerPointerEvent(widget.id, 'mousedown');
        },
        onPointerUp: (_) {
          JSInterpreter.triggerPointerEvent(widget.id, 'mouseup');
          JSInterpreter.triggerPointerEvent(widget.id, 'click');
          widget.onTap?.call();
        },
        child: widget.child,
      ),
    );
  }
}