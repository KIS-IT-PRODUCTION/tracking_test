// 1. ХОВАЄМО оригінальні віджети
import 'package:flutter/material.dart' hide TextField, ElevatedButton, SingleChildScrollView;
import 'package:flutter_web_plugins/url_strategy.dart';

// 2. ІМПОРТУЄМО нашу бібліотеку
import 'tracker_lib.dart'; 

void main() {
  usePathUrlStrategy(); 
  initTracking(); // <--- Ініціалізація
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Client App',
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginPage(),
        '/finish': (context) => const FinishPage(),
      },
      navigatorObservers: [TrackerRouteObserver()],
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _secretCtrl = TextEditingController(); // Контролер для поля без трекінгу

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Вхід у систему")),
      
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 50),
            
              const Text("1. Поле з трекінгом:", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              // --- ПОЛЕ З ТРЕКІНГОМ (dataTs1Id вказано) ---
              TextField(
                dataTs1Id: 'login_email_field', // <--- Є ID = ТРЕКІНГ ПРАЦЮЄ
                controller: _emailCtrl, 
                decoration: const InputDecoration(
                  labelText: 'Електронна пошта', 
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(),
                  helperText: "Введення тут відправляється в JS"
                ),
              ),
              
              const SizedBox(height: 30),

              const Text("2. Поле БЕЗ трекінгу:", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              // --- ПОЛЕ БЕЗ ТРЕКІНГУ (dataTs1Id відсутній) ---
              TextField(
                // dataTs1Id НЕ ВКАЗАНО = ТРЕКІНГ ВИМКНЕНО
                controller: _secretCtrl, 
                decoration: const InputDecoration(
                  labelText: 'Секретне поле', 
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                  helperText: "Введення тут ігнорується трекером"
                ),
              ),
              
              const SizedBox(height: 30),
              
              // Кнопка входу
              ElevatedButton(
                dataTs1Id: 'submit_login_btn',
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                   Navigator.pushNamed(context, '/finish');
                },
                child: const Text('Увійти'),
              ),
              
              const SizedBox(height: 1000), 
              const Text("Кінець сторінки"),
              const SizedBox(height: 50), 
            ],
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
      appBar: AppBar(title: const Text("Результат")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 100),
            const SizedBox(height: 20),
            const Text("Успішно!", style: TextStyle(fontSize: 24)),
            const SizedBox(height: 20),
            ElevatedButton(
              dataTs1Id: 'back_btn',
              onPressed: () => Navigator.pop(context),
              child: const Text("Назад"),
            )
          ],
        ),
      ),
    );
  }
}