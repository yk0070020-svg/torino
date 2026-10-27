import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

SupabaseClient get sb => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  runApp(const TorinoApp());
}

class TorinoApp extends StatelessWidget {
  const TorinoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Torino',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8E5BD6), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const Root(),
    );
  }
}

enum Stage { login, lock, secret, chat }

class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> with WidgetsBindingObserver {
  late Stage stage;
  bool secretVerified = false;
  DateTime? pausedAt;
  static const lockAfter = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    stage = sb.auth.currentSession == null ? Stage.login : Stage.lock;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (stage != Stage.chat && stage != Stage.secret) return;
    if (s == AppLifecycleState.paused) {
      pausedAt = DateTime.now();
    } else if (s == AppLifecycleState.resumed && pausedAt != null) {
      if (DateTime.now().difference(pausedAt!) > lockAfter) {
        setState(() => stage = Stage.lock);
      }
      pausedAt = null;
    }
  }

  Future<void> logout() async {
    await sb.auth.signOut();
    secretVerified = false;
    setState(() => stage = Stage.login);
  }

  @override
  Widget build(BuildContext context) {
    switch (stage) {
      case Stage.login:
        return LoginScreen(onDone: () => setState(() => stage = Stage.secret));
      case Stage.lock:
        return LockScreen(
          onUnlocked: () => setState(
              () => stage = secretVerified ? Stage.chat : Stage.secret),
          onLogout: logout,
        );
      case Stage.secret:
        return SecretScreen(
          onDone: () {
            secretVerified = true;
            setState(() => stage = Stage.chat);
          },
          onLogout: logout,
        );
      case Stage.chat:
        return ChatScreen(onLogout: logout);
    }
  }
}

// ---------- Login ----------
class LoginScreen extends StatefulWidget {
  final VoidCallback onDone;
  const LoginScreen({super.key, required this.onDone});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final pass = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await sb.auth.signInWithPassword(
          email: email.text.trim(), password: pass.text);
      widget.onDone();
    } catch (_) {
      setState(() => error = 'Email বা password ভুল');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Torino',
                    style:
                        TextStyle(fontSize: 38, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text('A Private Space for Two'),
                const SizedBox(height: 32),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Email', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: pass,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Password', border: OutlineInputBorder()),
                  onSubmitted: (_) => submit(),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(busy ? '...' : 'Login'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- App lock ----------
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  final VoidCallback onLogout;
  const LockScreen(
      {super.key, required this.onUnlocked, required this.onLogout});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final auth = LocalAuthentication();
  bool trying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unlock());
  }

  Future<void> unlock() async {
    if (trying) return;
    trying = true;
    try {
      final supported = await auth.isDeviceSupported();
      if (!supported) {
        widget.onUnlocked();
        return;
      }
      final ok = await auth.authenticate(
        localizedReason: 'Torino খুলতে আপনার পরিচয় নিশ্চিত করুন',
        options: const AuthenticationOptions(stickyAuth: true),
      );
      if (ok) widget.onUnlocked();
    } catch (_) {}
    trying = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 64),
            const SizedBox(height: 16),
            FilledButton(onPressed: unlock, child: const Text('Unlock')),
            TextButton(onPressed: widget.onLogout, child: const Text('Logout')),
          ],
        ),
      ),
    );
  }
}

// ---------- Secret key ----------
class SecretScreen extends StatefulWidget {
  final VoidCallback onDone;
  final VoidCallback onLogout;
  const SecretScreen({super.key, required this.onDone, required this.onLogout});
  @override
  State<SecretScreen> createState() => _SecretScreenState();
}

class _SecretScreenState extends State<SecretScreen> {
  final key = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ok = await sb.rpc('verify_secret', params: {'p_key': key.text});
      if (ok == true) {
        widget.onDone();
      } else {
        setState(() => error = 'Key ভুল (৫ বার ভুল হলে ১৫ মিনিট বন্ধ থাকবে)');
      }
    } catch (_) {
      setState(() => error = 'সংযোগে সমস্যা, আবার চেষ্টা করুন');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.key, size: 52),
                const SizedBox(height: 16),
                TextField(
                  controller: key,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Secret Key', border: OutlineInputBorder()),
                  onSubmitted: (_) => submit(),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(busy ? '...' : 'Enter'),
                  ),
                ),
                TextButton(
                    onPressed: widget.onLogout, child: const Text('Logout')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Chat ----------
class ChatScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const ChatScreen({super.key, required this.onLogout});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final input = TextEditingController();
  late final Stream<List<Map<String, dynamic>>> stream;

  @override
  void initState() {
    super.initState();
    stream = sb
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    input.clear();
    try {
      await sb.from('messages').insert({'body': text});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('পাঠানো যায়নি')));
      }
    }
  }

  Future<void> confirmDelete(String id) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('মেসেজ delete করবেন?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('না')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('হ্যাঁ')),
        ],
      ),
    );
    if (yes == true) {
      await sb.from('messages').delete().eq('id', id);
    }
  }

  String hm(DateTime t) {
    final l = t.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m ${l.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final me = sb.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Torino'),
        actions: [
          IconButton(
              icon: const Icon(Icons.logout), onPressed: widget.onLogout),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                final msgs = snap.data ?? [];
                if (snap.connectionState == ConnectionState.waiting &&
                    msgs.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final m = msgs[i];
                    final mine = m['sender_id'] == me;
                    final scheme = Theme.of(context).colorScheme;
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress:
                            mine ? () => confirmDelete(m['id'] as String) : null,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.78),
                          decoration: BoxDecoration(
                            color: mine
                                ? scheme.primaryContainer
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(m['body'] as String,
                                  style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 3),
                              Text(
                                hm(DateTime.parse(m['created_at'] as String)),
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'মেসেজ লিখুন...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                      onPressed: send, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
