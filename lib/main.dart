import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:html_character_entities/html_character_entities.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:app_links/app_links.dart';
import 'dart:io';
import 'dart:ui' as ui;

const String _kAppVersion = '1.1.1';
const int _kAppVersionCode = 11;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://kusvloreaakrvwsdhqhj.supabase.co',
    anonKey: 'sb_publishable_eHuAUb_bxcu8mi5ZL8u9XA_k4iQjeCW',
  );

  AppLinks().uriLinkStream.listen((uri) {
    Supabase.instance.client.auth.getSessionFromUrl(uri);
  });

  runApp(const TruBriefApp());
}

class TruBriefApp extends StatelessWidget {
  const TruBriefApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TruBrief',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        useMaterial3: false,
        scaffoldBackgroundColor: Colors.black,
        cardColor: const Color(0xFF1C1C1E),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.black,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator(color: Color(0xFFFF6200))),
          );
        }
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          return const ArticlesScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLogin = true;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;
  bool _signUpPending = false;
  String? _pendingEmail;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool('remember_me') ?? false;
    if (!remember) return;
    final email = prefs.getString('saved_email') ?? '';
    final password = prefs.getString('saved_password') ?? '';
    if (email.isEmpty || password.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _rememberMe = true;
      _emailCtrl.text = email;
      _passwordCtrl.text = password;
    });
    _submit(autoLogin: true);
  }

  Future<void> _saveCredentials(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', true);
    await prefs.setString('saved_email', email);
    await prefs.setString('saved_password', password);
  }

  Future<void> _clearSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('remember_me');
    await prefs.remove('saved_email');
    await prefs.remove('saved_password');
  }

  Future<void> _signInWithSocial(OAuthProvider provider) async {
    setState(() { _loading = true; _error = null; });
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        provider,
        redirectTo: 'com.truresolve.trubrief://login-callback',
      );
    } on AuthException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Social sign-in failed. Please try again.'; _loading = false; });
    }
  }

  Widget _socialButton(String letter, String name, VoidCallback onTap, Color color, {IconData? icon}) {
    return GestureDetector(
      onTap: _loading ? null : onTap,
      child: Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Center(
          child: icon != null
            ? Icon(icon, color: color, size: 26)
            : Text(letter, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: letter == '𝕏' ? 18 : 22)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit({bool autoLogin = false}) async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    if (email.isEmpty || password.isEmpty) {
      if (!autoLogin) setState(() => _error = 'Please enter your email and password.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      if (_isLogin) {
        await Supabase.instance.client.auth.signInWithPassword(email: email, password: password);
        if (_rememberMe) {
          await _saveCredentials(email, password);
        } else {
          await _clearSavedCredentials();
        }
      } else {
        final res = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: 'https://kusvloreaakrvwsdhqhj.supabase.co/auth/v1/callback',
        );
        if (mounted && res.session == null) {
          setState(() {
            _loading = false;
            _error = null;
            _signUpPending = true;
            _pendingEmail = email;
          });
          return;
        }
      }
    } on AuthException catch (e) {
      if (mounted) setState(() { _error = autoLogin ? null : e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = autoLogin ? null : 'Something went wrong. Please try again.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_signUpPending) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFFF6200), Color(0xFFFF8040)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.mark_email_read_outlined, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 28),
                  const Text('Check your email', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  const SizedBox(height: 12),
                  Text(
                    'We sent a confirmation link to\n${_pendingEmail ?? 'your email'}.\n\nTap the link to activate your account, then come back and sign in.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 15, height: 1.6),
                  ),
                  const SizedBox(height: 36),
                  GestureDetector(
                    onTap: () => setState(() { _signUpPending = false; _isLogin = true; }),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFF6200), Color(0xFFFF8040)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: const Color(0xFFFF6200).withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
                      ),
                      child: const Text('Back to Sign In', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                  child: Image.asset(
                    'assets/images/Playstore_Banner.jpg',
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                const SizedBox(height: 32),
                Text(
                  _isLogin ? 'Welcome back' : 'Create your account',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  _isLogin ? 'Sign in to continue' : 'Free forever — no credit card needed',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Email',
                    labelStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1C1C1E),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.email_outlined, color: Colors.white38, size: 20),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1C1C1E),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.lock_outline, color: Colors.white38, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white38, size: 20),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
                if (_isLogin) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _rememberMe,
                          onChanged: (val) => setState(() => _rememberMe = val ?? false),
                          activeColor: const Color(0xFFFF6200),
                          side: const BorderSide(color: Colors.white38),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _rememberMe = !_rememberMe),
                        child: const Text('Remember me', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () async {
                        final email = _emailCtrl.text.trim();
                        if (email.isEmpty) {
                          setState(() => _error = 'Enter your email above first.');
                          return;
                        }
                        final messenger = ScaffoldMessenger.of(context);
                        setState(() { _loading = true; _error = null; });
                        try {
                          await Supabase.instance.client.auth.resetPasswordForEmail(
                            email,
                            redirectTo: 'https://kusvloreaakrvwsdhqhj.supabase.co/auth/v1/callback',
                          );
                          if (mounted) {
                            setState(() => _loading = false);
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Password reset email sent. Check your inbox.')),
                            );
                          }
                        } catch (e) {
                          if (mounted) setState(() { _loading = false; _error = 'Could not send reset email. Try again.'; });
                        }
                      },
                      child: const Text('Forgot password?', style: TextStyle(color: Color(0xFFFF6200), fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6200),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(_isLogin ? 'Sign In' : 'Create Account', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  const Expanded(child: Divider(color: Colors.white12)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or continue with', style: const TextStyle(color: Colors.white24, fontSize: 12)),
                  ),
                  const Expanded(child: Divider(color: Colors.white12)),
                ]),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _socialButton('G', 'Google', () => _signInWithSocial(OAuthProvider.google), const Color(0xFF4285F4)),
                    const SizedBox(width: 12),
                    _socialButton('', 'Apple', () => _signInWithSocial(OAuthProvider.apple), Colors.white, icon: Icons.apple),
                    const SizedBox(width: 12),
                    _socialButton('f', 'Facebook', () => _signInWithSocial(OAuthProvider.facebook), const Color(0xFF1877F2)),
                    const SizedBox(width: 12),
                    _socialButton('𝕏', 'X / Twitter', () => _signInWithSocial(OAuthProvider.twitter), Colors.white),
                  ],
                ),
                const SizedBox(height: 20),
                Center(
                  child: GestureDetector(
                    onTap: () => setState(() { _isLogin = !_isLogin; _error = null; }),
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: _isLogin ? 'Don\'t have an account? ' : 'Already have an account? ',
                            style: const TextStyle(color: Colors.white38, fontSize: 14),
                          ),
                          TextSpan(
                            text: _isLogin ? 'Sign up free' : 'Sign in',
                            style: const TextStyle(color: Color(0xFFFF6200), fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                    ],
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

class ArticlesScreen extends StatefulWidget {
  const ArticlesScreen({super.key});

  @override
  State<ArticlesScreen> createState() => _ArticlesScreenState();
}

class _ArticlesScreenState extends State<ArticlesScreen> with TickerProviderStateMixin {
  String? get _effectiveUserId => Supabase.instance.client.auth.currentUser?.id;

  bool get _currentCategoryHasNoActiveSources {
    if (_selectedCategory == 'Tru Brief' || _selectedCategory == 'Local Brief' || _selectedCategory == 'National Brief' || _selectedCategory == 'Tru Flash') return false;
    final shortCat = _selectedCategory.replaceAll(' Brief', '').replaceAll(' News', '').trim();
    final catSources = _allSources.where((s) {
      final sCat = s['category']?.toString() ?? '';
      return sCat == _selectedCategory || sCat == shortCat || sCat == '$shortCat Brief' || sCat == '$shortCat News';
    }).toList();
    if (catSources.isEmpty) return false;
    return !catSources.any((s) => _selectedSources.contains(s['id'].toString()));
  }

  List<dynamic> _articles = [];
  List<dynamic> _allSources = [];
  bool _loading = true;
  bool _isPremium = false;
  bool _isTrialActive = false;
  bool _isIngesting = false;
  bool _isDisposed = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _savedArticleIds = {};
  
  List<String> _categories = [];
  List<String> _virtualCategories = [];
  List<String> _selectedCategories = [];
  List<String> _selectedSources = [];
  String _selectedCategory = 'Tru Brief';
  String? _zipCode;
  String? _locationType; // 'exact', 'zip', 'none'
  String? _city;
  String? _state;
  String? _county;
  Set<String> _hiddenTabs = {};
  String _flashSelectedSource = 'All Sources';
  String? _flashSelectedTopic;
  List<String> _flashEnabledSources = [];
  List<Map<String, dynamic>> _flashDynamicTopics = [];
  List<dynamic> _flashAllSourceArticles = [];

  static const List<Map<String, String>> _kFlashSources = [
    {'name': 'Fox News', 'url': 'https://feeds.foxnews.com/foxnews/latest'},
    {'name': 'CNN', 'url': 'https://news.google.com/rss/search?q=site:cnn.com&hl=en-US&gl=US&ceid=US:en'},
    {'name': 'NBC News', 'url': 'https://feeds.nbcnews.com/nbcnews/public/news'},
    {'name': 'Politico', 'url': 'https://rss.politico.com/politics-news.xml'},
    {'name': 'ABC News', 'url': 'https://feeds.abcnews.com/abcnews/topstories'},
    {'name': 'CBS News', 'url': 'https://feeds.cbsnews.com/cbsnews/rss/latest'},
    {'name': 'NPR', 'url': 'https://feeds.npr.org/1001/rss.xml'},
    {'name': 'Reuters', 'url': 'https://news.google.com/rss/search?q=site:reuters.com&hl=en-US&gl=US&ceid=US:en'},
    {'name': 'The Hill', 'url': 'https://thehill.com/rss/syndicator/19110'},
    {'name': 'DW News', 'url': 'https://rss.dw.com/rdf/rss-en-top'},
  ];

  static const Map<String, List<Map<String, String>>> _kFlashSourceTopics = {
    'Fox News': [
      {'name': 'Latest', 'url': 'https://feeds.foxnews.com/foxnews/latest'},
      {'name': 'Politics', 'url': 'https://feeds.foxnews.com/foxnews/politics'},
      {'name': 'U.S.', 'url': 'https://feeds.foxnews.com/foxnews/national'},
      {'name': 'World', 'url': 'https://feeds.foxnews.com/foxnews/world'},
      {'name': 'Business', 'url': 'https://feeds.foxnews.com/foxnews/business'},
      {'name': 'Entertainment', 'url': 'https://feeds.foxnews.com/foxnews/entertainment'},
    ],
    'CNN': [
      {'name': 'Latest', 'url': 'https://news.google.com/rss/search?q=site:cnn.com&hl=en-US&gl=US&ceid=US:en'},
      {'name': 'Politics', 'url': 'https://news.google.com/rss/search?q=site:cnn.com+politics&hl=en-US&gl=US&ceid=US:en'},
      {'name': 'World', 'url': 'https://news.google.com/rss/search?q=site:cnn.com+world+news&hl=en-US&gl=US&ceid=US:en'},
      {'name': 'U.S.', 'url': 'https://news.google.com/rss/search?q=site:cnn.com+us+news&hl=en-US&gl=US&ceid=US:en'},
      {'name': 'Business', 'url': 'https://news.google.com/rss/search?q=site:cnn.com+business&hl=en-US&gl=US&ceid=US:en'},
    ],
    'NBC News': [
      {'name': 'Latest', 'url': 'https://feeds.nbcnews.com/nbcnews/public/news'},
      {'name': 'Politics', 'url': 'https://feeds.nbcnews.com/nbcnews/public/politics'},
      {'name': 'Business', 'url': 'https://feeds.nbcnews.com/nbcnews/public/business'},
    ],
    'Politico': [
      {'name': 'Politics', 'url': 'https://rss.politico.com/politics-news.xml'},
      {'name': 'Congress', 'url': 'https://rss.politico.com/congress.xml'},
    ],
    'ABC News': [
      {'name': 'Latest', 'url': 'https://feeds.abcnews.com/abcnews/topstories'},
      {'name': 'U.S.', 'url': 'https://feeds.abcnews.com/abcnews/us'},
      {'name': 'World', 'url': 'https://feeds.abcnews.com/abcnews/world'},
      {'name': 'Politics', 'url': 'https://feeds.abcnews.com/abcnews/politics'},
      {'name': 'Business', 'url': 'https://feeds.abcnews.com/abcnews/business'},
    ],
    'CBS News': [
      {'name': 'Latest', 'url': 'https://feeds.cbsnews.com/cbsnews/rss/latest'},
      {'name': 'U.S.', 'url': 'https://feeds.cbsnews.com/cbsnews/rss/us'},
      {'name': 'World', 'url': 'https://feeds.cbsnews.com/cbsnews/rss/world'},
      {'name': 'Politics', 'url': 'https://feeds.cbsnews.com/cbsnews/rss/politics'},
    ],
    'NPR': [
      {'name': 'News', 'url': 'https://feeds.npr.org/1001/rss.xml'},
      {'name': 'Politics', 'url': 'https://feeds.npr.org/1014/rss.xml'},
      {'name': 'World', 'url': 'https://feeds.npr.org/1004/rss.xml'},
      {'name': 'Business', 'url': 'https://feeds.npr.org/1006/rss.xml'},
    ],
    'Reuters': [
      {'name': 'Top News', 'url': 'https://news.google.com/rss/search?q=site:reuters.com&hl=en-US&gl=US&ceid=US:en'},
      {'name': 'Business', 'url': 'https://news.google.com/rss/search?q=site:reuters.com+business&hl=en-US&gl=US&ceid=US:en'},
      {'name': 'World', 'url': 'https://news.google.com/rss/search?q=site:reuters.com+world+news&hl=en-US&gl=US&ceid=US:en'},
      {'name': 'Politics', 'url': 'https://news.google.com/rss/search?q=site:reuters.com+politics&hl=en-US&gl=US&ceid=US:en'},
      {'name': 'Tech', 'url': 'https://news.google.com/rss/search?q=site:reuters.com+technology&hl=en-US&gl=US&ceid=US:en'},
    ],
    'The Hill': [
      {'name': 'Latest', 'url': 'https://thehill.com/rss/syndicator/19110'},
    ],
    'DW News': [
      {'name': 'Top', 'url': 'https://rss.dw.com/rdf/rss-en-top'},
      {'name': 'World', 'url': 'https://rss.dw.com/rdf/rss-en-world'},
      {'name': 'Business', 'url': 'https://rss.dw.com/rdf/rss-en-business'},
    ],
  };

  bool _showTutorial = false;
  int _tutorialStep = 0;
  bool _feedGridOpen = false;

  late final AnimationController _tutorialPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..repeat(reverse: true);
  final GlobalKey _truBriefTabKey = GlobalKey();
  final GlobalKey _gridIconKey = GlobalKey();
  final GlobalKey _articleListKey = GlobalKey();
  final GlobalKey _settingsButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _fetchSavedArticles();
    _ensureDefaultSourcesExist();
    _fetchNewArticlesFromSources();
    _archiveOldArticles();
    _loadFlashEnabledSources();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _checkForUpdate();
      await _checkTutorial();
    });
  }

  Future<void> _loadFlashEnabledSources() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('flash_enabled_sources');
    if (mounted) {
      setState(() {
        _flashEnabledSources = saved ?? _kFlashSources.map((s) => s['name']!).toList();
        if (_flashEnabledSources.isNotEmpty && (_flashSelectedSource == 'All Sources' || !_flashEnabledSources.contains(_flashSelectedSource))) {
          _flashSelectedSource = _flashEnabledSources.first;
        }
        _flashSelectedTopic = null;
      });
    }
  }

  static const Set<String> _kFlashStopWords = {
    'about', 'after', 'again', 'against', 'also', 'amid', 'another', 'are', 'back',
    'been', 'being', 'between', 'both', 'but', 'call', 'calls', 'can', 'come',
    'comes', 'could', 'days', 'dead', 'dies', 'does', 'dont', 'down', 'each',
    'even', 'ever', 'face', 'faces', 'find', 'first', 'from', 'full', 'gets',
    'getting', 'give', 'going', 'good', 'have', 'here', 'high', 'hits', 'home',
    'hours', 'into', 'just', 'know', 'last', 'late', 'like', 'live', 'made', 'make',
    'many', 'more', 'most', 'move', 'much', 'need', 'never', 'news', 'next', 'now',
    'only', 'open', 'other', 'over', 'part', 'plan', 'plans', 'plus', 'puts',
    'real', 'report', 'reports', 'right', 'said', 'same', 'says', 'seen', 'sets',
    'show', 'shows', 'since', 'some', 'still', 'such', 'take', 'takes', 'talk',
    'tells', 'than', 'that', 'the', 'their', 'them', 'then', 'there', 'these',
    'they', 'this', 'three', 'through', 'time', 'today', 'told', 'too', 'top',
    'turn', 'two', 'under', 'until', 'use', 'used', 'very', 'want', 'wants',
    'was', 'way', 'week', 'weeks', 'were', 'what', 'when', 'where', 'which',
    'while', 'who', 'will', 'with', 'without', 'would', 'year', 'years', 'your',
    'major',
  };

  List<Map<String, dynamic>> _extractFlashTopics(List<dynamic> articles) {
    final phraseToIndices = <String, Set<int>>{};

    for (int i = 0; i < articles.length; i++) {
      final rawTitle = (articles[i]['title'] ?? '').toString();
      final words = rawTitle
          .replaceAll(RegExp(r"[^\w\s'-]"), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.length >= 2)
          .toList();

      for (int len = 2; len <= 4; len++) {
        for (int j = 0; j <= words.length - len; j++) {
          final seg = words.sublist(j, j + len);
          final segLower = seg.map((w) => w.toLowerCase()).toList();
          // First and last word must not be stop words
          if (_kFlashStopWords.contains(segLower.first) || _kFlashStopWords.contains(segLower.last)) continue;
          // First and last word must be substantial
          if (seg.first.length < 3 || seg.last.length < 3) continue;
          // At least ceil(len/2) words must be non-stop
          final nonStop = segLower.where((w) => !_kFlashStopWords.contains(w)).length;
          if (nonStop < (len / 2).ceil()) continue;
          final phrase = seg.map((w) => w.toUpperCase()).join(' ');
          phraseToIndices.putIfAbsent(phrase, () => <int>{}).add(i);
        }
      }
    }

    // Sort: more articles first, then longer phrase preferred
    final candidates = phraseToIndices.entries
        .where((e) => e.value.length >= 2)
        .toList()
      ..sort((a, b) {
        final cmp = b.value.length.compareTo(a.value.length);
        if (cmp != 0) return cmp;
        return b.key.length.compareTo(a.key.length);
      });

    final selected = <String>[];
    final usedIndices = <int>{};
    final topics = <Map<String, dynamic>>[];

    for (final entry in candidates) {
      if (topics.length >= 5) break;
      final phrase = entry.key;
      // Skip sub-phrases or super-phrases of already selected topics
      if (selected.any((s) => s.contains(phrase) || phrase.contains(s))) continue;
      final newIndices = entry.value.difference(usedIndices);
      if (newIndices.length < 2) continue;
      final topicArticles = entry.value.map((idx) => articles[idx]).toList()
        ..sort((a, b) {
          final da = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(0);
          final db = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(0);
          return db.compareTo(da);
        });
      selected.add(phrase);
      usedIndices.addAll(entry.value);
      topics.add({'name': phrase, 'articles': topicArticles});
    }
    return topics;
  }

  Future<void> _fetchFlashBySourceAndTopic(String sourceName, String topicUrl) async {
    if (mounted) setState(() => _loading = true);
    try {
      // Fetch from ALL available RSS feeds for this source to maximise the article pool for topic matching
      final feedUrls = (_kFlashSourceTopics[sourceName]?.map((t) => t['url']!).toList())
          ?? [_kFlashSources.firstWhere((s) => s['name'] == sourceName, orElse: () => {'url': topicUrl})['url'] ?? topicUrl];
      final results = await Future.wait(feedUrls.map((u) => _fetchRssFeedExpanded(u)));
      final seen = <String>{};
      final allArticles = <dynamic>[];
      for (final batch in results) {
        for (final a in batch) {
          final url = (a['original_url'] ?? '').toString();
          if (url.isNotEmpty && seen.add(url)) allArticles.add(a);
        }
      }
      if (allArticles.isEmpty) {
        final sourceDomains = <String, String>{
          'CNN': 'cnn.com',
          'Reuters': 'reuters.com',
          'NBC News': 'nbcnews.com',
          'ABC News': 'abcnews.go.com',
          'CBS News': 'cbsnews.com',
          'Politico': 'politico.com',
          'NPR': 'npr.org',
          'The Hill': 'thehill.com',
          'DW News': 'dw.com',
          'Fox News': 'foxnews.com',
        };
        final domain = sourceDomains[sourceName];
        if (domain != null) {
          try {
            final gnUrl = 'https://news.google.com/rss/search?q=site:$domain&hl=en-US&gl=US&ceid=US:en';
            final gnArticles = await _fetchRssFeedExpanded(gnUrl);
            for (final a in gnArticles) {
              final m = Map<String, dynamic>.from(a as Map);
              m['source_name'] = sourceName;
              final url = (m['original_url'] ?? '').toString();
              if (url.isNotEmpty && seen.add(url)) allArticles.add(m);
            }
          } catch (_) {}
        }
      }

      allArticles.sort((a, b) {
        final da = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(0);
        final db = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(0);
        return db.compareTo(da);
      });
      final latestUrl = feedUrls.first;
      final topics = await _fetchSourceTrendingTopics(sourceName, latestUrl, allArticles);
      if (mounted) {
        setState(() {
          _flashAllSourceArticles = allArticles;
          _flashDynamicTopics = topics;
          if (topics.isNotEmpty) {
            _flashSelectedTopic = topics.first['name'] as String;
            _articles = List<dynamic>.from(topics.first['articles'] as List);
          } else {
            _flashSelectedTopic = null;
            _articles = allArticles;
          }
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Flash fetch error: $e');
      if (mounted) setState(() { _articles = []; _loading = false; });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchSourceTrendingTopics(
    String sourceName,
    String rssUrl,
    List<dynamic> rssArticles,
  ) async {
    final sourceHomeUrls = <String, String>{
      'Fox News': 'https://www.foxnews.com/',
      'CNN': 'https://www.cnn.com/',
      'NBC News': 'https://www.nbcnews.com/',
      'ABC News': 'https://abcnews.go.com/',
      'CBS News': 'https://www.cbsnews.com/',
      'Politico': 'https://www.politico.com/',
      'NPR': 'https://www.npr.org/',
      'Reuters': 'https://www.reuters.com/',
      'The Hill': 'https://thehill.com/',
      'DW News': 'https://www.dw.com/en/',
    };

    final homeUrl = sourceHomeUrls[sourceName];
    if (homeUrl != null) {
      try {
        final res = await http.get(
          Uri.parse(homeUrl),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9',
          },
        ).timeout(const Duration(seconds: 12));

        final html = res.body;
        final trendingNames = <String>[];
        final trendingHrefs = <String, String>{};

        final htmlUp = html.toUpperCase();
        final trendingLabels = [
          'TRENDING',
          'MOST POPULAR',
          'MOST READ',
          "WHAT'S TRENDING",
          'TRENDING STORIES',
          'TRENDING NOW',
          'POPULAR STORIES',
          'POPULAR NOW',
          'IN THE NEWS',
          'TOP STORIES',
          'LIVE',
          'NOW TRENDING',
          'ALSO TRENDING',
          'TRENDING ON',
        ];
        const skipPhrases = [
          'log in', 'sign in', 'watch tv', 'watch live', 'watch now',
          'more +', 'more news', 'subscribe', 'newsletter', 'my account',
          'sign up', 'fox news', 'cnn', 'nbc news', 'abc news', 'cbs news',
          'the hill', 'reuters', 'politico', 'npr', 'dw news',
          'breaking news', 'latest news', 'top stories', 'most popular',
          'most read', 'trending', 'u.s. news', 'world news',
        ];

        for (final label in trendingLabels) {
          if (trendingNames.length >= 4) break;
          final labelIdx = htmlUp.indexOf(label);
          if (labelIdx < 0) continue;
          final window = html.substring(labelIdx, (labelIdx + 3000).clamp(0, html.length));
          final linkRe = RegExp(r'<a[^>]+href="([^"]*)"[^>]*>([\s\S]*?)</a>', caseSensitive: false);
          final foundInThisLabel = <String>[];
          for (final m in linkRe.allMatches(window)) {
            final href = m.group(1) ?? '';
            final rawText = (m.group(2) ?? '')
                .replaceAll(RegExp(r'<[^>]+>'), '')
                .replaceAll(RegExp(r'&amp;'), '&')
                .replaceAll(RegExp(r'&[a-z]+;'), '')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
            if (rawText.length < 5 || rawText.length > 80) continue;
            if (rawText.contains('{') || rawText.contains('<') || rawText.contains('©')) continue;
            final wordCount = rawText.split(RegExp(r'\s+')).length;
            if (wordCount < 2 || wordCount > 10) continue;
            final lower = rawText.toLowerCase();
            if (skipPhrases.any((s) => lower == s || lower == '$s:' || lower.startsWith('$s '))) continue;
            if (wordCount == 2 && lower.split(' ').every((w) => w.length <= 3)) continue;
            final upper = rawText.toUpperCase();
            if (!trendingNames.contains(upper) && !foundInThisLabel.contains(upper)) {
              foundInThisLabel.add(upper);
              if (href.isNotEmpty) {
                trendingHrefs[upper] = href.startsWith('http') ? href : '${homeUrl.replaceAll(RegExp(r'/$'), '')}$href';
              }
            }
            if (foundInThisLabel.length >= 6) break;
          }
          if (foundInThisLabel.length >= 2) {
            trendingNames.addAll(foundInThisLabel);
            break;
          }
        }

        // Strategy 2: __NEXT_DATA__ JSON
        if (trendingNames.isEmpty) {
          final nextData = RegExp(r'<script[^>]+id="__NEXT_DATA__"[^>]*>([\s\S]*?)</script>').firstMatch(html)?.group(1);
          if (nextData != null) {
            final trendCtx = RegExp(
              r'"(?:trending|ticker|trendingTopics|breakingNews|trendBar|liveBar|liveTopics|breakingBar|tickers|alerts|breaking|topStories|featuredStories|popularTopics)"[\s\S]{0,500}?\[[\s\S]{0,5000}?\]',
              caseSensitive: false,
            ).firstMatch(nextData);
            if (trendCtx != null) {
              final hits = RegExp(r'"(?:label|title|name|text|headline|displayTitle)"\s*:\s*"([^"]{4,60})"').allMatches(trendCtx.group(0)!);
              for (final h in hits.take(8)) {
                final t = h.group(1)!.trim();
                if (t.split(' ').length >= 2 && !t.contains('\\') && !t.contains('{')) {
                  trendingNames.add(t.toUpperCase());
                }
              }
            }
          }
        }

        // Strategy 3: Topic pill links
        if (trendingNames.isEmpty) {
          final topHtml = html.substring(0, html.length.clamp(0, 15000));
          final linkRe = RegExp(r'<a[^>]+href="([^"]*)"[^>]*>([\s\S]*?)</a>', caseSensitive: false);
          final candidates = <String, int>{};
          for (final m in linkRe.allMatches(topHtml)) {
            final rawText = (m.group(2) ?? '')
                .replaceAll(RegExp(r'<[^>]+>'), '')
                .replaceAll(RegExp(r'&[a-z]+;'), '')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
            final wc = rawText.split(' ').length;
            if (wc < 2 || wc > 6 || rawText.length < 5 || rawText.length > 50) continue;
            if (rawText.contains('{') || rawText.contains('<')) continue;
            final lower = rawText.toLowerCase();
            if (skipPhrases.any((s) => lower == s || lower.startsWith('$s '))) continue;
            candidates[rawText.toUpperCase()] = (candidates[rawText.toUpperCase()] ?? 0) + 1;
          }
          final pills = candidates.entries
              .where((e) => e.value == 1)
              .map((e) => e.key)
              .take(6)
              .toList();
          if (pills.length >= 2) trendingNames.addAll(pills);
        }

        if (trendingNames.isNotEmpty) {
          final topics = <Map<String, dynamic>>[];
          final domain = Uri.parse(homeUrl).host;

          for (final topicName in trendingNames.take(5)) {
            String? bannerUrl;
            List<dynamic> matched = [];

            // Try to fetch dedicated topic page for accurate articles + banner image
            final topicHref = trendingHrefs[topicName];
            if (topicHref != null) {
              try {
                final pageRes = await http.get(
                  Uri.parse(topicHref),
                  headers: {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                  },
                ).timeout(const Duration(seconds: 8));
                final pageHtml = pageRes.body;

                // Extract banner from og:image meta tag
                bannerUrl = RegExp(r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"', caseSensitive: false)
                    .firstMatch(pageHtml)?.group(1);
                bannerUrl ??= RegExp(r'<meta[^>]+content="([^"]+)"[^>]+property="og:image"', caseSensitive: false)
                    .firstMatch(pageHtml)?.group(1);

                // Strategy A: look for an embedded RSS/Atom feed link in the page <head>
                // Fox News category pages expose a per-category RSS link — this gives the exact curated article list
                final rssLinkRe = RegExp(
                  r'<link[^>]+type="application/(?:rss|atom)\+xml"[^>]+href="([^"]+)"',
                  caseSensitive: false,
                );
                final rssLinkMatch = rssLinkRe.firstMatch(pageHtml);
                if (rssLinkMatch != null) {
                  var feedUrl = rssLinkMatch.group(1)!;
                  if (!feedUrl.startsWith('http')) {
                    feedUrl = '${homeUrl.replaceAll(RegExp(r'/$'), '')}$feedUrl';
                  }
                  final feedArticles = await _fetchRssFeedExpanded(feedUrl);
                  if (feedArticles.isNotEmpty) {
                    matched = feedArticles;
                  }
                }

                // Strategy B: if the href path looks like a category (e.g. /category/politics/wars/war-with-iran),
                // try constructing a feeds.{domain}/path URL directly
                if (matched.isEmpty) {
                  final uri = Uri.parse(topicHref);
                  final feedsBase = 'https://feeds.${uri.host.replaceFirst('www.', '')}';
                  final candidateFeed = '$feedsBase${uri.path}';
                  try {
                    final feedArticles = await _fetchRssFeedExpanded(candidateFeed);
                    if (feedArticles.isNotEmpty) matched = feedArticles;
                  } catch (_) {}
                }

                // Strategy C: scan page HTML for any embedded RSS feed URL pointing to this domain
                if (matched.isEmpty) {
                  final embeddedFeedRe = RegExp(
                    r'https?://feeds\.' + RegExp.escape(domain.replaceFirst('www.', '')) + r'[^\s"<>]+',
                    caseSensitive: false,
                  );
                  final feedHit = embeddedFeedRe.firstMatch(pageHtml);
                  if (feedHit != null) {
                    try {
                      final feedArticles = await _fetchRssFeedExpanded(feedHit.group(0)!);
                      if (feedArticles.isNotEmpty) matched = feedArticles;
                    } catch (_) {}
                  }
                }
              } catch (e) {
                debugPrint('Topic page fetch failed for $topicName: $e');
              }
            }

            // Strategy D: Google News RSS search — most reliable source for topic articles.
            // Google indexes news articles quickly and provides a much larger window than source RSS feeds.
            try {
              final topicKws = topicName
                  .split(' ')
                  .where((w) => w.length >= 3 && !_kFlashStopWords.contains(w.toLowerCase()))
                  .take(5)
                  .map((w) => Uri.encodeComponent(w))
                  .join('+');
              final sourceDomain = domain.replaceFirst('www.', '');
              final googleUrl = 'https://news.google.com/rss/search'
                  '?q=site:$sourceDomain+$topicKws'
                  '&hl=en-US&gl=US&ceid=US:en';
              final rawGoogle = await _fetchRssFeedExpanded(googleUrl);
              debugPrint('Google News "$topicName" → ${rawGoogle.length} articles from $googleUrl');
              if (rawGoogle.isNotEmpty) {
                final googleArticles = rawGoogle.map((a) {
                  final m = Map<String, dynamic>.from(a as Map);
                  m['source_name'] = sourceName;
                  return m;
                }).toList();
                final existingUrls = matched
                    .map((a) => (a['original_url'] ?? '').toString())
                    .toSet();
                final existingTitles = matched
                    .map((a) => (a['title'] ?? '').toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim())
                    .where((t) => t.isNotEmpty)
                    .toSet();
                final newFromGoogle = googleArticles.where((a) {
                  final url = (a['original_url'] ?? '').toString();
                  if (existingUrls.contains(url)) return false;
                  final normalizedTitle = (a['title'] ?? '').toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim();
                  if (normalizedTitle.isEmpty) return true;
                  if (existingTitles.contains(normalizedTitle)) return false;
                  return !existingTitles.any((t) {
                    final shorter = normalizedTitle.length < t.length ? normalizedTitle : t;
                    final longer = normalizedTitle.length < t.length ? t : normalizedTitle;
                    return shorter.length > 20 && longer.contains(shorter);
                  });
                }).toList();
                matched = [...matched, ...newFromGoogle];
              }
            } catch (e) {
              debugPrint('Google News RSS failed for $topicName: $e');
            }

            // Fallback augmentation: keyword matches from the full source RSS pool
            if (matched.length < 5) {
              final keyWords = topicName.toLowerCase()
                  .split(' ')
                  .where((w) => w.length >= 3 && !_kFlashStopWords.contains(w))
                  .toList();
              final augmentKeys = keyWords.where((w) => w.length >= 4).toList();
              final fallbackKeys = augmentKeys.isNotEmpty ? augmentKeys : keyWords;
              if (fallbackKeys.isNotEmpty) {
                final existingUrls = matched
                    .map((a) => (a['original_url'] ?? '').toString())
                    .where((u) => u.isNotEmpty)
                    .toSet();
                final additional = rssArticles.where((a) {
                  final url = (a['original_url'] ?? '').toString();
                  if (url.isNotEmpty && existingUrls.contains(url)) return false;
                  final t = (a['title'] ?? '').toString().toLowerCase();
                  return fallbackKeys.any((w) => t.contains(w));
                }).toList();
                matched = [...matched, ...additional];
              }
            }

            if (matched.isNotEmpty) {
              matched.sort((a, b) {
                final da = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(0);
                final db = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(0);
                return db.compareTo(da);
              });
              topics.add({
                'name': topicName,
                'articles': matched,
                if (bannerUrl != null && bannerUrl.isNotEmpty) 'bannerUrl': bannerUrl,
              });
            }
          }
          if (topics.isNotEmpty) return topics;
        }
      } catch (e) {
        debugPrint('Trending scrape failed for $sourceName: $e');
      }
    }
    return _extractFlashTopics(rssArticles);
  }

  Future<List<dynamic>> _fetchRssFeedExpanded(String feedUrl) async {
    try {
      final res = await http.get(Uri.parse(feedUrl), headers: {'User-Agent': 'TruBrief/1.0'}).timeout(const Duration(seconds: 10));
      final xml = res.body;
      final items = RegExp(r'<item>(.*?)</item>', dotAll: true).allMatches(xml);
      final List<dynamic> articles = [];
      final sourceNameMatch = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(xml)?.group(1) ?? 'News';
      final cleanSourceName = _cleanXmlContent(sourceNameMatch).split('\n').first.trim();
      for (var match in items) {
        final item = match.group(1)!;
        final rawTitle = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(item)?.group(1) ?? '';
        final link = (RegExp(r'<link>(.*?)</link>', dotAll: true).firstMatch(item)?.group(1) ??
                      RegExp(r'<guid[^>]*>(.*?)</guid>', dotAll: true).firstMatch(item)?.group(1) ?? '').trim();
        final pubDateStr = RegExp(r'<pubDate>(.*?)</pubDate>', dotAll: true).firstMatch(item)?.group(1)?.trim();
        final desc = RegExp(r'<description>(.*?)</description>', dotAll: true).firstMatch(item)?.group(1) ?? '';
        final imgMatch = RegExp(r'<media:content[^>]*url="([^"]+)"', dotAll: true).firstMatch(item) ??
                         RegExp(r'<enclosure[^>]*url="([^"]+)"', dotAll: true).firstMatch(item);
        final imageUrl = imgMatch?.group(1);
        final title = _cleanXmlContent(rawTitle);
        final titleParts = title.split(' - ');
        final cleanTitle = titleParts.length > 1 ? titleParts.sublist(0, titleParts.length - 1).join(' - ') : title;
        if (link.isEmpty || cleanTitle.isEmpty) continue;
        final cleanDesc = _cleanDescription(desc);
        articles.add({
          'id': link.hashCode.toString(),
          'title': cleanTitle,
          'original_url': link,
          'image_url': imageUrl,
          'summary_brief': cleanDesc.isNotEmpty ? cleanDesc : null,
          'category': 'Tru Flash',
          'source_name': cleanSourceName,
          'source_id': null,
          'created_at': _parseRssDate(pubDateStr),
        });
      }
      return articles;
    } catch (e) {
      debugPrint('RSS expanded feed error for $feedUrl: $e');
      return [];
    }
  }

  Future<void> _checkTutorial() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final seen = user.userMetadata?['tutorial_seen'] == true;
    if (!seen && mounted) {
      setState(() { _showTutorial = true; _tutorialStep = 0; });
    }
  }

  Future<void> _advanceTutorial() async {
    if (_tutorialStep < 4) {
      setState(() => _tutorialStep++);
    } else if (_tutorialStep == 4) {
      setState(() { _showTutorial = false; });
      await _navigateToSettingsWithTutorial(startStep: 5);
    } else if (_tutorialStep < 8) {
      setState(() => _tutorialStep++);
    } else {
      await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'tutorial_seen': true}));
      if (mounted) setState(() => _showTutorial = false);
    }
  }

  void _regressTutorial() {
    if (_tutorialStep > 0) {
      setState(() => _tutorialStep--);
    }
  }

  Future<void> _navigateToSettingsWithTutorial({int startStep = 3}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SourceSettingsScreen(
          onRestartTutorial: _restartTutorial,
          tutorialStep: startStep,
          onTutorialComplete: _dismissTutorial,
        ),
      ),
    );
    if (mounted) {
      _fetchUserData();
      _fetchArticles();
    }
  }

  Future<void> _restartTutorial() async {
    await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'tutorial_seen': false}));
    if (mounted) setState(() { _showTutorial = true; _tutorialStep = 0; });
  }

  Future<void> _dismissTutorial() async {
    await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'tutorial_seen': true}));
    if (mounted) setState(() => _showTutorial = false);
  }

  static const int _currentVersionCode = _kAppVersionCode;
  bool _updateDialogShown = false;

  Future<void> _checkForUpdate() async {
    if (_updateDialogShown) return;
    try {
      final rows = await Supabase.instance.client
          .from('trl_app_version')
          .select()
          .order('version_code', ascending: false)
          .limit(1);
      if (rows.isEmpty) return;
      final latest = rows.first;
      final latestCode = (latest['version_code'] as num?)?.toInt() ?? 0;
      final latestName = latest['version_name']?.toString() ?? '';
      final downloadUrl = latest['download_url']?.toString() ?? '';
      final notes = latest['release_notes']?.toString() ?? '';
      final force = latest['force_update'] == true;
      if (latestCode <= _currentVersionCode || downloadUrl.isEmpty) return;
      if (!mounted) return;
      _updateDialogShown = true;
      showDialog(
        context: context,
        barrierDismissible: !force,
        builder: (ctx) {
          double progress = 0;
          bool downloading = false;
          return StatefulBuilder(
            builder: (context, setStateDialog) => AlertDialog(
              backgroundColor: const Color(0xFF1C1C1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Update Available', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Version $latestName is ready.', style: const TextStyle(color: Colors.white70)),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(notes, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                  if (downloading) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: progress > 0 ? progress : null,
                      backgroundColor: Colors.white12,
                      color: const Color(0xFFFF6200),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      progress > 0 ? '${(progress * 100).toStringAsFixed(0)}%' : 'Downloading...',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ],
              ),
              actions: [
                if (!force && !downloading)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Later', style: TextStyle(color: Colors.white38)),
                  ),
                if (!downloading)
                  TextButton(
                    onPressed: () async {
                      setStateDialog(() => downloading = true);
                      try {
                        final dir = await getTemporaryDirectory();
                        final filePath = '${dir.path}/trubrief_update.apk';
                        final file = File(filePath);
                        if (await file.exists()) await file.delete();

                        final ioClient = HttpClient();
                        final ioReq = await ioClient.getUrl(Uri.parse(downloadUrl));
                        ioReq.followRedirects = true;
                        ioReq.maxRedirects = 10;
                        ioReq.headers.set(HttpHeaders.userAgentHeader, 'TruBrief-Updater/1.0');
                        ioReq.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
                        final ioResp = await ioReq.close();

                        if (ioResp.statusCode < 200 || ioResp.statusCode >= 300) {
                          throw Exception('Server returned ${ioResp.statusCode}');
                        }

                        final total = ioResp.contentLength;
                        int received = 0;
                        final sink = file.openWrite();
                        await ioResp.listen((chunk) {
                          sink.add(chunk);
                          received += chunk.length;
                          if (total > 0) {
                            setStateDialog(() => progress = received / total);
                          }
                        }).asFuture();
                        await sink.flush();
                        await sink.close();
                        ioClient.close();

                        final fileSize = await file.length();
                        if (fileSize < 5000000) {
                          throw Exception('Download incomplete — only ${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB received. Check your connection and try again.');
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        await OpenFilex.open(filePath, type: 'application/vnd.android.package-archive');
                      } catch (e) {
                        debugPrint('Download error: $e');
                        if (ctx.mounted) {
                          setStateDialog(() { downloading = false; progress = 0; });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Update failed: $e'),
                              backgroundColor: const Color(0xFF8B0000),
                              duration: const Duration(seconds: 6),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Install Update', style: TextStyle(color: Color(0xFFFF6200), fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('Update check error: $e');
    }
  }

  Future<void> _fetchSavedArticles() async {
    final userId = _effectiveUserId;
    if (userId == null) return;
    try {
      final saved = await Supabase.instance.client
          .from('trl_saved_articles')
          .select('article_id')
          .eq('user_id', userId);
      if (mounted) {
        setState(() {
          _savedArticleIds.clear();
          for (var item in saved) {
            _savedArticleIds.add(item['article_id'].toString());
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching saved: $e');
    }
  }

  Future<void> _toggleSaveArticle(Map<String, dynamic> article) async {
    final userId = _effectiveUserId;
    if (userId == null) return;
    final rawId = article['id'];
    if (rawId == null) return;
    final articleId = rawId.toString();
    final isSaved = _savedArticleIds.contains(articleId);

    if (mounted) {
      setState(() {
        if (isSaved) {
          _savedArticleIds.remove(articleId);
        } else {
          _savedArticleIds.add(articleId);
        }
      });
    }

    try {
      if (isSaved) {
        await Supabase.instance.client
            .from('trl_saved_articles')
            .delete()
            .eq('user_id', userId)
            .eq('article_id', articleId);
      } else {
        final articleUrl = _cleanXmlContent(article['original_url']).isNotEmpty
            ? _cleanXmlContent(article['original_url'])
            : article['url']?.toString() ?? '';
        await Supabase.instance.client
            .from('trl_saved_articles')
            .upsert({
              'user_id': userId,
              'article_id': articleId,
              'title': article['title']?.toString() ?? '',
              'url': articleUrl,
              'source_name': article['source_name']?.toString() ?? '',
              'thumbnail_url': article['image_url']?.toString() ?? '',
            }, onConflict: 'user_id,article_id', ignoreDuplicates: true);
      }
    } catch (e) {
      debugPrint('Error toggling save: ${e.runtimeType}: $e');
      if (mounted) {
        setState(() {
          if (isSaved) {
            _savedArticleIds.add(articleId);
          } else {
            _savedArticleIds.remove(articleId);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isSaved ? 'Could not remove bookmark.' : 'Could not save article. Please try again.'),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _archiveOldArticles() async {
    try {
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
      
      // 1. Find articles older than 7 days
      final oldArticles = await Supabase.instance.client
          .from('trl_articles')
          .select()
          .lt('created_at', sevenDaysAgo)
          .limit(100); // Process in batches to avoid timeouts

      if (oldArticles.isEmpty) return;

      // 2. Insert into archive
      await Supabase.instance.client.from('trl_articles_archive').insert(oldArticles);

      // 3. Delete from active
      final List<String> oldIds = oldArticles.map((a) => a['id'].toString()).toList();
      await Supabase.instance.client.from('trl_articles').delete().inFilter('id', oldIds);
      
      debugPrint('Archived ${oldIds.length} old articles');

      // --- SMART PURGE: Delete 30d+ archive unless saved ---
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
      
      // 1. Get all saved article IDs to protect them
      final savedArticles = await Supabase.instance.client
          .from('trl_saved_articles')
          .select('article_id');
      final List<String> protectedIds = savedArticles.map((s) => s['article_id'].toString()).toList();

      // 2. Delete anything older than 30 days that is NOT in the protected list
      var purgeQuery = Supabase.instance.client
          .from('trl_articles_archive')
          .delete()
          .lt('created_at', thirtyDaysAgo);

      if (protectedIds.isNotEmpty) {
        purgeQuery = purgeQuery.not('id', 'in', '(${protectedIds.join(",")})');
      }
      
      await purgeQuery;
      debugPrint('Smart Purge completed.');
    } catch (e) {
      debugPrint('Archive error: $e');
    }
  }

  Future<void> _ensureDefaultSourcesExist() async {
    // Sources are now seeded via SQL migrations. 
    // This method remains as a placeholder or for dynamic runtime checks.
    try {
      final List<dynamic> dbSources = await Supabase.instance.client.from('trl_sources').select();
      debugPrint('Found ${dbSources.length} sources in database.');
    } catch (e) {
      debugPrint('Error checking sources: $e');
    }
  }

  @override
  void dispose() {
    _tutorialPulse.dispose();
    _isDisposed = true;
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    final userId = _effectiveUserId;
    if (userId == null) return;

    try {
      // 1. Fetch Categories from DB (Dynamic)
      final catData = await Supabase.instance.client
          .from('trl_categories')
          .select()
          .order('display_order', ascending: true);
      
      if (catData != null && catData.isNotEmpty && mounted) {
        setState(() {
          _virtualCategories = List<String>.from(catData.where((c) => c['is_virtual'] == true && c['name'] != 'Weekly Top').map((c) => c['name']));
          
          // Default all categories from DB first
          final List<String> dbCats = List<String>.from(catData.map((c) => c['name'])).where((c) => c != 'Weekly Top').toList();
          _categories = dbCats;
          debugPrint('Fetched ${_categories.length} categories from DB');
        });
      } else {
        debugPrint('Warning: No categories found in DB or empty response');
      }

      // 2. Fetch all sources (for paywall detection) — non-fatal if it fails
      try {
        final sourcesData = await Supabase.instance.client
            .from('trl_sources')
            .select('id, name, category, requires_subscription');
        if (mounted) {
          setState(() => _allSources = List<dynamic>.from(sourcesData));
        }
      } catch (e) {
        debugPrint('Sources fetch error: $e');
      }

      // 3. Fetch User Preferences
      final prefs = await Supabase.instance.client
          .from('trl_user_preferences')
          .select()
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle();
      
      if (prefs != null && mounted) {
        setState(() {
          _locationType = prefs['location_type'] ?? 'none';
          _zipCode = _locationType == 'none' ? null : prefs['zip_code'];
          _city = _locationType == 'none' ? null : prefs['city'];
          _state = _locationType == 'none' ? null : prefs['state'];
          _county = _locationType == 'none' ? null : prefs['county'];
          _hiddenTabs = Set<String>.from(prefs['hidden_tabs'] ?? []);
          _selectedSources = List<String>.from(prefs['selected_sources'] ?? []);
          
          final List<String> savedOrder = List<String>.from(prefs['selected_categories'] ?? []);
          
          // Reconstruct _categories based on saved order, then add any NEW categories from DB at the end
          final List<String> orderedCats = [];
          for (var catName in savedOrder) {
            if (_categories.contains(catName)) {
              orderedCats.add(catName);
            }
          }
          
          // Add remaining categories from DB that weren't in the saved order
          for (var dbCat in _categories) {
            if (!orderedCats.contains(dbCat)) {
              orderedCats.add(dbCat);
            }
          }

          _categories = orderedCats.where((c) => c != 'Weekly Top').toList();
          
          // Ensure Tru Brief is ALWAYS first
          if (_categories.contains('Tru Brief')) {
            _categories.remove('Tru Brief');
            _categories.insert(0, 'Tru Brief');
          }

          _selectedCategories = List<String>.from(savedOrder).where((c) => c != 'Weekly Top').toList();
          
          if (_selectedCategories.isEmpty) {
            _selectedCategories = ['Tru Brief', 'Local Brief', 'Weather Brief'];
          }
        });
      }

      // 3. Fetch Subscription
      final sub = await Supabase.instance.client
          .from('trl_subscriptions')
          .select()
          .eq('user_id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      
      if (sub != null && mounted) {
        setState(() {
          _isPremium = sub['status'] == 'active';
          // Check if trial is within 7 days
          if (sub['trial_started_at'] != null) {
            final trialStart = DateTime.parse(sub['trial_started_at']);
            _isTrialActive = DateTime.now().difference(trialStart).inDays < 7;
          }
        });
      }

      _fetchArticles(); // Re-fetch now that we know the user's selected categories
    } catch (e) {
      debugPrint('User data error: $e');
    }
  }

  Future<List<dynamic>> _fetchGoogleNewsLocal() async {
    final List<Future<List<dynamic>>> fetches = [];

    if (_city != null && _city!.isNotEmpty && _state != null && _state!.isNotEmpty) {
      // Query 1: Exact city
      fetches.add(_fetchGoogleNewsQuery(
        Uri.encodeComponent('"$_city" "$_state" local news'),
      ));

      // Query 2: County-level — covers nearby cities naturally
      if (_county != null && _county!.isNotEmpty) {
        final countyName = _county!.replaceAll(RegExp(r'\s*[Cc]ounty$'), '').trim();
        fetches.add(_fetchGoogleNewsQuery(
          Uri.encodeComponent('"$countyName County" "$_state" local news'),
        ));
        // Query 3: County name without "County" — surfaces major city (e.g. Tampa for Hillsborough)
        fetches.add(_fetchGoogleNewsQuery(
          Uri.encodeComponent('"$countyName" "$_state" news'),
        ));
      }
    } else if (_zipCode != null && _zipCode!.isNotEmpty) {
      fetches.add(_fetchGoogleNewsQuery(
        Uri.encodeComponent('"$_zipCode" local news'),
      ));
    }

    if (fetches.isEmpty) return [];

    final results = await Future.wait(fetches);

    // Merge and deduplicate by URL, preserving order (city-specific first)
    final seen = <String>{};
    final merged = <dynamic>[];
    for (final articles in results) {
      for (final article in articles) {
        final url = article['original_url'] as String;
        if (seen.add(url)) {
          merged.add(article);
        }
      }
    }

    // Sort by date descending
    merged.sort((a, b) {
      final da = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(0);
      final db = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(0);
      return db.compareTo(da);
    });

    return merged;
  }

  String _getGoogleNewsLocaleParams() {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final lang = locale.languageCode.toLowerCase();
    final country = locale.countryCode?.toUpperCase() ?? '';
    if (lang == 'pt' || country == 'BR') return 'hl=pt-BR&gl=BR&ceid=BR:pt';
    if (lang == 'es') return 'hl=es&gl=ES&ceid=ES:es';
    if (lang == 'fr') return 'hl=fr&gl=FR&ceid=FR:fr';
    if (lang == 'de') return 'hl=de&gl=DE&ceid=DE:de';
    if (lang == 'ja') return 'hl=ja&gl=JP&ceid=JP:ja';
    return 'hl=en-US&gl=US&ceid=US:en';
  }

  Future<List<dynamic>> _fetchGoogleNewsQuery(String encodedQuery, {String? localeParams}) async {
    final params = localeParams ?? _getGoogleNewsLocaleParams();
    final url = 'https://news.google.com/rss/search?q=when:72h+$encodedQuery&$params';
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      final xml = res.body;
      final items = RegExp(r'<item>(.*?)</item>', dotAll: true).allMatches(xml);
      final List<dynamic> articles = [];
      for (var match in items) {
        final item = match.group(1)!;
        final rawTitle = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(item)?.group(1) ?? '';
        final link = RegExp(r'<link>(.*?)</link>', dotAll: true).firstMatch(item)?.group(1)?.trim() ?? '';
        final pubDateStr = RegExp(r'<pubDate>(.*?)</pubDate>', dotAll: true).firstMatch(item)?.group(1)?.trim();
        final sourceMatch = RegExp(r'<source[^>]*>(.*?)</source>', dotAll: true).firstMatch(item);
        final sourceName = sourceMatch?.group(1)?.trim() ?? 'Local News';
        final title = _cleanXmlContent(rawTitle);
        final titleParts = title.split(' - ');
        final cleanTitle = titleParts.length > 1 ? titleParts.sublist(0, titleParts.length - 1).join(' - ') : title;

        if (link.isEmpty || cleanTitle.isEmpty) continue;

        articles.add({
          'id': link.hashCode.toString(),
          'title': cleanTitle,
          'original_url': link,
          'image_url': null,
          'summary_brief': null,
          'category': 'Local Brief',
          'source_name': sourceName,
          'source_id': null,
          'created_at': _parseRssDate(pubDateStr),
        });
      }
      return articles;
    } catch (e) {
      debugPrint('Google News local fetch error: $e');
      return [];
    }
  }

  Future<void> _fetchFlashBriefArticles() async {
    if (mounted) setState(() => _loading = true);
    try {
      final feeds = [
        'https://feeds.foxnews.com/foxnews/latest',
        'https://rss.cnn.com/rss/edition.rss',
        'https://feeds.nbcnews.com/nbcnews/public/news',
        'https://rss.politico.com/politics-news.xml',
        'https://feeds.abcnews.com/abcnews/topstories',
        'https://feeds.cbsnews.com/cbsnews/rss/latest',
        'https://feeds.npr.org/1001/rss.xml',
        'https://feeds.reuters.com/reuters/topNews',
        'https://thehill.com/rss/syndicator/19110',
        'https://rss.dw.com/rdf/rss-en-top',
      ];
      final List<Future<List<dynamic>>> fetches = feeds.map((feedUrl) => _fetchRssFeed(feedUrl)).toList();
      fetches.add(_fetchGoogleNewsTopStories());
      final results = await Future.wait(fetches.map((f) => f.catchError((_) => <dynamic>[])));
      final seen = <String>{};
      final merged = <dynamic>[];
      for (final articles in results) {
        for (final article in articles) {
          final url = (article['original_url'] ?? '').toString();
          if (url.isNotEmpty && seen.add(url)) merged.add(article);
        }
      }
      merged.sort((a, b) {
        final da = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(0);
        final db = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(0);
        return db.compareTo(da);
      });
      final deduped = _deduplicateByTopic(merged);
      if (mounted) setState(() { _articles = deduped; _loading = false; });
    } catch (e) {
      debugPrint('Tru Flash error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<dynamic>> _fetchGoogleNewsTopStories() async {
    return _fetchGoogleNewsQuery(Uri.encodeComponent('top stories'));
  }

  Future<List<dynamic>> _fetchRssFeed(String feedUrl) async {
    try {
      final res = await http.get(Uri.parse(feedUrl), headers: {'User-Agent': 'TruBrief/1.0'}).timeout(const Duration(seconds: 10));
      final xml = res.body;
      final items = RegExp(r'<item>(.*?)</item>', dotAll: true).allMatches(xml);
      final List<dynamic> articles = [];
      final sourceNameMatch = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(xml)?.group(1) ?? 'News';
      final cleanSourceName = _cleanXmlContent(sourceNameMatch).split('\n').first.trim();
      for (var match in items.take(15)) {
        final item = match.group(1)!;
        final rawTitle = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(item)?.group(1) ?? '';
        final link = (RegExp(r'<link>(.*?)</link>', dotAll: true).firstMatch(item)?.group(1) ??
                      RegExp(r'<guid[^>]*>(.*?)</guid>', dotAll: true).firstMatch(item)?.group(1) ?? '').trim();
        final pubDateStr = RegExp(r'<pubDate>(.*?)</pubDate>', dotAll: true).firstMatch(item)?.group(1)?.trim();
        final desc = RegExp(r'<description>(.*?)</description>', dotAll: true).firstMatch(item)?.group(1) ?? '';
        final imgMatch = RegExp(r'<media:content[^>]*url="([^"]+)"', dotAll: true).firstMatch(item) ??
                         RegExp(r'<enclosure[^>]*url="([^"]+)"', dotAll: true).firstMatch(item);
        final imageUrl = imgMatch?.group(1);
        final title = _cleanXmlContent(rawTitle);
        final titleParts = title.split(' - ');
        final cleanTitle = titleParts.length > 1 ? titleParts.sublist(0, titleParts.length - 1).join(' - ') : title;
        if (link.isEmpty || cleanTitle.isEmpty) continue;
        final cleanDesc = _cleanDescription(desc);
        articles.add({
          'id': link.hashCode.toString(),
          'title': cleanTitle,
          'original_url': link,
          'image_url': imageUrl,
          'summary_brief': cleanDesc.isNotEmpty ? cleanDesc.substring(0, cleanDesc.length.clamp(0, 200)) : null,
          'category': 'Tru Flash',
          'source_name': cleanSourceName,
          'source_id': null,
          'created_at': _parseRssDate(pubDateStr),
        });
      }
      return articles;
    } catch (e) {
      debugPrint('RSS feed error for $feedUrl: $e');
      return [];
    }
  }

  Future<void> _fetchArticles() async {
    try {
      if (mounted) setState(() => _loading = true);

      var query = Supabase.instance.client.from('trl_articles').select();

      final search = _searchController.text.trim();
      if (search.isNotEmpty) {
        query = query.ilike('title', '%$search%');
      } else {
        if (_selectedCategory == 'Tru Flash') {
          final sourceEntry = _kFlashSources.firstWhere(
            (s) => s['name'] == _flashSelectedSource,
            orElse: () => _kFlashSources.first,
          );
          await _fetchFlashBySourceAndTopic(_flashSelectedSource, sourceEntry['url']!);
          return;
        } else if (_selectedCategory == 'Local Brief' && _locationType != 'none') {
          final localArticles = _deduplicateByTopic(_filterGeoRestricted(await _fetchGoogleNewsLocal()));
          if (mounted) {
            setState(() {
              _articles = localArticles;
              _loading = false;
            });
            _repairMissingImages();
          }
          return;
        } else if (_selectedCategory == 'Tru Brief') {
          // TRU BRIEF: Fetch articles from ALL selected sources
          if (_selectedSources.isEmpty) {
            if (mounted) setState(() { _articles = []; _loading = false; });
            return;
          }
          query = query.inFilter('source_id', _selectedSources);
        } else {
          if (_currentCategoryHasNoActiveSources) {
            if (mounted) setState(() { _articles = []; _loading = false; });
            return;
          }
          final shortCat = _selectedCategory.replaceAll(' Brief', '').replaceAll(' News', '').trim();
          query = query.or('category.eq."$_selectedCategory",category.eq."$shortCat",category.eq."$shortCat Brief",category.eq."$shortCat News"');
        }
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(150)
          .timeout(const Duration(seconds: 10));

      final interleaved = _deduplicateByTopic(_filterGeoRestricted(_interleaveBySource(List<dynamic>.from(response))));

      if (mounted) {
        setState(() {
          _articles = interleaved;
        });
        _repairMissingImages();
      }
    } catch (e) {
      debugPrint('Fetch error: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<dynamic> _filterGeoRestricted(List<dynamic> articles) {
    final countryCode = WidgetsBinding.instance.platformDispatcher.locale.countryCode?.toUpperCase() ?? '';
    return articles.where((article) {
      final url = (article['original_url'] ?? '').toString().toLowerCase();
      if (countryCode != 'GB' && url.contains('/iplayer/')) return false;
      if (countryCode != 'US' && url.contains('//www.hulu.com')) return false;
      if (countryCode != 'US' && url.contains('//www.espn.com/watch')) return false;
      return true;
    }).toList();
  }

  static const _stopWords = {
    'a','an','the','and','or','but','in','on','at','to','for','of','with',
    'is','are','was','were','be','been','being','have','has','had','do','does',
    'did','will','would','could','should','may','might','can','it','its',
    'this','that','these','those','by','from','as','up','about','into',
    'after','before','during','over','under','not','no','new','two','one',
    'man','woman','men','women','says','said','than','more','what',
    'how','who','when','where','why','he','she','they','we','his','her',
    'their','our','us','him','them','my','your','i','you','all','also','just',
  };

  Set<String> _titleKeywords(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3 && !_stopWords.contains(w))
        .toSet();
  }

  List<dynamic> _deduplicateByTopic(List<dynamic> articles, {double threshold = 0.25}) {
    final List<Map<String, dynamic>> result = [];
    final List<Set<String>> seenKeywordSets = [];

    for (final article in articles) {
      final title = (article['title'] ?? '').toString();
      final keywords = _titleKeywords(title);
      if (keywords.isEmpty) {
        result.add(Map<String, dynamic>.from(article as Map));
        continue;
      }
      bool found = false;
      for (int i = 0; i < seenKeywordSets.length; i++) {
        final intersection = keywords.intersection(seenKeywordSets[i]).length;
        final union = keywords.union(seenKeywordSets[i]).length;
        if (union > 0 && intersection >= 2 && intersection / union >= threshold) {
          final related = List<dynamic>.from(result[i]['_related_articles'] as List? ?? []);
          related.add(article);
          result[i] = {...result[i], '_related_articles': related};
          found = true;
          break;
        }
      }
      if (!found) {
        result.add({...Map<String, dynamic>.from(article as Map), '_related_articles': <dynamic>[]});
        seenKeywordSets.add(keywords);
      }
    }
    return result;
  }

  List<dynamic> _interleaveBySource(List<dynamic> articles) {
    final Map<String, List<dynamic>> bySource = {};
    for (final article in articles) {
      final key = article['source_id']?.toString() ?? article['source_name']?.toString() ?? 'unknown';
      bySource.putIfAbsent(key, () => []).add(article);
    }

    final List<List<dynamic>> buckets = bySource.values.toList();
    final List<dynamic> result = [];
    int i = 0;
    while (result.length < 50) {
      bool anyLeft = false;
      for (final bucket in buckets) {
        if (i < bucket.length) {
          result.add(bucket[i]);
          anyLeft = true;
          if (result.length == 50) break;
        }
      }
      if (!anyLeft) break;
      i++;
    }
    return result;
  }

  Future<void> _repairMissingImages() async {
    final limit = _articles.length < 30 ? _articles.length : 30;
    for (var i = 0; i < limit; i++) {
      final article = _articles[i];
      if (article['image_url'] == null || article['image_url'].toString().isEmpty) {
        final url = _cleanXmlContent(article['original_url']);
        if (url.isEmpty) continue;
        try {
          final imageUrl = await _scrapeImageUrl(url);
          if (imageUrl != null && imageUrl.isNotEmpty) {
            final isInMemoryOnly = article['source_id'] == null;
            if (!isInMemoryOnly) {
              await Supabase.instance.client
                  .from('trl_articles')
                  .update({'image_url': imageUrl})
                  .eq('id', article['id']);
            }
            _articles[i] = Map<String, dynamic>.from(article)..['image_url'] = imageUrl;
            if (mounted) setState(() {});
          }
        } catch (e) {
          debugPrint('Repair error for ${article['id']}: $e');
        }
      }
    }
  }

  /// PROACTIVE INGESTION: Fetches new articles directly from the app
  /// This ensures the app stays updated even without a backend worker.
  Future<void> _fetchNewArticlesFromSources() async {
    if (_isIngesting || _isDisposed) return;
    _isIngesting = true;
    try {
      final List<dynamic> dbSources = await Supabase.instance.client.from('trl_sources').select();
      final List<Map<String, dynamic>> sources = List<Map<String, dynamic>>.from(dbSources);

      // FORCE FIX: Sweep 200 "Tech" articles and correct them to their source's category
      final techArticles = await Supabase.instance.client
          .from('trl_articles')
          .select('id, source_id')
          .eq('category', 'Tech')
          .limit(200);
      
      for (var art in techArticles) {
        final parentSource = sources.cast<Map<String, dynamic>?>().firstWhere(
          (s) => s?['id'] == art['source_id'], 
          orElse: () => null
        );
        if (parentSource != null) {
          await Supabase.instance.client
              .from('trl_articles')
              .update({'category': parentSource['category']})
              .eq('id', art['id']);
        }
      }

      int newArticlesCount = 0;
      for (var source in sources) {
        if (_isDisposed) break;
        if (source['requires_subscription'] == true) continue;
        final res = await http.get(Uri.parse(source['url'])).timeout(const Duration(seconds: 10));
        final xml = res.body;

        final items = RegExp(r'<item>(.*?)</item>', dotAll: true).allMatches(xml);
        for (var match in items) {
          final item = match.group(1)!;
          final title = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(item)?.group(1);
          final link = RegExp(r'<link>(.*?)</link>', dotAll: true).firstMatch(item)?.group(1);
          final description = RegExp(r'<description>(.*?)</description>', dotAll: true).firstMatch(item)?.group(1);
          final pubDateStr = RegExp(r'<pubDate>(.*?)</pubDate>', dotAll: true).firstMatch(item)?.group(1);
          
          if (title == null || link == null) continue;

          final originalUrl = _cleanXmlContent(link);
          final existing = await Supabase.instance.client
              .from('trl_articles')
              .select()
              .eq('original_url', originalUrl)
              .maybeSingle();

          if (existing == null) {
            String? imageUrl = _extractRssImage(item) ?? await _scrapeImageUrl(originalUrl);
            DateTime pubDate;
            try {
              // Note: This is a simple RSS date parse. Real RSS may need intl package.
              pubDate = pubDateStr != null ? DateTime.tryParse(pubDateStr) ?? DateTime.now() : DateTime.now();
            } catch (_) {
              pubDate = DateTime.now();
            }

            await Supabase.instance.client.from('trl_articles').insert({
              'title': _cleanXmlContent(title),
              'original_url': originalUrl,
              'image_url': imageUrl,
              'summary_brief': _cleanDescription(description),
              'category': source['category'],
              'source_name': source['name'],
              'source_id': source['id'],
              'created_at': pubDate.toIso8601String(),
            });
            newArticlesCount++;
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $newArticlesCount new Briefs'), backgroundColor: Colors.green),
        );
      }
      // Re-fetch local list once background ingestion completes
      if (mounted && !_isDisposed) _fetchArticles(); 
    } catch (e) {
      debugPrint('Background ingestion failed: $e');
    } finally {
      _isIngesting = false;
    }
  }

  String? _extractRssImage(String itemXml) {
    // 1. media:content url
    final mediaContent = RegExp(r'<media:content[^>]+url="([^"]+)"', caseSensitive: false).firstMatch(itemXml);
    if (mediaContent != null) return _cleanXmlContent(mediaContent.group(1));

    // 2. media:thumbnail url
    final mediaThumbnail = RegExp(r'<media:thumbnail[^>]+url="([^"]+)"', caseSensitive: false).firstMatch(itemXml);
    if (mediaThumbnail != null) return _cleanXmlContent(mediaThumbnail.group(1));

    // 3. enclosure (image type)
    final enclosure = RegExp(r'<enclosure[^>]+url="([^"]+)"[^>]+type="image/[^"]*"', caseSensitive: false).firstMatch(itemXml) ??
                      RegExp(r'<enclosure[^>]+type="image/[^"]*"[^>]+url="([^"]+)"', caseSensitive: false).firstMatch(itemXml);
    if (enclosure != null) return _cleanXmlContent(enclosure.group(1));

    // 4. <img src="..."> or src='...' inside description/content
    final imgTag = RegExp(r'''<img[^>]+src=["'](https?://[^"']+)["']''', caseSensitive: false).firstMatch(itemXml);
    if (imgTag != null) return _cleanXmlContent(imgTag.group(1));

    return null;
  }

  Future<String?> _scrapeImageUrl(String? rawUrl) async {
    if (rawUrl == null || rawUrl.isEmpty) return null;
    final url = _cleanXmlContent(rawUrl);
    // Skip Google-owned pages — they return the Google News logo, not article images
    if (Uri.tryParse(url)?.host.contains('google.com') == true) return null;
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 5));
      
      final html = res.body;
      
      // 1. OG Image
      final ogMatch = RegExp(r'<meta[^>]*property="og:image"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html) ??
                      RegExp(r'<meta[^>]*content="([^"]*)"[^>]*property="og:image"', caseSensitive: false).firstMatch(html);
      if (ogMatch != null) return _cleanXmlContent(ogMatch.group(1));

      // 2. Twitter Image
      final twMatch = RegExp(r'<meta[^>]*name="twitter:image"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html) ??
                      RegExp(r'<meta[^>]*content="([^"]*)"[^>]*name="twitter:image"', caseSensitive: false).firstMatch(html);
      if (twMatch != null) return _cleanXmlContent(twMatch.group(1));

      // 3. Schema.org itemprop
      final itemPropMatch = RegExp(r'<meta[^>]*itemprop="image"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html);
      if (itemPropMatch != null) return _cleanXmlContent(itemPropMatch.group(1));

      // 4. JSON-LD structured data (used by Forbes, NYT, many publishers)
      final jsonLdMatch = RegExp(r'"image"\s*:\s*\{\s*"[^"]*"\s*:\s*"[^"]*"\s*,\s*"url"\s*:\s*"([^"]+)"', caseSensitive: false).firstMatch(html) ??
                          RegExp(r'"image"\s*:\s*"(https?://[^"]+)"', caseSensitive: false).firstMatch(html) ??
                          RegExp(r'"thumbnailUrl"\s*:\s*"(https?://[^"]+)"', caseSensitive: false).firstMatch(html) ??
                          RegExp(r'"url"\s*:\s*"(https?://[^"]*(?:\.jpg|\.jpeg|\.png|\.webp)[^"]*)"', caseSensitive: false).firstMatch(html);
      if (jsonLdMatch != null) return _cleanXmlContent(jsonLdMatch.group(1));

      // 5. First large <img> in article body
      final imgMatch = RegExp(r'<img[^>]+src="(https?://[^"]+\.(?:jpg|jpeg|png|webp)[^"]*)"', caseSensitive: false).firstMatch(html);
      if (imgMatch != null) return _cleanXmlContent(imgMatch.group(1));

      return null;
    } catch (e) {
      debugPrint('Scrape error for $url: $e');
      return null;
    }
  }

  static const _kMonths = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  String _parseRssDate(String? raw) {
    if (raw == null || raw.isEmpty) return DateTime.now().toIso8601String();
    // Try ISO 8601 first
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso.toIso8601String();
    // Parse RFC 2822: "Tue, 01 Apr 2025 08:30:00 +0000" or "...GMT"
    try {
      final parts = raw.trim().split(RegExp(r'[\s,]+'));
      // parts may look like: ['Tue', '01', 'Apr', '2025', '08:30:00', '+0000']
      // or without day-of-week: ['01', 'Apr', '2025', '08:30:00', '+0000']
      final idx = (parts.length >= 6) ? 1 : 0;
      final day = int.parse(parts[idx]);
      final month = _kMonths[parts[idx + 1].toLowerCase().substring(0, 3)] ?? 1;
      final year = int.parse(parts[idx + 2]);
      final timeParts = parts[idx + 3].split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final second = timeParts.length > 2 ? int.parse(timeParts[2]) : 0;
      int tzOffset = 0;
      if (parts.length > idx + 4) {
        final tz = parts[idx + 4];
        if (tz != 'GMT' && tz != 'UTC' && tz.length >= 5) {
          final sign = tz[0] == '-' ? -1 : 1;
          final tzH = int.tryParse(tz.substring(1, 3)) ?? 0;
          final tzM = int.tryParse(tz.substring(3, 5)) ?? 0;
          tzOffset = sign * (tzH * 60 + tzM);
        }
      }
      final dt = DateTime.utc(year, month, day, hour, minute, second)
          .subtract(Duration(minutes: tzOffset));
      return dt.toIso8601String();
    } catch (_) {
      return DateTime.now().toIso8601String();
    }
  }

  String _cleanXmlContent(String? text) {
    if (text == null) return '';
    String cleaned = text.trim();
    if (cleaned.startsWith('<![CDATA[')) {
      cleaned = cleaned.substring(9);
    }
    if (cleaned.endsWith(']]>')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    return cleaned.trim();
  }

  String _cleanDescription(String? text) {
    if (text == null || text.isEmpty) return '';
    String cleaned = text.trim();
    if (cleaned.startsWith('<![CDATA[')) cleaned = cleaned.substring(9);
    if (cleaned.endsWith(']]>')) cleaned = cleaned.substring(0, cleaned.length - 3);
    cleaned = HtmlCharacterEntities.decode(cleaned);
    cleaned = cleaned.replaceAll(RegExp(r'<[^>]+>'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  String _unescapeHtml(String? text) {
    if (text == null) return '';
    return HtmlCharacterEntities.decode(text);
  }

  String _getTimeAgo(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'Just now';
    try {
      final date = DateTime.parse(dateStr);
      final diff = DateTime.now().difference(date);
      
      if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y ago';
      if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
      if (diff.inDays > 0) return '${diff.inDays}d ago';
      if (diff.inHours > 0) return '${diff.inHours}h ago';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
      return 'Just now';
    } catch (e) {
      return 'Just now';
    }
  }

  void _showRelatedSources(BuildContext context, Map<String, dynamic> primaryArticle, List<dynamic> related) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  'Covered by ${related.length + 1} sources',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _unescapeHtml(primaryArticle['title'] ?? ''),
                  style: const TextStyle(fontSize: 13, color: Colors.white60, height: 1.4),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white12, height: 1),
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _openArticle(primaryArticle);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 8, color: Color(0xFFFF6200)),
                      const SizedBox(width: 12),
                      Text(
                        _unescapeHtml(primaryArticle['source_name'] ?? 'Unknown'),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
                    ],
                  ),
                ),
              ),
              ...related.map((a) => InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _openArticle(Map<String, dynamic>.from(a as Map));
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 8, color: Colors.white24),
                      const SizedBox(width: 12),
                      Text(
                        _unescapeHtml((a as Map)['source_name']?.toString() ?? 'Unknown'),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
                    ],
                  ),
                ),
              )),
              const Divider(color: Colors.white12, height: 1),
              if (!_isPremium && !_isTrialActive)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFFF6200)),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Get an AI-combined summary of all sources — subscribe to TruBrief AI.',
                          style: TextStyle(fontSize: 12, color: Colors.white54, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
            ),
          ),
        );
      },
    );
  }

  void _openArticle(Map<String, dynamic> article) {
    final url = _cleanXmlContent(article['original_url']);
    if (url.isEmpty) return;
    String? sourceLoginUrl;
    try {
      final uri = Uri.parse(url);
      String host = uri.host;
      const hostRemap = {
        'feeds.a.dj.com': 'www.wsj.com',
        'feeds.bloomberg.com': 'www.bloomberg.com',
        'feeds.apnews.com': 'apnews.com',
        'feeds.washingtonpost.com': 'www.washingtonpost.com',
        'feeds.npr.org': 'www.npr.org',
        'rss.nytimes.com': 'www.nytimes.com',
        'rss.cnn.com': 'www.cnn.com',
        'feeds.bbci.co.uk': 'www.bbc.co.uk',
        'newsnetwork.mayoclinic.org': 'www.mayoclinic.org',
        'rssfeeds.webmd.com': 'www.webmd.com',
      };
      host = hostRemap[host] ?? host.replaceFirst(RegExp(r'^(feeds?\d*|rss)\.'), 'www.');
      sourceLoginUrl = 'https://$host';
    } catch (_) {}
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ArticleReaderScreen(
          url: url,
          sourceName: _unescapeHtml(article['source_name'] ?? 'The news source'),
          articleTitle: _unescapeHtml(article['title'] ?? ''),
          aiSummary: _unescapeHtml(article['summary_brief']),
          isSubscribed: _isPremium || _isTrialActive,
          sourceLoginUrl: sourceLoginUrl,
          initialIsSaved: _savedArticleIds.contains(article['id']?.toString() ?? ''),
          onToggleSave: () => _toggleSaveArticle(article),
          articleId: article['id']?.toString(),
        ),
      ),
    );
  }

  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SourceSettingsScreen(onRestartTutorial: _restartTutorial)),
    ).then((_) {
      if (mounted) {
        _fetchUserData();
        _fetchArticles();
        _loadFlashEnabledSources();
      }
    });
  }

  Widget _buildTutorialOverlay() {
    const steps = [
      (
        icon: Icons.auto_awesome_rounded,
        title: 'Welcome to Tru Brief',
        body: 'The Tru Brief tab is your personalized news digest — a single curated feed built from the sources and categories you choose. Everything in this app is designed around it.',
        arrowUp: false,
      ),
      (
        icon: Icons.grid_view_rounded,
        title: 'Your Feed Tabs',
        body: 'Tap the grid icon at the top right to browse and add news categories to your feed.',
        arrowUp: true,
      ),
      (
        icon: Icons.article_rounded,
        title: 'Reading an Article',
        body: 'Tap any article card to read it. Tap the bookmark icon to save it for later.',
        arrowUp: false,
      ),
      (
        icon: Icons.layers_rounded,
        title: 'Multiple Sources',
        body: 'When a story shows "Reported by "x" sources", tap it to see how different outlets cover it.',
        arrowUp: false,
      ),
      (
        icon: Icons.tune_rounded,
        title: 'Customize Your Briefs',
        body: 'Tap the Settings ⚙ Icon to choose which feeds and sources appear in your personal Tru Brief.',
        arrowUp: true,
      ),
      (
        icon: Icons.location_on_rounded,
        title: 'Location Settings',
        body: 'Set your zip code or use GPS to get local news tailored to your area in the Local Brief tab.',
        arrowUp: false,
      ),
      (
        icon: Icons.rss_feed_rounded,
        title: 'My Feed',
        body: 'View and manage your active categories. Tap any category to customize which sources appear in your feed.',
        arrowUp: false,
      ),
      (
        icon: Icons.apps_rounded,
        title: 'Available Feeds',
        body: 'Browse all news categories. Toggle Feed to include sources in Tru Brief, or Tab to add it as a browsable tab — independently.',
        arrowUp: false,
      ),
      (
        icon: Icons.mark_email_read_outlined,
        title: 'Newsletters',
        body: 'Add your favorite email newsletters to TruBrief for a complete, all-in-one reading experience.',
        arrowUp: false,
      ),
    ];

    final step = steps[_tutorialStep];
    const totalSteps = 9;
    const isLast = false;

    Rect? getHighlightRect() {
      GlobalKey? key;
      if (_tutorialStep == 0) {
        key = _truBriefTabKey;
      } else if (_tutorialStep == 1) {
        key = _gridIconKey;
      } else if (_tutorialStep == 4) {
        key = _settingsButtonKey;
      }
      if (key == null) return null;
      final ctx = key.currentContext;
      if (ctx == null) return null;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) return null;
      return box.localToGlobal(Offset.zero) & box.size;
    }

    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _tutorialPulse,
        builder: (context, child) {
          final highlightRect = getHighlightRect();
          final screenHeight = MediaQuery.of(context).size.height;
          double? cardTop;
          double? cardBottom;
          if (highlightRect != null) {
            if (highlightRect.center.dy < screenHeight / 2) {
              cardBottom = 120;
            } else {
              cardTop = 80;
            }
          } else {
            cardTop = step.arrowUp ? 80 : null;
            cardBottom = step.arrowUp ? null : 120;
          }
          return CustomPaint(
            painter: _SpotlightPainter(highlightRect: highlightRect, pulse: _tutorialPulse.value),
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned(
                    top: cardTop,
                    bottom: cardBottom,
                    left: 20,
                    right: 20,
                    child: child!,
                  ),
                ],
              ),
            ),
          );
        },
        child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_tutorialStep),
                    child: GestureDetector(
                      onHorizontalDragEnd: (details) {
                        if ((details.primaryVelocity ?? 0) < -200) {
                          _advanceTutorial();
                        } else if ((details.primaryVelocity ?? 0) > 200) {
                          _regressTutorial();
                        }
                      },
                      child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF161618),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.25), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF6200).withValues(alpha: 0.12),
                            blurRadius: 40,
                            spreadRadius: 0,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 24,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: 3,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [const Color(0xFFFF6200), const Color(0xFFFF6200).withValues(alpha: 0.0)],
                                  stops: [(_tutorialStep + 1) / totalSteps, (_tutorialStep + 1) / totalSteps],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFFFF6200), Color(0xFFFF8C42)],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Icon(step.icon, color: Colors.white, size: 22),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${_tutorialStep + 1} of $totalSteps',
                                              style: const TextStyle(
                                                color: Color(0xFFFF6200),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.8,
                                                decoration: TextDecoration.none,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              step.title,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 18,
                                                letterSpacing: -0.3,
                                                decoration: TextDecoration.none,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: _dismissTutorial,
                                        child: Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.07),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(Icons.close_rounded, color: Colors.white38, size: 16),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    step.body,
                                    style: const TextStyle(
                                      color: Color(0xFFAAAAAA),
                                      fontSize: 14.5,
                                      height: 1.6,
                                      decoration: TextDecoration.none,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Row(
                                    children: [
                                      if (_tutorialStep > 0) ...[
                                        GestureDetector(
                                          onTap: _regressTutorial,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(30),
                                              border: Border.all(color: Colors.white24),
                                            ),
                                            child: const Text('Back', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14, decoration: TextDecoration.none)),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                      ],
                                      Row(
                                        children: List.generate(totalSteps, (i) => AnimatedContainer(
                                          duration: const Duration(milliseconds: 300),
                                          curve: Curves.easeInOut,
                                          width: i == _tutorialStep ? 20 : 6,
                                          height: 6,
                                          margin: const EdgeInsets.only(right: 5),
                                          decoration: BoxDecoration(
                                            color: i == _tutorialStep
                                                ? const Color(0xFFFF6200)
                                                : i < _tutorialStep
                                                    ? const Color(0xFFFF6200).withValues(alpha: 0.4)
                                                    : Colors.white12,
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                        )),
                                      ),
                                      const Spacer(),
                                      GestureDetector(
                                        onTap: _advanceTutorial,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [Color(0xFFFF6200), Color(0xFFFF8040)],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.circular(30),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFFFF6200).withValues(alpha: 0.4),
                                                blurRadius: 12,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                isLast ? 'Get Started' : 'Next',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
                                                  decoration: TextDecoration.none,
                                                ),
                                              ),
                                              if (!isLast) ...[
                                                const SizedBox(width: 6),
                                                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 15),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ),
                ),
      ),
    );
  }

  Widget _buildFlashSourceHeader() {
    final enabledSources = _flashEnabledSources.isNotEmpty
        ? _flashEnabledSources
        : _kFlashSources.map((s) => s['name']!).toList();

    return Container(
      color: const Color(0xFF0A0A0A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, color: Color(0xFFFF6200), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final selected = await showModalBottomSheet<String>(
                  context: context,
                  backgroundColor: const Color(0xFF111111),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (ctx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 12),
                        Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(height: 16),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Text('Select Source', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                        const SizedBox(height: 12),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ...enabledSources.map((name) => InkWell(
                                  onTap: () => Navigator.pop(ctx, name),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                    decoration: BoxDecoration(
                                      border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(child: Text(name, style: TextStyle(color: _flashSelectedSource == name ? const Color(0xFFFF6200) : Colors.white, fontWeight: FontWeight.w600, fontSize: 15))),
                                        if (_flashSelectedSource == name) const Icon(Icons.check, color: Color(0xFFFF6200), size: 18),
                                      ],
                                    ),
                                  ),
                                )),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
                if (selected != null && selected != _flashSelectedSource && mounted) {
                  setState(() {
                    _flashSelectedSource = selected;
                    _flashSelectedTopic = null;
                    _loading = true;
                  });
                  _fetchArticles();
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _flashSelectedSource,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.3),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54, size: 20),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() { _loading = true; });
              _fetchArticles();
            },
            child: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildFlashTopicRow() {
    if (_flashDynamicTopics.isEmpty) return const SizedBox.shrink();
    final count = _flashDynamicTopics.length;
    final cols = count <= 3 ? count : (count == 4 ? 2 : 3);
    return Container(
      color: const Color(0xFF0D0D0D),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chipW = (constraints.maxWidth - (cols - 1) * 8) / cols;
          return Wrap(
            spacing: 8,
            runSpacing: 6,
            children: List.generate(_flashDynamicTopics.length, (index) {
              final topic = _flashDynamicTopics[index];
              final name = topic['name'] as String;
              final isSelected = _flashSelectedTopic == name;
              return GestureDetector(
                onTap: () {
                  if (_flashSelectedTopic == name) return;
                  setState(() {
                    _flashSelectedTopic = name;
                    _articles = List<dynamic>.from(topic['articles'] as List);
                  });
                },
                child: Container(
                  width: chipW,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: isSelected ? null : Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? Colors.black : Colors.white70,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildFlashTopicBanner() {
    if (_flashSelectedTopic == null || _flashDynamicTopics.isEmpty) return const SizedBox.shrink();
    final topicData = _flashDynamicTopics.firstWhere(
      (t) => t['name'] == _flashSelectedTopic,
      orElse: () => {},
    );
    if (topicData.isEmpty) return const SizedBox.shrink();
    final topicName = _flashSelectedTopic!;
    final bannerUrl = topicData['bannerUrl']?.toString();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.6), width: 1.5),
        color: const Color(0xFF1A1A1A),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bannerUrl != null && bannerUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Stack(
                children: [
                  Image.network(
                    bannerUrl,
                    width: double.infinity,
                    height: 160,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildTextOnlyBannerTop(topicName),
                  ),
                  Positioned(
                    top: 10,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6200),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.bolt, color: Colors.white, size: 13),
                          SizedBox(width: 3),
                          Text(
                            'TRENDING',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            _buildTextOnlyBannerTop(topicName),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  topicName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 2,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6200),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Live coverage',
                      style: TextStyle(
                        color: Color(0xFFFF6200),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextOnlyBannerTop(String topicName) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: Container(
        width: double.infinity,
        height: 90,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2A0E00), Color(0xFF1A0800), Color(0xFF0D0400)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                topicName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            Positioned(
              top: 10,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6200),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.bolt, color: Colors.white, size: 13),
                    SizedBox(width: 3),
                    Text(
                      'TRENDING',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: false,
        title: _isSearching 
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: const InputDecoration(
                hintText: 'Search TruBrief...',
                hintStyle: TextStyle(color: Colors.white38),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _fetchArticles(),
            )
          : const Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Tru',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 32,
                      letterSpacing: -1.0,
                    ),
                  ),
                  TextSpan(
                    text: 'Brief',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 32,
                      color: Color(0xFFFF6200),
                      letterSpacing: -1.0,
                    ),
                  ),
                ],
              ),
            ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search_rounded, size: 26),
            color: Colors.white,
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _fetchArticles();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          if (!_isSearching) ...[
            IconButton(
              icon: const Icon(Icons.bookmark_rounded, size: 24),
              color: Colors.white,
              tooltip: 'Saved Articles',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SavedArticlesScreen(
                      isSubscribed: _isPremium || _isTrialActive,
                    ),
                  ),
                ).then((_) { if (mounted) _fetchSavedArticles(); });
              },
            ),
            IconButton(
              icon: KeyedSubtree(
                key: _settingsButtonKey,
                child: const Icon(Icons.settings_rounded, size: 26),
              ),
              color: Colors.white,
              onPressed: _navigateToSettings,
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchArticles,
        color: const Color(0xFFFF6200),
        backgroundColor: const Color(0xFF1C1C1E),
        child: Column(
          children: [
            Builder(builder: (context) {
              final visibleTabs = _selectedCategories.where((c) => !_hiddenTabs.contains(c) && c != 'Tru Flash').toList();
              final displayTabs = visibleTabs.take(3).toList();
              const hasMore = true;

              Widget _tabChip(String cat) {
                final isSelected = _selectedCategory == cat;
                return InkWell(
                  onTap: () {
                    setState(() { _selectedCategory = cat; _loading = true; });
                    _fetchArticles();
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? const Color(0xFFFF6200) : Colors.white24,
                        width: 1.5,
                      ),
                    ),
                    child: () {
                      final parts = cat.split(' ');
                      if (parts.length >= 2) {
                        return RichText(
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          text: TextSpan(
                            children: [
                              TextSpan(text: parts[0], style: TextStyle(color: isSelected ? Colors.white : Colors.white38, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: -0.5)),
                              TextSpan(text: ' ${parts.skip(1).join(' ')}', style: TextStyle(color: isSelected ? const Color(0xFFFF6200) : const Color(0xFFFF6200).withValues(alpha: 0.4), fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: -0.5)),
                            ],
                          ),
                        );
                      }
                      return Text(cat.toUpperCase(), style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.8), overflow: TextOverflow.ellipsis, maxLines: 1);
                    }(),
                  ),
                );
              }

              return Container(
                height: 48,
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: displayTabs.map((cat) => Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: SizedBox(
                              height: 40,
                              child: cat == 'Tru Brief'
                                  ? KeyedSubtree(key: _truBriefTabKey, child: _tabChip(cat))
                                  : _tabChip(cat),
                            ),
                          ),
                        )).toList(),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() { _selectedCategory = 'Tru Flash'; _loading = true; });
                        _fetchArticles();
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        margin: const EdgeInsets.only(right: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _selectedCategory == 'Tru Flash'
                              ? const Color(0xFFFFD700).withValues(alpha: 0.18)
                              : const Color(0xFFFFD700).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _selectedCategory == 'Tru Flash'
                                ? const Color(0xFFFFD700)
                                : const Color(0xFFFFD700).withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          Icons.bolt_rounded,
                          size: 20,
                          color: _selectedCategory == 'Tru Flash'
                              ? const Color(0xFFFFD700)
                              : const Color(0xFFFFD700).withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    if (hasMore)
                      InkWell(
                        onTap: () {
                          if (_feedGridOpen) {
                            Navigator.of(context).pop();
                            return;
                          }
                          setState(() => _feedGridOpen = true);
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            isScrollControlled: true,
                            isDismissible: true,
                            enableDrag: true,
                            builder: (ctx) => DraggableScrollableSheet(
                              expand: false,
                              initialChildSize: 0.6,
                              minChildSize: 0.4,
                              maxChildSize: 0.9,
                              builder: (_, controller) => Container(
                                decoration: const BoxDecoration(
                                  color: Color(0xFF111111),
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                ),
                                child: Column(
                                  children: [
                                    const SizedBox(height: 10),
                                    Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                                    const SizedBox(height: 16),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      child: Row(
                                        children: [
                                          const SizedBox(width: 60),
                                          const Expanded(
                                            child: Text('My Feeds', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.2)),
                                          ),
                                          GestureDetector(
                                            onTap: () => Navigator.pop(ctx),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFF6200).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.4)),
                                              ),
                                              child: const Text('Close', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Expanded(
                                      child: GridView.builder(
                                        controller: controller,
                                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 3,
                                          mainAxisSpacing: 10,
                                          crossAxisSpacing: 10,
                                          childAspectRatio: 2.0,
                                        ),
                                        itemCount: (visibleTabs.skip(3).toList()..sort((a, b) => a.compareTo(b))).length,
                                        itemBuilder: (ctx, i) {
                                          final cat = (visibleTabs.skip(3).toList()..sort((a, b) => a.compareTo(b)))[i];
                                          final isSelected = _selectedCategory == cat;
                                          final parts = cat.split(' ');
                                          return GestureDetector(
                                            onTap: () {
                                              Navigator.pop(ctx);
                                              setState(() { _selectedCategory = cat; _loading = true; });
                                              _fetchArticles();
                                            },
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 150),
                                              alignment: Alignment.center,
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: isSelected ? const Color(0xFF3A2010) : const Color(0xFF2C1C16),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: isSelected ? const Color(0xFFFF6200) : const Color(0xFFFF6200).withValues(alpha: 0.35),
                                                  width: isSelected ? 2.0 : 1.5,
                                                ),
                                              ),
                                              child: parts.length >= 2
                                                ? RichText(
                                                    textAlign: TextAlign.center,
                                                    text: TextSpan(children: [
                                                      TextSpan(text: '${parts[0]}\n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: -0.3)),
                                                      TextSpan(text: parts.skip(1).join(' '), style: const TextStyle(color: Color(0xFFFF6200), fontWeight: FontWeight.w800, fontSize: 11)),
                                                    ]),
                                                  )
                                                : Text(cat, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11), textAlign: TextAlign.center),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                      child: GestureDetector(
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          _navigateToSettings();
                                        },
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(vertical: 13),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [Color(0xFFFF6200), Color(0xFFFF8040)],
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                            ),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Text(
                                            'Customize Feeds',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ).then((_) {
                            if (mounted) setState(() => _feedGridOpen = false);
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          key: _gridIconKey,
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6200).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.5), width: 1.5),
                          ),
                          child: const Icon(Icons.grid_view_rounded, size: 18, color: Color(0xFFFF6200)),
                        ),
                      ),
                    const SizedBox(width: 16),
                  ],
                ),
              );
            }),
            if ((_selectedCategory == 'Local Brief' || _selectedCategory == 'National Brief') && _locationType == 'none')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: InkWell(
                  onTap: _navigateToSettings,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6200).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.location_on, size: 16, color: Color(0xFFFF6200)),
                        SizedBox(width: 8),
                        Text(
                          'SET LOCATION FOR LOCAL BRIEF',
                          style: TextStyle(
                            color: Color(0xFFFF6200),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_selectedCategory == 'Local Brief' && _city != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, size: 14, color: Color(0xFFFF6200)),
                    const SizedBox(width: 4),
                    Text(
                      '$_city, $_state',
                      style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            if (_selectedCategory == 'Tru Flash') ...[
              _buildFlashSourceHeader(),
              _buildFlashTopicRow(),
            ],
            if (_selectedCategory != 'Tru Brief' &&
                _selectedCategory != 'Local Brief' &&
                _selectedCategory != 'National Brief' &&
                _selectedCategory != 'Tru Flash') ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(
                  children: [
                    const Icon(Icons.grid_view_rounded, size: 13, color: Color(0xFFFF6200)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _selectedCategory.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFFFF6200),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() { _selectedCategory = 'Tru Brief'; _loading = true; _fetchArticles(); }),
                      child: const Icon(Icons.close, size: 16, color: Colors.white38),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF222222)),
            ],
            Expanded(
              key: _articleListKey,
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6200)))
                  : _articles.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                            if ((_selectedCategory == 'Local Brief' || _selectedCategory == 'National Brief') && _locationType == 'none') ...[
                              const Center(
                                child: Icon(Icons.location_off_outlined, size: 64, color: Colors.white24),
                              ),
                              const SizedBox(height: 16),
                              const Center(
                                child: Text(
                                  'Location Not Set',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Center(
                                child: Text(
                                  'Set your location to see news from your area.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Center(
                                child: ElevatedButton(
                                  onPressed: _navigateToSettings,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF6200),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  ),
                                  child: const Text('Set Location'),
                                ),
                              ),
                            ] else if (_selectedCategory == 'Tru Brief' && _selectedSources.isEmpty) ...[
                              const Center(
                                child: Icon(Icons.tune_rounded, size: 64, color: Colors.white24),
                              ),
                              const SizedBox(height: 16),
                              const Center(
                                child: Text(
                                  'No Sources Selected',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Center(
                                child: Text(
                                  'You haven\'t selected any sources yet.\nGo to Feeds & select the sources\nyou want to follow.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white38, fontSize: 14, height: 1.5),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Center(
                                child: ElevatedButton.icon(
                                  onPressed: _navigateToSettings,
                                  icon: const Icon(Icons.rss_feed, size: 18),
                                  label: const Text('Go to Feeds'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF6200),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  ),
                                ),
                              ),
                            ] else if (_currentCategoryHasNoActiveSources) ...[
                              const Center(
                                child: Icon(Icons.tune_rounded, size: 64, color: Colors.white24),
                              ),
                              const SizedBox(height: 16),
                              Center(
                                child: Text(
                                  'No Sources Selected',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Center(
                                child: Text(
                                  'You have no sources selected for $_selectedCategory.\nTap below to add sources.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white38, fontSize: 14, height: 1.5),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Center(
                                child: ElevatedButton.icon(
                                  onPressed: _navigateToSettings,
                                  icon: const Icon(Icons.add_circle_outline, size: 18),
                                  label: const Text('Add Sources'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF6200),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  ),
                                ),
                              ),
                            ] else ...[
                              const Center(
                                child: Icon(Icons.newspaper, size: 64, color: Colors.white24),
                              ),
                              const SizedBox(height: 16),
                              const Center(child: Text('No articles yet', style: TextStyle(fontSize: 16, color: Colors.grey))),
                            ],
                          ],
                        )
                      : ListView.builder(
                          itemCount: _articles.length + (_selectedCategory == 'Tru Flash' && _flashSelectedTopic != null ? 2 : 1),
                          itemBuilder: (context, index) {
                    final bool showFlashBanner = _selectedCategory == 'Tru Flash' && _flashSelectedTopic != null;
                    if (showFlashBanner && index == 0) return _buildFlashTopicBanner();
                    final articleIndex = showFlashBanner ? index - 1 : index;
                    if (articleIndex == _articles.length) {
                      // Local Brief uses Google News — subscription source notices don't apply
                      if (_selectedCategory == 'Local Brief') return const SizedBox.shrink();
                      final shortCat = _selectedCategory.replaceAll(' Brief', '').replaceAll(' News', '').trim();
                      final paywallSources = _allSources.where((s) {
                        if (s['requires_subscription'] != true) return false;
                        final sCat = s['category'].toString();
                        return sCat == _selectedCategory || sCat == shortCat || sCat == '$shortCat Brief' || sCat == '$shortCat News' || _selectedCategory == 'Tru Brief';
                      }).toList();
                      if (paywallSources.isEmpty) return const SizedBox.shrink();
                      final names = paywallSources.map((s) => s['name'].toString()).join(', ');
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.lock_outline, size: 16, color: Colors.grey),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '$names require${paywallSources.length == 1 ? 's' : ''} an account to view full articles.',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final article = Map<String, dynamic>.from(_articles[articleIndex] as Map);
                    final String? imageUrl = article['image_url'];
                    final String title = _unescapeHtml(article['title'] ?? 'No title');
                    final String source = _unescapeHtml(article['source_name'] ?? 'Unknown Source');
                    final String? summary = _cleanDescription(article['summary_brief']);
                    final bool isFeatured = articleIndex == 0;
                    final List<dynamic> relatedArticles = List<dynamic>.from(article['_related_articles'] as List? ?? []);

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      clipBehavior: Clip.antiAlias,
                      color: const Color(0xFF1C1C1E),
                      child: InkWell(
                        onTap: () => _openArticle(article),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (imageUrl != null && imageUrl.isNotEmpty)
                              Stack(
                                children: [
                                  CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    height: isFeatured ? 240 : 180,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      height: isFeatured ? 240 : 180,
                                      color: const Color(0xFF2A2A2A),
                                    ),
                                    errorWidget: (context, url, error) => const SizedBox.shrink(),
                                  ),
                                  if (isFeatured)
                                    Positioned(
                                      top: 12,
                                      left: 12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF6200),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'LATEST',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                            letterSpacing: 1.1,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          source.toUpperCase(),
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFFFF6200),
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      GestureDetector(
                                        onTap: () => _toggleSaveArticle(article),
                                        child: Icon(
                                          _savedArticleIds.contains(article['id'].toString())
                                              ? Icons.bookmark
                                              : Icons.bookmark_border,
                                          size: 22,
                                          color: _savedArticleIds.contains(article['id'].toString())
                                              ? const Color(0xFFFF6200)
                                              : Colors.white54,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.access_time, size: 14, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(
                                        _getTimeAgo(article['created_at']),
                                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: isFeatured ? 22 : 18,
                                      fontWeight: FontWeight.w700,
                                      height: 1.2,
                                    ),
                                  ),
                                  if (relatedArticles.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    GestureDetector(
                                      onTap: () => _showRelatedSources(context, article, relatedArticles),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF6200).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.35)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.source_outlined, size: 13, color: Color(0xFFFF6200)),
                                            const SizedBox(width: 5),
                                            Text(
                                              'Reported by ${relatedArticles.length + 1} sources',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFFFF6200),
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            const Icon(Icons.chevron_right, size: 13, color: Color(0xFFFF6200)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (summary != null && summary.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    if (_isPremium || _isTrialActive)
                                      Text(
                                        summary,
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: Colors.white.withValues(alpha: 0.7),
                                          height: 1.5,
                                        ),
                                        maxLines: isFeatured ? 4 : 3,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              'AI Summary Locked',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white.withValues(alpha: 0.5),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            const Text(
                                              'Start your 7-day free trial to read AI briefs.',
                                              style: TextStyle(fontSize: 12, color: Colors.grey),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ),
          ],
        ),
      ),
    );

    if (!_showTutorial) return scaffold;
    return Stack(
      children: [
        scaffold,
        Positioned.fill(child: _buildTutorialOverlay()),
      ],
    );
  }
}

class SourceSettingsScreen extends StatefulWidget {
  final VoidCallback? onRestartTutorial;
  final int? tutorialStep;
  final Future<void> Function()? onTutorialComplete;
  const SourceSettingsScreen({super.key, this.onRestartTutorial, this.tutorialStep, this.onTutorialComplete});

  @override
  State<SourceSettingsScreen> createState() => _SourceSettingsScreenState();
}

class _SourceSettingsScreenState extends State<SourceSettingsScreen> with TickerProviderStateMixin {
  String? get _effectiveUserId => Supabase.instance.client.auth.currentUser?.id;

  bool _loading = true;
  List<String> _categories = [];
  List<String> _virtualCategories = [];
  List<String> _selectedCategories = [];
  List<dynamic> _sources = [];
  List<String> _selectedSources = [];
  String _locationType = 'none'; // 'exact', 'zip', 'none'
  String? _zipCode;
  String? _city;
  Set<String> _hiddenTabs = {};
  final TextEditingController _zipController = TextEditingController();
  bool _showLocationEditor = false;
  int? _tutorialStep;
  bool _myFeedExpanded = false;
  bool _availableFeedsExpanded = false;
  bool _truFlashExpanded = false;
  List<String> _flashSourcesEnabled = [];
  static const List<Map<String, String>> _kFlashSourceList = [
    {'name': 'Fox News', 'url': 'https://feeds.foxnews.com/foxnews/latest'},
    {'name': 'CNN', 'url': 'https://rss.cnn.com/rss/edition.rss'},
    {'name': 'NBC News', 'url': 'https://feeds.nbcnews.com/nbcnews/public/news'},
    {'name': 'Politico', 'url': 'https://rss.politico.com/politics-news.xml'},
    {'name': 'ABC News', 'url': 'https://feeds.abcnews.com/abcnews/topstories'},
    {'name': 'CBS News', 'url': 'https://feeds.cbsnews.com/cbsnews/rss/latest'},
    {'name': 'NPR', 'url': 'https://feeds.npr.org/1001/rss.xml'},
    {'name': 'Reuters', 'url': 'https://feeds.reuters.com/reuters/topNews'},
    {'name': 'The Hill', 'url': 'https://thehill.com/rss/syndicator/19110'},
    {'name': 'DW News', 'url': 'https://rss.dw.com/rdf/rss-en-top'},
  ];
  final TextEditingController _categorySearchController = TextEditingController();
  String _categorySearchQuery = '';
  bool _isPremium = false;
  bool _isTrialActive = false;
  DateTime? _trialStartedAt;
  DateTime? _subscriptionRenewsAt;
  List<Map<String, dynamic>> _customSources = [];
  bool _addSourceExpanded = false;

  late final AnimationController _tutorialPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..repeat(reverse: true);
  final GlobalKey _locationRowKey = GlobalKey();
  final GlobalKey _myFeedRowKey = GlobalKey();
  final GlobalKey _availableFeedsRowKey = GlobalKey();
  final GlobalKey _newslettersRowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tutorialStep = widget.tutorialStep;
    _fetchSettings();
  }

  Future<void> _showFeedbackDialog() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    String? selectedType;
    final messageController = TextEditingController();
    XFile? attachedImage;
    bool sending = false;

    await showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: const Color(0xFF161618),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFF6200), Color(0xFFFF8040)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 12),
                    const Text('Send to Developer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.close_rounded, color: Colors.white38, size: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ...[
                  ('bug', Icons.bug_report_rounded, 'Report Bug'),
                  ('feature', Icons.lightbulb_rounded, 'Request Feature'),
                  ('contact', Icons.mail_rounded, 'Contact Dev'),
                ].map((item) {
                  final (type, icon, label) = item;
                  final selected = selectedType == type;
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedType = type),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFFFF6200).withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: selected ? const Color(0xFFFF6200).withValues(alpha: 0.5) : Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Icon(icon, color: selected ? const Color(0xFFFF6200) : Colors.white38, size: 18),
                          const SizedBox(width: 10),
                          Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white60, fontWeight: FontWeight.w600, fontSize: 14)),
                          const Spacer(),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 18, height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected ? const Color(0xFFFF6200) : Colors.transparent,
                              border: Border.all(color: selected ? const Color(0xFFFF6200) : Colors.white24, width: 1.5),
                            ),
                            child: selected ? const Icon(Icons.check, color: Colors.white, size: 11) : null,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                TextField(
                  controller: messageController,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Describe your issue or idea...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white12)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white12)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFF6200), width: 1.5)),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                        if (picked != null) setDialogState(() => attachedImage = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: attachedImage != null ? const Color(0xFFFF6200).withValues(alpha: 0.5) : Colors.white12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.attach_file_rounded, size: 16, color: attachedImage != null ? const Color(0xFFFF6200) : Colors.white38),
                            const SizedBox(width: 6),
                            Text(
                              attachedImage != null ? attachedImage!.name : 'Screenshot',
                              style: TextStyle(color: attachedImage != null ? const Color(0xFFFF6200) : Colors.white38, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: sending ? null : () async {
                        if (selectedType == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a type.')));
                          return;
                        }
                        if (messageController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a message.')));
                          return;
                        }
                        setDialogState(() => sending = true);
                        try {
                          String? screenshotUrl;
                          if (attachedImage != null) {
                            try {
                              final bytes = await File(attachedImage!.path).readAsBytes();
                              final fileName = 'feedback_${DateTime.now().millisecondsSinceEpoch}.jpg';
                              await supabase.storage.from('feedback-screenshots').uploadBinary(fileName, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
                              screenshotUrl = supabase.storage.from('feedback-screenshots').getPublicUrl(fileName);
                            } catch (_) {}
                          }
                          await supabase.from('trl_feedback').insert({
                            'user_id': user?.id,
                            'user_email': user?.email,
                            'type': selectedType,
                            'message': messageController.text.trim(),
                            if (screenshotUrl != null) 'screenshot_url': screenshotUrl,
                            'created_at': DateTime.now().toIso8601String(),
                          });
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Feedback submitted. Thank you!')));
                        } catch (e) {
                          setDialogState(() => sending = false);
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: sending ? [Colors.grey.shade800, Colors.grey.shade700] : [const Color(0xFFFF6200), const Color(0xFFFF8040)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: sending ? [] : [BoxShadow(color: const Color(0xFFFF6200).withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: sending
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Send', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                                  SizedBox(width: 6),
                                  Icon(Icons.send_rounded, color: Colors.white, size: 14),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    messageController.dispose();
  }

  Future<void> _advanceSettingsTutorial() async {
    if (_tutorialStep != null && _tutorialStep! < 8) {
      setState(() => _tutorialStep = _tutorialStep! + 1);
    } else {
      await widget.onTutorialComplete?.call();
      if (mounted) {
        setState(() => _tutorialStep = null);
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _dismissSettingsTutorial() async {
    await widget.onTutorialComplete?.call();
    if (mounted) setState(() => _tutorialStep = null);
  }

  Widget _buildSettingsTutorialOverlay() {
    const steps = [
      (
        icon: Icons.location_on_rounded,
        title: 'Location Settings',
        body: 'Set your zip code or use GPS to get local news tailored to your area in the Local Brief tab.',
      ),
      (
        icon: Icons.rss_feed_rounded,
        title: 'My Feed',
        body: 'View and manage your active categories. Tap any category to customize which sources appear in your feed.',
      ),
      (
        icon: Icons.apps_rounded,
        title: 'Available Feeds',
        body: 'Browse all news categories. Toggle Feed to include sources in Tru Brief, or Tab to add it as a browsable tab — independently.',
      ),
      (
        icon: Icons.mark_email_read_outlined,
        title: 'Newsletters',
        body: 'Add your favorite email newsletters to TruBrief for a complete, all-in-one reading experience.',
      ),
    ];

    final localStep = (_tutorialStep ?? 5) - 5;
    final clampedStep = localStep.clamp(0, steps.length - 1);
    final step = steps[clampedStep];
    final isLast = clampedStep == steps.length - 1;
    const totalSteps = 9;
    final globalStep = _tutorialStep ?? 5;

    Rect? getHighlightRect() {
      GlobalKey? key;
      switch (clampedStep) {
        case 0: key = _locationRowKey; break;
        case 1: key = _myFeedRowKey; break;
        case 2: key = _availableFeedsRowKey; break;
        case 3: key = _newslettersRowKey; break;
        default: return null;
      }
      final ctx = key.currentContext;
      if (ctx == null) return null;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) return null;
      return box.localToGlobal(Offset.zero) & box.size;
    }

    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _tutorialPulse,
        builder: (context, child) {
          final highlightRect = getHighlightRect();
          final screenHeight = MediaQuery.of(context).size.height;
          double? cardTop;
          double? cardBottom;
          if (highlightRect != null) {
            if (highlightRect.center.dy < screenHeight / 2) {
              cardBottom = 120;
            } else {
              cardTop = 80;
            }
          } else {
            cardBottom = 120;
          }
          return CustomPaint(
            painter: _SpotlightPainter(highlightRect: highlightRect, pulse: _tutorialPulse.value),
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned(
                    top: cardTop,
                    bottom: cardBottom,
                    left: 20,
                    right: 20,
                    child: child!,
                  ),
                ],
              ),
            ),
          );
        },
        child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(clampedStep),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF161618),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.25), width: 1),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFFFF6200).withValues(alpha: 0.12), blurRadius: 40, spreadRadius: 0, offset: const Offset(0, 8)),
                          BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 24, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: 3,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [const Color(0xFFFF6200), const Color(0xFFFF6200).withValues(alpha: 0.0)],
                                  stops: [(globalStep + 1) / totalSteps, (globalStep + 1) / totalSteps],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(colors: [Color(0xFFFF6200), Color(0xFFFF8C42)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Icon(step.icon, color: Colors.white, size: 22),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${globalStep + 1} of $totalSteps',
                                              style: const TextStyle(color: Color(0xFFFF6200), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, decoration: TextDecoration.none),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              step.title,
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.3, decoration: TextDecoration.none),
                                            ),
                                          ],
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: _dismissSettingsTutorial,
                                        child: Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(8)),
                                          child: const Icon(Icons.close_rounded, color: Colors.white38, size: 16),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    step.body,
                                    style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 14.5, height: 1.6, decoration: TextDecoration.none, fontWeight: FontWeight.w400),
                                  ),
                                  const SizedBox(height: 24),
                                  Row(
                                    children: [
                                      Row(
                                        children: List.generate(totalSteps, (i) => AnimatedContainer(
                                          duration: const Duration(milliseconds: 300),
                                          curve: Curves.easeInOut,
                                          width: i == globalStep ? 20 : 6,
                                          height: 6,
                                          margin: const EdgeInsets.only(right: 5),
                                          decoration: BoxDecoration(
                                            color: i == globalStep
                                                ? const Color(0xFFFF6200)
                                                : i < globalStep
                                                    ? const Color(0xFFFF6200).withValues(alpha: 0.4)
                                                    : Colors.white12,
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                        )),
                                      ),
                                      const Spacer(),
                                      GestureDetector(
                                        onTap: _advanceSettingsTutorial,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(colors: [Color(0xFFFF6200), Color(0xFFFF8040)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                            borderRadius: BorderRadius.circular(30),
                                            boxShadow: [BoxShadow(color: const Color(0xFFFF6200).withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                isLast ? 'Get Started' : 'Next',
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, decoration: TextDecoration.none),
                                              ),
                                              if (!isLast) ...[
                                                const SizedBox(width: 6),
                                                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 15),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
      ),
    );
  }

  void _showSubscriptionManagement(BuildContext context, bool isActive) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 22),
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6200).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFF6200), size: 22),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TruBrief Pro', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                    Text(
                      isActive ? 'Active subscription' : 'Not subscribed',
                      style: TextStyle(color: isActive ? const Color(0xFFFF6200) : Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (isActive) ...[
              const Text('Manage Subscription', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              const Text(
                'Subscriptions are managed through the Google Play Store. To cancel or change your plan, visit your Play Store subscription settings.',
                style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  launchUrl(
                    Uri.parse('https://play.google.com/store/account/subscriptions?package=com.truresolve.trubrief'),
                    mode: LaunchMode.externalApplication,
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.open_in_new, color: Colors.white54, size: 16),
                      SizedBox(width: 8),
                      Text('Open Play Store Subscriptions', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFF6200), Color(0xFFFF8C42)], begin: Alignment.centerLeft, end: Alignment.centerRight),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: const Color(0xFFFF6200).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: const Text('Subscribe — Coming Soon', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _fetchSettings() async {
    final userId = _effectiveUserId;
    try {
      // 1. Fetch Categories dynamically
      final catData = await Supabase.instance.client
          .from('trl_categories')
          .select()
          .order('display_order', ascending: true);
      
      final sources = await Supabase.instance.client
          .from('trl_sources')
          .select()
          .timeout(const Duration(seconds: 10));
      
      List<String> selectedSources = [];
      List<String> selectedCategories = [];
      List<String> allCategories = List<String>.from(catData.map((c) => c['name'])).where((c) => c != 'Weekly Top').toList();
      List<String> virtuals = List<String>.from(catData.where((c) => c['is_virtual'] == true && c['name'] != 'Weekly Top').map((c) => c['name']));

      if (userId != null) {
        final prefs = await Supabase.instance.client
            .from('trl_user_preferences')
            .select()
            .eq('user_id', userId)
            .limit(1)
            .maybeSingle()
            .timeout(const Duration(seconds: 10));
        
        if (prefs != null) {
          selectedSources = List<String>.from(prefs['selected_sources'] ?? []);
          final List<String> savedOrder = List<String>.from(prefs['selected_categories'] ?? []);
          
          // Reconstruct _categories based on saved order, then add any NEW categories from DB at the end
          final List<String> orderedCats = [];
          for (var catName in savedOrder) {
            if (allCategories.contains(catName)) {
              orderedCats.add(catName);
            }
          }
          
          for (var dbCat in allCategories) {
            if (!orderedCats.contains(dbCat)) {
              orderedCats.add(dbCat);
            }
          }
          allCategories = orderedCats.where((c) => c != 'Weekly Top').toList();

          // Ensure Tru Brief is ALWAYS first
          if (allCategories.contains('Tru Brief')) {
            allCategories.remove('Tru Brief');
            allCategories.insert(0, 'Tru Brief');
          }

          selectedCategories = List<String>.from(savedOrder).where((c) => c != 'Weekly Top').toList();
          
          if (selectedCategories.isEmpty) {
            selectedCategories = ['Tru Brief', 'Local Brief', 'Weather Brief'];
          }

          final allSourceIds = sources.map((s) => s['id'].toString()).toSet();

          // Remove only stale source IDs (sources no longer in DB); preserve subscription sources
          selectedSources.removeWhere((id) => !allSourceIds.contains(id));

          // Only auto-add default free sources if the user has NO sources at all (first-time equivalent)
          if (selectedSources.isEmpty) {
            for (var cat in allCategories) {
              final shortCat = cat.replaceAll(' Brief', '').replaceAll(' News', '').trim();
              final catSources = sources.where((s) {
                final sCat = s['category'].toString();
                return sCat == cat || sCat == shortCat || sCat == '$shortCat Brief' || sCat == '$shortCat News';
              }).toList();
              final freeCatSources = catSources.where((s) => s['requires_subscription'] != true).toList();
              for (var i = 0; i < freeCatSources.length && i < 3; i++) {
                final id = freeCatSources[i]['id'].toString();
                if (!selectedSources.contains(id)) selectedSources.add(id);
              }
            }
          }

          _locationType = prefs['location_type'] ?? 'none';
          _zipCode = _locationType == 'none' ? null : prefs['zip_code'];
          _city = _locationType == 'none' ? null : prefs['city'];
          _hiddenTabs = Set<String>.from(prefs['hidden_tabs'] ?? []);
          _zipController.text = _zipCode ?? '';
          _showLocationEditor = _locationType == 'none';
        } else {
          // If no prefs exist, highlight the defaults and select top 3 FREE sources per category
          selectedCategories = ['Tru Brief', 'Local Brief', 'Weather Brief'];
          _showLocationEditor = true;

          for (var cat in allCategories) {
            final shortCat = cat.replaceAll(' Brief', '').replaceAll(' News', '').trim();
            final freeCatSources = sources.where((s) {
              final sCat = s['category'].toString();
              final matchesCat = sCat == cat || sCat == shortCat || sCat == '$shortCat Brief' || sCat == '$shortCat News';
              return matchesCat && s['requires_subscription'] != true;
            }).toList();
            for (var i = 0; i < freeCatSources.length && i < 3; i++) {
              selectedSources.add(freeCatSources[i]['id'].toString());
            }
          }
        }
      }

      bool isPremium = false;
      bool isTrialActive = false;
      DateTime? trialStartedAt;
      DateTime? renewsAt;
      if (userId != null) {
        try {
          final sub = await Supabase.instance.client
              .from('trl_subscriptions')
              .select()
              .eq('user_id', userId)
              .maybeSingle()
              .timeout(const Duration(seconds: 8));
          if (sub != null) {
            isPremium = sub['status'] == 'active';
            if (sub['trial_started_at'] != null) {
              trialStartedAt = DateTime.tryParse(sub['trial_started_at'].toString());
              if (trialStartedAt != null) {
                isTrialActive = DateTime.now().difference(trialStartedAt!).inDays < 7;
              }
            }
            if (sub['renews_at'] != null) {
              renewsAt = DateTime.tryParse(sub['renews_at'].toString());
            }
          }
        } catch (_) {}
      }

      List<Map<String, dynamic>> customSources = [];
      if (userId != null) {
        try {
          final rows = await Supabase.instance.client
              .from('trl_user_custom_sources')
              .select()
              .eq('user_id', userId)
              .order('created_at', ascending: true);
          customSources = List<Map<String, dynamic>>.from(rows);
        } catch (_) {}
      }

      final localPrefs = await SharedPreferences.getInstance();
      final savedFlash = localPrefs.getStringList('flash_enabled_sources');
      final flashEnabled = savedFlash ?? _kFlashSourceList.map((s) => s['name']!).toList();

      if (catData != null && catData.isNotEmpty && mounted) {
        setState(() {
          _categories = allCategories;
          _virtualCategories = virtuals;
          _sources = sources;
          _selectedSources = selectedSources;
          _selectedCategories = selectedCategories;
          _isPremium = isPremium;
          _isTrialActive = isTrialActive;
          _trialStartedAt = trialStartedAt;
          _subscriptionRenewsAt = renewsAt;
          _customSources = customSources;
          _flashSourcesEnabled = flashEnabled;
          _loading = false;
        });
      } else {
        debugPrint('Warning: No categories found during settings load');
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('Load settings error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tutorialPulse.dispose();
    _zipController.dispose();
    _categorySearchController.dispose();
    super.dispose();
  }

  Future<void> _savePreferences({String? city, String? state, String? county}) async {
    final userId = _effectiveUserId;
    if (userId == null) return;

    try {
      // Preserve order by filtering _categories based on what is in _selectedCategories
      final List<String> orderedSelections = _categories
          .where((cat) => _selectedCategories.contains(cat))
          .toList();

      final Map<String, dynamic> data = {
        'user_id': userId,
        'selected_sources': _selectedSources,
        'selected_categories': orderedSelections,
        'location_type': _locationType,
        'zip_code': _zipCode,
        'hidden_tabs': _hiddenTabs.toList(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (city != null) data['city'] = city;
      if (state != null) data['state'] = state;
      if (county != null) data['county'] = county;

      await Supabase.instance.client.from('trl_user_preferences').upsert(
        data,
        onConflict: 'user_id',
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  Widget _buildLocationHeader() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),

      ),
      child: Material(
        key: _locationRowKey,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _showLocationEditor = !_showLocationEditor),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0A2018), Color(0xFF050F0C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.5), width: 1.0),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6200).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _locationType == 'exact' ? Icons.gps_fixed : (_locationType == 'zip' ? Icons.location_on : Icons.location_off),
                      color: const Color(0xFFFF6200), size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Location Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                      Text(
                        _locationType == 'exact'
                            ? 'GPS location${_city != null && _city!.isNotEmpty ? " · $_city" : ""}'
                            : (_locationType == 'zip'
                                ? 'Postal code $_zipCode${_city != null && _city!.isNotEmpty ? " · $_city" : ""}'
                                : 'Location not set'),
                        style: const TextStyle(fontSize: 12, color: Color(0xFFFF6200)),
                      ),
                    ],
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _showLocationEditor ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6200).withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.keyboard_arrow_down, color: Color(0xFFFF6200), size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationContent() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.2), width: 1.2),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: InkWell(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              onTap: () async {
                if (!mounted) return;
                if (_locationType == 'exact') {
                  setState(() { _locationType = 'none'; _city = null; _zipCode = null; });
                  _savePreferences();
                  return;
                }
                final messenger = ScaffoldMessenger.of(context);
                setState(() => _loading = true);
                try {
                  LocationPermission permission = await Geolocator.checkPermission();
                  if (!mounted) return;
                  if (permission == LocationPermission.denied) {
                    permission = await Geolocator.requestPermission();
                  }
                  if (!mounted) return;
                  if (permission == LocationPermission.deniedForever) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Location permission permanently denied. Enable it in device settings.')),
                    );
                    return;
                  }
                  if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
                    Position position = await Geolocator.getCurrentPosition(
                      locationSettings: const LocationSettings(
                        accuracy: LocationAccuracy.medium,
                        timeLimit: Duration(seconds: 8),
                      ),
                    );
                    if (!mounted) return;
                    List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude).timeout(const Duration(seconds: 6));
                    if (!mounted) return;
                    if (placemarks.isNotEmpty) {
                      Placemark place = placemarks[0];
                      setState(() {
                        _locationType = 'exact';
                        _zipCode = place.postalCode;
                        _city = place.locality;
                        _showLocationEditor = false;
                      });
                      _savePreferences(city: place.locality, state: place.administrativeArea, county: place.subAdministrativeArea);
                    }
                  }
                } catch (e) {
                  debugPrint('GPS error: $e');
                  if (mounted) messenger.showSnackBar(
                    const SnackBar(content: Text('Could not get location. Try entering a zip code instead.')),
                  );
                } finally {
                  if (mounted) setState(() => _loading = false);
                }
              },
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _locationType == 'exact'
                        ? [const Color(0xFF2A1500), const Color(0xFF1A0E00)]
                        : [const Color(0xFF1C1C1E), const Color(0xFF111111)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF6200), Color(0xFFFF8040)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _locationType == 'exact' ? Icons.gps_fixed : Icons.my_location,
                          color: Colors.white,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Use GPS Location',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.1,
                            ),
                          ),
                          Text(
                            _locationType == 'exact' ? 'Active · Most accurate' : 'Most accurate for local news',
                            style: TextStyle(
                              fontSize: 11,
                              color: _locationType == 'exact'
                                  ? const Color(0xFFFF6200).withValues(alpha: 0.8)
                                  : Colors.white38,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Switch.adaptive(
                        value: _locationType == 'exact',
                        onChanged: (val) async {
                          if (!val) {
                            setState(() { _locationType = 'none'; _city = null; _zipCode = null; });
                            _savePreferences();
                            return;
                          }
                          final messenger = ScaffoldMessenger.of(context);
                          setState(() => _loading = true);
                          try {
                            LocationPermission permission = await Geolocator.checkPermission();
                            if (!mounted) return;
                            if (permission == LocationPermission.denied) {
                              permission = await Geolocator.requestPermission();
                            }
                            if (!mounted) return;
                            if (permission == LocationPermission.deniedForever) {
                              messenger.showSnackBar(const SnackBar(content: Text('Location permission permanently denied. Enable it in device settings.')));
                              return;
                            }
                            if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
                              final position = await Geolocator.getCurrentPosition(
                                locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 8)),
                              );
                              if (!mounted) return;
                              final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude).timeout(const Duration(seconds: 6));
                              if (!mounted) return;
                              if (placemarks.isNotEmpty) {
                                final place = placemarks[0];
                                setState(() {
                                  _locationType = 'exact';
                                  _zipCode = place.postalCode;
                                  _city = place.locality;
                                  _showLocationEditor = false;
                                });
                                _savePreferences(city: place.locality, state: place.administrativeArea, county: place.subAdministrativeArea);
                              }
                            }
                          } catch (e) {
                            debugPrint('GPS error: $e');
                            if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Could not get location. Try entering a postal code instead.')));
                          } finally {
                            if (mounted) setState(() => _loading = false);
                          }
                        },
                        activeThumbColor: const Color(0xFFFF6200),
                        activeTrackColor: const Color(0xFFFF6200).withValues(alpha: 0.35),
                        inactiveThumbColor: Colors.white38,
                        inactiveTrackColor: Colors.white12,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.06))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('OR', style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                ),
                Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.06))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: TextField(
                      controller: _zipController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Enter Postal Code',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () async {
                    final code = _zipController.text.trim();
                    if (code.length >= 3) {
                      setState(() {
                        _locationType = 'zip';
                        _zipCode = code;
                        _showLocationEditor = false;
                      });
                      String? resolvedCity;
                      String? resolvedState;
                      try {
                        final locs = await locationFromAddress(code);
                        if (locs.isNotEmpty) {
                          final marks = await placemarkFromCoordinates(locs.first.latitude, locs.first.longitude);
                          if (marks.isNotEmpty) {
                            resolvedCity = marks.first.locality;
                            resolvedState = marks.first.administrativeArea;
                            if (mounted) setState(() => _city = resolvedCity);
                          }
                        }
                      } catch (_) {}
                      _savePreferences(city: resolvedCity, state: resolvedState);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF6200), Color(0xFFFF8040)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyFeedHeader() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),

      ),
      child: Material(
        key: _myFeedRowKey,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _myFeedExpanded = !_myFeedExpanded),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF241000), Color(0xFF140800)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.5), width: 1.0),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6200).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.rss_feed, color: Color(0xFFFF6200), size: 22),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('My Feed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                      Text(_myFeedExpanded ? 'Drag to reorder • Tap to manage' : 'Manage your active feed tabs', style: const TextStyle(fontSize: 12, color: Color(0xFFFF6200))),
                    ],
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _myFeedExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6200).withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.keyboard_arrow_down, color: Color(0xFFFF6200), size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMyFeedContent() {
    return Column(
      children: [
        const SizedBox(height: 12),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex -= 1;
              if (newIndex == 0) newIndex = 1;
              if (oldIndex == 0) return;
              final item = _selectedCategories.removeAt(oldIndex);
              _selectedCategories.insert(newIndex, item);
            });
            _savePreferences();
          },
          children: _selectedCategories.map((cat) {
            final bool isTruBrief = cat == 'Tru Brief';
            final idx = _selectedCategories.indexOf(cat);
            final shortCat = cat.replaceAll(' Brief', '').replaceAll(' News', '').trim();
            final catSources = _sources.where((s) {
              final sCat = s['category']?.toString() ?? '';
              return sCat == cat || sCat == shortCat || sCat == '$shortCat Brief' || sCat == '$shortCat News';
            }).toList();
            final activeCount = catSources.where((s) => _selectedSources.contains(s['id'].toString())).length;
            final bool isTabHidden = _hiddenTabs.contains(cat);
            return ClipRRect(
              key: ValueKey(cat),
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 56,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C1C16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Center(
                          child: isTruBrief
                              ? const Icon(Icons.push_pin, color: Color(0xFFFF6200), size: 20)
                              : ReorderableDragStartListener(
                                  index: idx,
                                  child: const Icon(Icons.drag_handle, color: Colors.white38, size: 24),
                                ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(cat, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (!isTruBrief) ...[
                                Text('$activeCount source${activeCount == 1 ? '' : 's'} active', style: const TextStyle(fontSize: 11, color: Colors.white54)),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (!isTruBrief) ...[
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => CategoryDetailScreen(
                                category: cat,
                                sources: catSources,
                                selectedSources: List<String>.from(_selectedSources),
                                isInFeed: true,
                                isTabVisible: !isTabHidden,
                                onChanged: (newSources, inFeed, tabVisible) {
                                  setState(() {
                                    _selectedSources = newSources;
                                    if (!inFeed) _selectedCategories.remove(cat);
                                    if (tabVisible) { _hiddenTabs.remove(cat); } else { _hiddenTabs.add(cat); }
                                  });
                                  _savePreferences();
                                },
                              ),
                            ));
                          },
                          child: Container(
                            width: 60,
                            height: 56,
                            decoration: BoxDecoration(
                              border: Border(left: BorderSide(color: const Color(0xFFFF6200).withValues(alpha: 0.2))),
                              color: Colors.white.withValues(alpha: 0.04),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.tune_rounded, size: 22, color: Color(0xFFFF6200)),
                                SizedBox(height: 4),
                                Text('Sources', style: TextStyle(fontSize: 11, color: Color(0xFFFF6200), fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() => _selectedCategories.remove(cat));
                            _savePreferences();
                          },
                          child: Container(
                            width: 60,
                            height: 56,
                            decoration: BoxDecoration(
                              border: Border(left: BorderSide(color: const Color(0xFFFF6200).withValues(alpha: 0.2))),
                              color: Colors.white.withValues(alpha: 0.04),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.rss_feed, size: 22, color: Color(0xFFFF6200)),
                                SizedBox(height: 4),
                                Text('Feed', style: TextStyle(fontSize: 11, color: Color(0xFFFF6200), fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() {
                              if (!isTabHidden) { _hiddenTabs.add(cat); } else { _hiddenTabs.remove(cat); }
                            });
                            _savePreferences();
                          },
                          child: Container(
                            width: 60,
                            height: 56,
                            decoration: BoxDecoration(
                              border: Border(left: BorderSide(color: const Color(0xFFFF6200).withValues(alpha: 0.2))),
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: const BorderRadius.only(topRight: Radius.circular(9), bottomRight: Radius.circular(9)),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(!isTabHidden ? Icons.tab : Icons.tab_unselected, size: 22, color: !isTabHidden ? const Color(0xFFFF6200) : Colors.white24),
                                const SizedBox(height: 4),
                                Text('Tab', style: TextStyle(fontSize: 11, color: !isTabHidden ? const Color(0xFFFF6200) : Colors.white24, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAvailableFeedsHeader() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),

      ),
      child: Material(
        key: _availableFeedsRowKey,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() {
            _availableFeedsExpanded = !_availableFeedsExpanded;
            if (!_availableFeedsExpanded) {
              _categorySearchController.clear();
              _categorySearchQuery = '';
            }
          }),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF091620), Color(0xFF050C14)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.5), width: 1.0),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.grid_view_rounded, color: Colors.white70, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Available Feeds', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                      Text(_availableFeedsExpanded ? 'Tap to manage sources or add to feed' : 'Browse & add more categories', style: const TextStyle(fontSize: 12, color: Color(0xFFFF6200))),
                    ],
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _availableFeedsExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvailableFeedsContent() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: TextField(
            controller: _categorySearchController,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            onChanged: (val) => setState(() => _categorySearchQuery = val),
            decoration: InputDecoration(
              hintText: 'Search categories...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
              suffixIcon: _categorySearchQuery.isNotEmpty
                  ? GestureDetector(
                      onTap: () => setState(() {
                        _categorySearchController.clear();
                        _categorySearchQuery = '';
                      }),
                      child: const Icon(Icons.clear, color: Colors.white38, size: 18),
                    )
                  : null,
              isDense: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _showAddCustomSourceSheet,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.35)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_circle_outline, color: Color(0xFFFF6200), size: 18),
                SizedBox(width: 8),
                Text('+ Add Custom Source', style: TextStyle(color: Color(0xFFFF6200), fontWeight: FontWeight.w700, fontSize: 14)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final sortedCats = (_categories.where((c) => !_virtualCategories.contains(c)).toList()..sort((a, b) => a.compareTo(b)));
            final filteredCats = _categorySearchQuery.isEmpty
                ? sortedCats
                : sortedCats.where((c) => c.toLowerCase().contains(_categorySearchQuery.toLowerCase())).toList();
            return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredCats.length,
          itemBuilder: (context, index) {
            final cat = filteredCats[index];
            final bool isInFeed = _selectedCategories.contains(cat);
            final bool isTruBrief = cat == 'Tru Brief';
            final shortCat = cat.replaceAll(' Brief', '').replaceAll(' News', '').trim();
            final catSources = _sources.where((s) {
              final sCat = s['category']?.toString() ?? '';
              return sCat == cat || sCat == shortCat || sCat == '$shortCat Brief' || sCat == '$shortCat News';
            }).toList();
            final activeCount = catSources.where((s) => _selectedSources.contains(s['id'].toString())).length;
            final bool isTabHidden = _hiddenTabs.contains(cat);
            final bool isActive = isInFeed && !isTabHidden;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 56,
                child: Container(
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF2C1C16) : const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isActive ? const Color(0xFFFF6200).withValues(alpha: 0.5) : Colors.white10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => CategoryDetailScreen(
                              category: cat,
                              sources: catSources,
                              selectedSources: List<String>.from(_selectedSources),
                              isInFeed: isInFeed,
                              isTabVisible: !isTabHidden,
                              onChanged: (newSources, inFeed, tabVisible) {
                                setState(() {
                                  _selectedSources = newSources;
                                  if (inFeed && !_selectedCategories.contains(cat)) {
                                    _selectedCategories.add(cat);
                                  } else if (!inFeed) {
                                    _selectedCategories.remove(cat);
                                  }
                                  if (tabVisible) {
                                    _hiddenTabs.remove(cat);
                                  } else {
                                    _hiddenTabs.add(cat);
                                  }
                                });
                                _savePreferences();
                              },
                            ),
                          ));
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                cat,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: isActive ? Colors.white : Colors.white70),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '$activeCount source${activeCount == 1 ? '' : 's'} active',
                                style: TextStyle(fontSize: 11, color: isActive ? Colors.white54 : Colors.white24),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (isTruBrief)
                      Container(
                        width: 44,
                        height: double.infinity,
                        decoration: BoxDecoration(
                          border: Border(left: BorderSide(color: const Color(0xFFFF6200).withValues(alpha: 0.2))),
                          color: Colors.transparent,
                        ),
                        child: const Icon(Icons.push_pin, size: 16, color: Color(0xFFFF6200)),
                      )
                    else ...[
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => CategoryDetailScreen(
                              category: cat,
                              sources: catSources,
                              selectedSources: List<String>.from(_selectedSources),
                              isInFeed: isInFeed,
                              isTabVisible: !isTabHidden,
                              onChanged: (newSources, inFeed, tabVisible) {
                                setState(() {
                                  _selectedSources = newSources;
                                  if (inFeed && !_selectedCategories.contains(cat)) {
                                    _selectedCategories.add(cat);
                                  } else if (!inFeed) {
                                    _selectedCategories.remove(cat);
                                  }
                                  if (tabVisible) {
                                    _hiddenTabs.remove(cat);
                                  } else {
                                    _hiddenTabs.add(cat);
                                  }
                                });
                                _savePreferences();
                              },
                            ),
                          ));
                        },
                        child: Container(
                          width: 60,
                          height: 56,
                          decoration: BoxDecoration(
                            border: Border(left: BorderSide(color: isActive ? const Color(0xFFFF6200).withValues(alpha: 0.2) : Colors.white10)),
                            color: Colors.white.withValues(alpha: 0.04),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.tune_rounded, size: 22, color: Color(0xFFFF6200)),
                              SizedBox(height: 4),
                              Text('Sources', style: TextStyle(fontSize: 11, color: Color(0xFFFF6200), fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          final freeSources = catSources.where((s) => s['requires_subscription'] != true).toList();
                          final top3 = freeSources.take(3).map((s) => s['id'].toString()).toList();
                          setState(() {
                            if (isInFeed) {
                              _selectedCategories.remove(cat);
                            } else {
                              _selectedCategories.add(cat);
                              for (final id in top3) {
                                if (!_selectedSources.contains(id)) _selectedSources.add(id);
                              }
                            }
                          });
                          _savePreferences();
                        },
                        child: Container(
                          width: 60,
                          height: 56,
                          decoration: BoxDecoration(
                            border: Border(left: BorderSide(color: isActive ? const Color(0xFFFF6200).withValues(alpha: 0.2) : Colors.white10)),
                            color: Colors.white.withValues(alpha: 0.04),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(isInFeed ? Icons.rss_feed : Icons.rss_feed_outlined, size: 22, color: isInFeed ? const Color(0xFFFF6200) : Colors.white24),
                              const SizedBox(height: 4),
                              Text('Feed', style: TextStyle(fontSize: 11, color: isInFeed ? const Color(0xFFFF6200) : Colors.white24, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            if (!isTabHidden) {
                              _hiddenTabs.add(cat);
                            } else {
                              _hiddenTabs.remove(cat);
                            }
                          });
                          _savePreferences();
                        },
                        child: Container(
                          width: 60,
                          height: 56,
                          decoration: BoxDecoration(
                            border: Border(left: BorderSide(color: isActive ? const Color(0xFFFF6200).withValues(alpha: 0.2) : Colors.white10)),
                            color: Colors.white.withValues(alpha: 0.04),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(!isTabHidden ? Icons.tab : Icons.tab_unselected, size: 22, color: !isTabHidden ? const Color(0xFFFF6200) : Colors.white24),
                              const SizedBox(height: 4),
                              Text('Tab', style: TextStyle(fontSize: 11, color: !isTabHidden ? const Color(0xFFFF6200) : Colors.white24, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                ),
              ),
              ),
            );
          },
        );
          },
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app, color: Colors.white54, size: 22),
            tooltip: 'Sign out',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1C1C1E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('Sign out?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  content: const Text('You will need to sign back in to access your account.', style: TextStyle(color: Colors.white54, fontSize: 14)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Sign out', style: TextStyle(color: Color(0xFFFF6200), fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;
              final prefs = await SharedPreferences.getInstance();
              final remember = prefs.getBool('remember_me') ?? false;
              if (!remember) {
                await prefs.remove('saved_email');
                await prefs.remove('saved_password');
              }
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6200)))
          : _showLocationEditor
              ? Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _buildLocationHeader(),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _buildLocationContent(),
                      ),
                    ),
                  ],
                )
              : _myFeedExpanded
                  ? Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: _buildMyFeedHeader(),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: _buildMyFeedContent(),
                          ),
                        ),
                      ],
                    )
                  : _availableFeedsExpanded
                      ? Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: _buildAvailableFeedsHeader(),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(16),
                                child: _buildAvailableFeedsContent(),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildLocationHeader(),
                                      const SizedBox(height: 16),
                                      _buildMyFeedHeader(),
                                      const SizedBox(height: 16),
                                      _buildAvailableFeedsHeader(),
                                      const SizedBox(height: 16),
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(14),
                                  
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(14),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(14),
                                            onTap: () => setState(() => _truFlashExpanded = !_truFlashExpanded),
                                            child: Ink(
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [Color(0xFF1C0E00), Color(0xFF100800)],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                borderRadius: BorderRadius.circular(14),
                                                border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.5), width: 1.0),
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: 40, height: 40,
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFFF6200).withValues(alpha: 0.25),
                                                        borderRadius: BorderRadius.circular(10),
                                                      ),
                                                      child: const Icon(Icons.bolt_rounded, color: Color(0xFFFF6200), size: 22),
                                                    ),
                                                    const SizedBox(width: 14),
                                                    Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Text('Tru Flash', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                                                        Text(_truFlashExpanded ? 'Tap to enable or disable sources' : 'Manage breaking news sources', style: const TextStyle(fontSize: 12, color: Color(0xFFFF6200))),
                                                      ],
                                                    ),
                                                    const Spacer(),
                                                    AnimatedRotation(
                                                      turns: _truFlashExpanded ? 0.5 : 0.0,
                                                      duration: const Duration(milliseconds: 250),
                                                      child: Container(
                                                        width: 30, height: 30,
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFFF6200).withValues(alpha: 0.22),
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFFFF6200), size: 22),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_truFlashExpanded) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF141414),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.2), width: 1),
                                          ),
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          child: Column(
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                                                child: Text(
                                                  'Choose which sources appear in the Tru Flash tab. At least one must be enabled.',
                                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12, height: 1.4),
                                                ),
                                              ),
                                              ..._kFlashSourceList.map((source) {
                                                final name = source['name']!;
                                                final isEnabled = _flashSourcesEnabled.contains(name);
                                                return InkWell(
                                                  onTap: () async {
                                                    setState(() {
                                                      if (isEnabled) {
                                                        if (_flashSourcesEnabled.length > 1) _flashSourcesEnabled.remove(name);
                                                      } else {
                                                        _flashSourcesEnabled.add(name);
                                                      }
                                                    });
                                                    final p = await SharedPreferences.getInstance();
                                                    await p.setStringList('flash_enabled_sources', _flashSourcesEnabled);
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                                    decoration: BoxDecoration(
                                                      border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Container(
                                                          width: 28, height: 28,
                                                          decoration: BoxDecoration(
                                                            color: isEnabled ? const Color(0xFFFF6200).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.06),
                                                            borderRadius: BorderRadius.circular(7),
                                                          ),
                                                          child: Icon(Icons.bolt_rounded, color: isEnabled ? const Color(0xFFFF6200) : Colors.white30, size: 16),
                                                        ),
                                                        const SizedBox(width: 12),
                                                        Expanded(child: Text(name, style: TextStyle(color: isEnabled ? Colors.white : Colors.white54, fontWeight: FontWeight.w600, fontSize: 14))),
                                                        Switch(
                                                          value: isEnabled,
                                                          onChanged: (_) async {
                                                            setState(() {
                                                              if (isEnabled) {
                                                                if (_flashSourcesEnabled.length > 1) _flashSourcesEnabled.remove(name);
                                                              } else {
                                                                _flashSourcesEnabled.add(name);
                                                              }
                                                            });
                                                            final p = await SharedPreferences.getInstance();
                                                            await p.setStringList('flash_enabled_sources', _flashSourcesEnabled);
                                                          },
                                                          activeThumbColor: const Color(0xFFFF6200),
                                                          activeTrackColor: const Color(0xFFFF6200).withValues(alpha: 0.3),
                                                          inactiveThumbColor: Colors.white38,
                                                          inactiveTrackColor: Colors.white12,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }),
                                            ],
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 16),
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(14),
                                  
                                        ),
                                        child: Material(
                                          key: _newslettersRowKey,
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(14),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(14),
                                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewslettersScreen())).then((_) { if (mounted) _fetchSettings(); }),
                                            child: Ink(
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [Color(0xFF180826), Color(0xFF0E0418)],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                borderRadius: BorderRadius.circular(14),
                                                border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.5), width: 1.0),
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: 40, height: 40,
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF8B2BE2).withValues(alpha: 0.30),
                                                        borderRadius: BorderRadius.circular(10),
                                                      ),
                                                      child: const Icon(Icons.mark_email_read_outlined, color: Color(0xFFCC88FF), size: 22),
                                                    ),
                                                    const SizedBox(width: 14),
                                                    const Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text('Newsletters', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                                                        Text('Add email newsletters to your feed', style: TextStyle(fontSize: 12, color: Color(0xFFFF6200))),
                                                      ],
                                                    ),
                                                    const Spacer(),
                                                    Container(
                                                      width: 30, height: 30,
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF8B2BE2).withValues(alpha: 0.25),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFFCC88FF), size: 22),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Builder(builder: (context) {
                                        final bool isActive = _isPremium || _isTrialActive;
                                        final String subtitle = isActive
                                            ? (_isPremium ? 'Active subscription' : 'Free trial active')
                                            : 'AI summaries for every article';
                                        return Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(14),
                                    
                                          ),
                                          child: Material(
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(14),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(14),
                                            onTap: () => _showSubscriptionManagement(context, isActive),
                                            child: Ink(
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [Color(0xFF220E00), Color(0xFF130600)],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                borderRadius: BorderRadius.circular(14),
                                                border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.5), width: 1.0),
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: 40, height: 40,
                                                      decoration: BoxDecoration(
                                                        color: isActive
                                                            ? const Color(0xFFFF6200).withValues(alpha: 0.25)
                                                            : const Color(0xFFE8A000).withValues(alpha: 0.25),
                                                        borderRadius: BorderRadius.circular(10),
                                                      ),
                                                      child: Icon(
                                                        isActive ? Icons.workspace_premium_rounded : Icons.auto_awesome_rounded,
                                                        color: isActive ? const Color(0xFFFF6200) : const Color(0xFFFFCC44),
                                                        size: 22,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 14),
                                                    Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          isActive ? 'TruBrief Pro' : 'Upgrade to Pro',
                                                          style: const TextStyle(
                                                            fontSize: 16, fontWeight: FontWeight.w700,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                        Text(subtitle, style: TextStyle(fontSize: 12, color: isActive ? const Color(0xFFFF6200) : const Color(0xFFFFCC44))),
                                                      ],
                                                    ),
                                                    const Spacer(),
                                                    if (isActive)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFFF6200).withValues(alpha: 0.2),
                                                          borderRadius: BorderRadius.circular(20),
                                                          border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.8)),
                                                        ),
                                                        child: const Text('ACTIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFFFF6200), letterSpacing: 1.0)),
                                                      )
                                                    else
                                                      Container(
                                                        width: 28, height: 28,
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFE8A000).withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(7),
                                                        ),
                                                        child: const Icon(Icons.keyboard_arrow_right_rounded, color: Color(0xFFFFCC44), size: 20),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ));
                                      }),
                                      const SizedBox(height: 16),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const Divider(color: Colors.white10, height: 1),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                              child: GestureDetector(
                                onTap: _showFeedbackDialog,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF1A0A00), Color(0xFF120800)],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.3), width: 1.2),
                                    boxShadow: [BoxShadow(color: const Color(0xFFFF6200).withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4))],
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.send_rounded, color: Color(0xFFFF6200), size: 18),
                                      SizedBox(width: 10),
                                      Text('Send to Developer', style: TextStyle(color: Color(0xFFFF6200), fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.2)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              child: Column(
                                children: [
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 12,
                                    runSpacing: 0,
                                    children: [
                                                _buildLegalLink('Disclaimer',
                                                  'DISCLAIMER — TruBrief by Tru-Resolve LLC\n\n'
                                                  'TruBrief is a news aggregator that curates publicly available RSS feed content and provides AI-generated summaries for quick, informed reading.\n\n'
                                                  'CONTENT OWNERSHIP\n'
                                                  'All articles, images, and original content remain the exclusive property of their respective publishers and journalists. Tru-Resolve LLC does not claim ownership of any news content. Full credit and attribution belong to the original creators. We display brief summaries only; full articles open directly on the publisher\'s website.\n\n'
                                                  'AI-GENERATED SUMMARIES\n'
                                                  'Article summaries in TruBrief are generated by artificial intelligence. These summaries may contain errors, omissions, or inaccuracies. They are provided for informational convenience only and do not constitute professional, legal, medical, financial, or any other form of advice. Always refer to the original article for complete and accurate information.\n\n'
                                                  'NO ENDORSEMENT\n'
                                                  'The inclusion of any news source or article does not imply endorsement by Tru-Resolve LLC. We are not responsible for the accuracy, legality, completeness, or content of any third-party source.\n\n'
                                                  'AS IS / NO WARRANTIES\n'
                                                  'TruBrief is provided "AS IS" and "AS AVAILABLE" without warranties of any kind, either express or implied, including but not limited to warranties of merchantability, fitness for a particular purpose, or non-infringement. We do not guarantee uninterrupted, error-free, or secure access to the service.\n\n'
                                                  'LIMITATION OF LIABILITY\n'
                                                  'To the fullest extent permitted by applicable law, Tru-Resolve LLC, its officers, directors, employees, and agents shall not be liable for any indirect, incidental, special, consequential, or punitive damages arising from your use of or inability to use TruBrief. Our total liability shall not exceed the greater of the amount you paid us in the preceding 12 months or \$50 USD.\n\n'
                                                  'AGE REQUIREMENT\n'
                                                  'TruBrief is intended for users 13 years of age or older. By using this app, you confirm that you are at least 13 years old. Users under 18 should have parental or guardian consent. We do not knowingly collect personal information from children under 13. If you believe a child under 13 has provided us with personal information, contact us at contact@tru-resolve.com and we will delete it promptly.\n\n'
                                                  'By continuing to use TruBrief, you agree to respect all copyrights, support the original publishers, and accept this disclaimer in full.'
                                                ),
                                                _buildLegalLink('Terms of Service',
                                                  'TERMS OF SERVICE — Tru-Resolve LLC\n'
                                                  'Effective Date: January 1, ${DateTime.now().year}\n\n'
                                                  '1. ACCEPTANCE OF TERMS\n'
                                                  'By downloading, installing, or using TruBrief, you agree to be bound by these Terms of Service ("Terms"). If you do not agree, do not use the app. We reserve the right to update these Terms at any time; continued use constitutes acceptance.\n\n'
                                                  '2. ELIGIBILITY\n'
                                                  'You must be at least 13 years old to use TruBrief. By using the app, you represent and warrant that you meet this age requirement. Users under 18 must have parental or guardian consent.\n\n'
                                                  '3. PERMITTED USE\n'
                                                  'TruBrief is licensed for personal, non-commercial use only. You may not: (a) scrape, copy, or redistribute content; (b) use automated systems to access the service; (c) reverse engineer or decompile the app; (d) use the app for unlawful purposes; or (e) circumvent any access controls or security features.\n\n'
                                                  '4. INTELLECTUAL PROPERTY\n'
                                                  'Tru-Resolve LLC owns all rights to the TruBrief app, its design, code, and branding. We do not claim ownership of third-party news content. All such content remains the property of its respective publishers.\n\n'
                                                  '5. THIRD-PARTY CONTENT\n'
                                                  'All news content is sourced from publicly available third-party RSS feeds. We do not endorse, verify, or take responsibility for any third-party content. Your access to third-party websites is governed by those sites\' own terms and privacy policies.\n\n'
                                                  '6. AI-GENERATED SUMMARIES\n'
                                                  'Article summaries are generated by AI and may contain inaccuracies. They are for informational purposes only and do not constitute professional advice of any kind.\n\n'
                                                  '7. IN-APP BROWSER & THIRD-PARTY LOGINS\n'
                                                  'When you use TruBrief\'s in-app browser to access news sources or log in to third-party accounts (e.g., NYT, WSJ), you are subject to those sites\' own terms of service and privacy policies. Tru-Resolve LLC is not responsible for the content, conduct, cookies, or data practices of any third-party site accessed through the app.\n\n'
                                                  '8. DISCLAIMER OF WARRANTIES\n'
                                                  'The service is provided "AS IS" and "AS AVAILABLE" without any warranties, express or implied. We do not warrant accuracy, completeness, availability, or fitness for a particular purpose.\n\n'
                                                  '9. LIMITATION OF LIABILITY\n'
                                                  'To the fullest extent permitted by law, Tru-Resolve LLC shall not be liable for any indirect, incidental, special, consequential, or punitive damages. Our maximum liability shall not exceed \$50 USD or amounts paid by you in the prior 12 months.\n\n'
                                                  '10. INDEMNIFICATION\n'
                                                  'You agree to defend, indemnify, and hold harmless Tru-Resolve LLC and its officers, directors, employees, and agents from any claims, liabilities, damages, or expenses (including attorneys\' fees) arising from: (a) your use of the app; (b) your violation of these Terms; or (c) your violation of any third-party rights.\n\n'
                                                  '11. DISPUTE RESOLUTION & ARBITRATION\n'
                                                  'Any dispute arising from these Terms or your use of TruBrief shall be resolved by binding individual arbitration under the rules of the American Arbitration Association (AAA), not in court. YOU WAIVE YOUR RIGHT TO A JURY TRIAL AND TO PARTICIPATE IN CLASS ACTION LAWSUITS. You may opt out of arbitration within 30 days of first use by emailing contact@tru-resolve.com with "Arbitration Opt-Out" in the subject line.\n\n'
                                                  '12. CLASS ACTION WAIVER\n'
                                                  'You may only bring claims against Tru-Resolve LLC in your individual capacity. You may not bring or participate in any class, collective, or representative action or proceeding.\n\n'
                                                  '13. TERMINATION\n'
                                                  'We reserve the right to suspend or terminate your access to TruBrief at any time, for any reason, without notice, including for violation of these Terms. We also reserve the right to modify, suspend, or discontinue the service at any time.\n\n'
                                                  '14. REPEAT INFRINGER POLICY\n'
                                                  'We reserve the right to terminate accounts of users who are found to repeatedly infringe third-party intellectual property rights.\n\n'
                                                  '15. GOVERNING LAW\n'
                                                  'These Terms are governed by the laws of the State of Florida, United States, without regard to conflict of law principles. Any disputes not subject to arbitration shall be brought exclusively in the state or federal courts located in Florida.\n\n'
                                                  'Contact: contact@tru-resolve.com'
                                                ),
                                                _buildLegalLink('Privacy Policy',
                                                  'PRIVACY POLICY — Tru-Resolve LLC\n'
                                                  'Last Updated: January 1, ${DateTime.now().year}\n\n'
                                                  'This Privacy Policy explains how Tru-Resolve LLC ("we," "us," or "our") collects, uses, and protects your information when you use TruBrief.\n\n'
                                                  '1. INFORMATION WE COLLECT\n'
                                                  'We collect only what is necessary to operate TruBrief:\n'
                                                  '• Account data: email address and authentication credentials (if you sign in)\n'
                                                  '• Preferences: your selected news categories and sources\n'
                                                  '• Saved articles: articles you bookmark within the app\n'
                                                  '• Location data: zip code or city (only if you enable Local Brief and grant permission)\n\n'
                                                  '2. INFORMATION WE DO NOT COLLECT\n'
                                                  'We do not collect: contacts, precise GPS location, payment information, browsing history outside the app, device identifiers for advertising, or any data we do not need to operate the service.\n\n'
                                                  '3. HOW WE USE YOUR DATA\n'
                                                  'Your data is used solely to: provide and personalize the TruBrief experience, maintain your preferences across sessions, and improve the app. We do not sell, rent, or share your personal data with third parties for marketing purposes.\n\n'
                                                  '4. CHILDREN\'S PRIVACY (COPPA COMPLIANCE)\n'
                                                  'TruBrief is not directed to children under 13. We do not knowingly collect personal information from children under 13. If we become aware that a child under 13 has provided personal information, we will delete it immediately. Parents or guardians who believe their child has submitted information may contact us at contact@tru-resolve.com.\n\n'
                                                  '5. IN-APP BROWSER & THIRD-PARTY COOKIES\n'
                                                  'When you access news sources or log in to third-party accounts through TruBrief\'s in-app browser, those sites may set cookies or collect data independently. We have no access to or control over third-party cookies or their data practices. Please review each source\'s privacy policy separately.\n\n'
                                                  '6. THIRD-PARTY SERVICES\n'
                                                  'We use Supabase to store account and preference data securely. Supabase\'s privacy practices are described at supabase.com/privacy.\n\n'
                                                  '7. DATA RETENTION\n'
                                                  'We retain your data for as long as your account is active. You may request deletion of your account and associated data at any time by contacting contact@tru-resolve.com.\n\n'
                                                  '8. SECURITY\n'
                                                  'We implement industry-standard security measures including encrypted data transmission (TLS) and secure cloud storage. However, no method of internet transmission is 100% secure, and we cannot guarantee absolute security.\n\n'
                                                  '9. YOUR RIGHTS\n'
                                                  'Depending on your location, you may have rights including:\n'
                                                  '• Access: request a copy of data we hold about you\n'
                                                  '• Correction: request correction of inaccurate data\n'
                                                  '• Deletion: request deletion of your data ("Right to be Forgotten")\n'
                                                  '• Opt-out: opt out of any data sharing\n'
                                                  'To exercise any right, contact: contact@tru-resolve.com\n\n'
                                                  '10. CALIFORNIA RESIDENTS (CCPA)\n'
                                                  'California residents have the right to know what personal information is collected, to opt out of the sale of personal information (we do not sell your data), and to request deletion. To submit a request, email contact@tru-resolve.com with "CCPA Request" in the subject.\n\n'
                                                  '11. EUROPEAN USERS (GDPR)\n'
                                                  'If you are in the European Economic Area, our legal basis for processing your data is: (a) your consent, and (b) legitimate interest in providing the service. You have the right to lodge a complaint with your local data protection authority.\n\n'
                                                  '12. CHANGES TO THIS POLICY\n'
                                                  'We may update this Privacy Policy periodically. We will notify you of material changes through the app. Your continued use of TruBrief after changes constitutes acceptance.\n\n'
                                                  'Contact: contact@tru-resolve.com'
                                                ),
                                                _buildLegalLink('DMCA / Copyright',
                                                  'DMCA & COPYRIGHT POLICY — Tru-Resolve LLC\n\n'
                                                  'OVERVIEW\n'
                                                  'TruBrief aggregates publicly available RSS feed content that publishers make available for distribution. We display AI-generated summaries only; all full articles open directly on the original publisher\'s website. We respect intellectual property rights and comply fully with the Digital Millennium Copyright Act (17 U.S.C. § 512).\n\n'
                                                  'DMCA SAFE HARBOR\n'
                                                  'Tru-Resolve LLC qualifies for DMCA safe harbor protection as a service provider under 17 U.S.C. § 512(c). We have designated a Copyright Agent to receive infringement notices.\n\n'
                                                  'TO FILE A TAKEDOWN NOTICE\n'
                                                  'If you believe content in TruBrief infringes your copyright, please send a written notice to our Copyright Agent at:\n\n'
                                                  'Copyright Agent — Tru-Resolve LLC\n'
                                                  'Email: contact@tru-resolve.com\n'
                                                  'Subject: DMCA Takedown Notice\n\n'
                                                  'Your notice must include ALL of the following:\n'
                                                  '• Your full legal name and contact information (address, phone, email)\n'
                                                  '• Identification of the copyrighted work you claim has been infringed\n'
                                                  '• Identification of the specific content in TruBrief you believe infringes (including URL or description)\n'
                                                  '• A statement that you have a good faith belief that the use is not authorized by the copyright owner, its agent, or the law\n'
                                                  '• A statement, made under penalty of perjury, that the information in your notice is accurate and that you are the copyright owner or authorized to act on their behalf\n'
                                                  '• Your physical or electronic signature\n\n'
                                                  'REPEAT INFRINGER POLICY\n'
                                                  'In accordance with 17 U.S.C. § 512(i), we maintain a policy of terminating, in appropriate circumstances, users who are repeat infringers of intellectual property rights.\n\n'
                                                  'COUNTER-NOTIFICATION\n'
                                                  'If you believe content was removed in error, you may submit a counter-notification to contact@tru-resolve.com including: your name and contact info, identification of the removed content, a statement under penalty of perjury that the content was removed by mistake, and your consent to jurisdiction of the Federal District Court for Florida.\n\n'
                                                  'We will process all valid notices promptly in accordance with applicable law.'
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                  Text(
                                    'Version $_kAppVersion',
                                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '© ${DateTime.now().year} Tru-Resolve LLC',
                                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      widget.onRestartTutorial?.call();
                                    },
                                    child: const Text(
                                      'Restart Tutorial',
                                      style: TextStyle(
                                        color: Color(0xFFFF6200),
                                        fontSize: 13,
                                        decoration: TextDecoration.underline,
                                        decorationColor: Color(0xFFFF6200),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
    );
    if (_tutorialStep != null) {
      return Stack(
        children: [
          scaffold,
          Positioned.fill(child: _buildSettingsTutorialOverlay()),
        ],
      );
    }
    return scaffold;
  }

  Widget _buildLegalLink(String title, String content) {
    return TextButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LegalContentScreen(title: title, content: content),
          ),
        );
      },
      style: TextButton.styleFrom(
        foregroundColor: Colors.white60,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          decoration: TextDecoration.underline,
          decorationColor: Colors.white38,
          decorationThickness: 1,
          height: 1.8,
        ),
      ),
    );
  }

  String _getSourceHomepage(dynamic src) {
    final rssUrl = src['url']?.toString() ?? '';
    try {
      final uri = Uri.parse(rssUrl);
      String host = uri.host;
      const hostRemap = {
        'feeds.a.dj.com': 'www.wsj.com',
        'feeds.bloomberg.com': 'www.bloomberg.com',
        'feeds.apnews.com': 'apnews.com',
        'feeds.washingtonpost.com': 'www.washingtonpost.com',
        'feeds.npr.org': 'www.npr.org',
        'rss.nytimes.com': 'www.nytimes.com',
        'rss.cnn.com': 'www.cnn.com',
        'feeds.bbci.co.uk': 'www.bbc.co.uk',
        'newsnetwork.mayoclinic.org': 'www.mayoclinic.org',
        'rssfeeds.webmd.com': 'www.webmd.com',
      };
      host = hostRemap[host] ?? host.replaceFirst(RegExp(r'^(feeds?\d*|rss)\.'), 'www.');
      return 'https://$host';
    } catch (_) {
      return rssUrl;
    }
  }

  Future<void> _showAddCustomSourceSheet() async {
    final urlCtrl = TextEditingController();
    String detectedName = '';
    bool isValidating = false;
    bool isValid = false;
    String? errorMsg;
    final Set<String> selectedCats = {};
    final allCats = _categories.where((c) => !_virtualCategories.contains(c)).toList()..sort();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> validate() async {
            final url = urlCtrl.text.trim();
            if (url.isEmpty) return;
            setSheet(() { isValidating = true; errorMsg = null; isValid = false; detectedName = ''; });
            try {
              final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
              final resp = await http.get(uri, headers: {'User-Agent': 'TruBrief/1.0'}).timeout(const Duration(seconds: 10));
              final body = resp.body;
              final isRss = body.contains('<rss') || body.contains('<feed') || body.contains('<channel>');
              if (!isRss) {
                setSheet(() { isValidating = false; isValid = false; errorMsg = 'This URL doesn\'t appear to be a valid RSS/Atom feed.'; });
                return;
              }
              final titleMatch = RegExp(r'<title[^>]*>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</title>', dotAll: true).firstMatch(body);
              String name = titleMatch?.group(1)?.trim() ?? '';
              name = name.replaceAll(RegExp(r'<[^>]+>'), '').trim();
              if (name.isEmpty) name = uri.host.replaceFirst(RegExp(r'^www\.'), '');
              setSheet(() { isValidating = false; isValid = true; detectedName = name; });
            } catch (e) {
              setSheet(() { isValidating = false; isValid = false; errorMsg = 'Could not reach this URL. Check the address and try again.'; });
            }
          }

          Future<void> save() async {
            if (!isValid || selectedCats.isEmpty) return;
            final uid = _effectiveUserId;
            if (uid == null) return;
            final url = urlCtrl.text.trim();
            final normalizedUrl = url.startsWith('http') ? url : 'https://$url';
            try {
              final row = await Supabase.instance.client
                  .from('trl_user_custom_sources')
                  .insert({
                    'user_id': uid,
                    'name': detectedName,
                    'url': normalizedUrl,
                    'categories': selectedCats.toList(),
                  })
                  .select()
                  .single();
              if (mounted) {
                setState(() => _customSources.add(Map<String, dynamic>.from(row)));
                Navigator.pop(ctx);
              }
            } catch (e) {
              setSheet(() => errorMsg = 'Failed to save. Please try again.');
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 18),
                  const Text('Add Custom Source', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('Paste an RSS or Atom feed URL', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isValid ? const Color(0xFFFF6200).withValues(alpha: 0.5) : Colors.white12),
                          ),
                          child: TextField(
                            controller: urlCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            onChanged: (_) => setSheet(() { isValid = false; detectedName = ''; errorMsg = null; }),
                            decoration: const InputDecoration(
                              hintText: 'https://example.com/rss',
                              hintStyle: TextStyle(color: Colors.white24, fontSize: 14),
                              prefixIcon: Icon(Icons.rss_feed, color: Colors.white38, size: 18),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: isValidating ? null : validate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6200),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: isValidating
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Check', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(errorMsg!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ],
                  if (isValid) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6200).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Color(0xFFFF6200), size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Detected: $detectedName', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (isValid) ...[
                    const Text('Add to categories', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    ...allCats.map((cat) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: selectedCats.contains(cat),
                      activeColor: const Color(0xFFFF6200),
                      title: Text(cat, style: const TextStyle(color: Colors.white, fontSize: 14)),
                      onChanged: (v) => setSheet(() {
                        if (v == true) selectedCats.add(cat); else selectedCats.remove(cat);
                      }),
                    )),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: selectedCats.isEmpty ? null : save,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: selectedCats.isEmpty
                              ? null
                              : const LinearGradient(colors: [Color(0xFFFF6200), Color(0xFFFF8C42)], begin: Alignment.centerLeft, end: Alignment.centerRight),
                          color: selectedCats.isEmpty ? Colors.white12 : null,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          selectedCats.isEmpty ? 'Select at least one category' : 'Add Source',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: selectedCats.isEmpty ? Colors.white30 : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openSourceLogin(dynamic src) {
    final homepage = _getSourceHomepage(src);
    final name = src['name']?.toString() ?? 'this source';
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: const Color(0xFFFF6200).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.lock_open_rounded, color: Color(0xFFFF6200), size: 26),
            ),
            const SizedBox(height: 14),
            Text('Sign in to $name', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 8),
            Text(
              '$name requires an account to access full articles. Open their website to sign in — your session will carry over when reading articles in the app.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                launchUrl(Uri.parse(homepage), mode: LaunchMode.externalApplication);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Open $name Website', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'After signing in, return to TruBrief to access your content.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white24, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: const Text('Not now', style: TextStyle(color: Colors.white38, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceTile(dynamic src, {bool isSubscription = false}) {
    final isSelected = _selectedSources.contains(src['id'].toString());
    return CheckboxListTile(
      title: Text(src['name'], style: const TextStyle(fontSize: 14)),
      subtitle: Text(src['url'], style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
      value: isSelected,
      activeColor: const Color(0xFFFF6200),
      contentPadding: EdgeInsets.zero,
      dense: true,
      onChanged: (val) {
        setState(() {
          if (val == true) {
            _selectedSources.add(src['id'].toString());
            if (isSubscription) {
              _openSourceLogin(src);
            }
          } else {
            _selectedSources.remove(src['id'].toString());
          }
        });
        _savePreferences();
      },
    );
  }
}

class NewslettersScreen extends StatefulWidget {
  const NewslettersScreen({super.key});
  @override
  State<NewslettersScreen> createState() => _NewslettersScreenState();
}

class _NewslettersScreenState extends State<NewslettersScreen> {
  final List<Map<String, String>> _curated = [
    {'name': 'Morning Brew', 'desc': 'Business news in a witty, quick read', 'url': 'https://www.morningbrew.com/daily', 'icon': '☕'},
    {'name': 'TLDR', 'desc': 'Tech, science & coding headlines daily', 'url': 'https://tldr.tech', 'icon': '⚡'},
    {'name': 'The Hustle', 'desc': 'Business & tech stories that matter', 'url': 'https://thehustle.co', 'icon': '💼'},
    {'name': '1440 Daily Digest', 'desc': 'News without bias, 1440 minutes of day', 'url': 'https://join1440.com', 'icon': '📰'},
    {'name': 'Axios AM', 'desc': 'Smart brevity on top stories each morning', 'url': 'https://www.axios.com/newsletters/axios-am', 'icon': '🌅'},
    {'name': 'The Pour Over', 'desc': 'Christian perspective on world news', 'url': 'https://thepourover.org', 'icon': '✝️'},
    {'name': 'NextDraft', 'desc': "Dave Pell's daily take on the internet's best", 'url': 'https://nextdraft.com', 'icon': '🗞️'},
    {'name': 'Milk Road', 'desc': 'Crypto news made simple', 'url': 'https://www.milkroad.com', 'icon': '🥛'},
    {'name': 'Dense Discovery', 'desc': 'Design, tech & culture weekly', 'url': 'https://www.densediscovery.com', 'icon': '🎨'},
    {'name': 'Politico Playbook', 'desc': 'Inside Washington politics every morning', 'url': 'https://www.politico.com/playbook', 'icon': '🏛️'},
    {'name': 'The Rundown AI', 'desc': 'Daily AI news and tools digest', 'url': 'https://www.therundown.ai', 'icon': '🤖'},
    {'name': 'Finimize', 'desc': 'Finance news explained in plain English', 'url': 'https://www.finimize.com', 'icon': '📈'},
  ];

  List<Map<String, dynamic>> _myNewsletters = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMyNewsletters();
  }

  Future<void> _loadMyNewsletters() async {
    try {
      final data = await Supabase.instance.client
          .from('trl_sources')
          .select()
          .eq('is_custom', true);
      if (mounted) setState(() { _myNewsletters = List<Map<String, dynamic>>.from(data); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteNewsletter(String id) async {
    try {
      await Supabase.instance.client.from('trl_articles').delete().eq('source_id', id);
      await Supabase.instance.client.from('trl_sources').delete().eq('id', id);
      _loadMyNewsletters();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showAddSheet({String? prefillName, String? prefillUrl}) {
    final nameCtrl = TextEditingController(text: prefillName ?? '');
    final rssCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text(
              prefillName != null ? 'Set up $prefillName' : 'Add Newsletter',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.purpleAccent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _step('1', 'Open Kill the Newsletter, type a name, tap Create — you\'ll get an Email Address and Atom Feed URL'),
                  const SizedBox(height: 6),
                  _step('2', 'Use that Email Address to subscribe to the newsletter'),
                  const SizedBox(height: 6),
                  _step('3', 'Paste the Atom Feed URL into the field below and tap Add'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async => launchUrl(Uri.parse('https://kill-the-newsletter.com'), mode: LaunchMode.externalApplication),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.open_in_new, color: Colors.purpleAccent, size: 15),
                    SizedBox(width: 8),
                    Text('Open Kill the Newsletter', style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
              ),
            ),
            if (prefillUrl != null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async => launchUrl(Uri.parse(prefillUrl), mode: LaunchMode.externalApplication),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.open_in_new, color: Colors.white54, size: 15),
                      const SizedBox(width: 8),
                      Text('Go to ${prefillName ?? 'Newsletter'} to Subscribe', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Newsletter Name',
                labelStyle: const TextStyle(color: Colors.white38),
                filled: true, fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rssCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Atom Feed URL (from Kill the Newsletter)',
                labelStyle: const TextStyle(color: Colors.white38),
                filled: true, fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final rss = rssCtrl.text.trim();
                  if (name.isEmpty || rss.isEmpty) return;
                  Navigator.pop(ctx);
                  try {
                    await Supabase.instance.client.from('trl_sources').insert({
                      'name': name,
                      'url': rss,
                      'type': 'rss',
                      'category': 'Tru Brief',
                      'requires_subscription': false,
                      'is_preset': false,
                      'is_custom': true,
                    });
                    _loadMyNewsletters();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Newsletter added to Tru Brief!')));
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purpleAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Add to Tru Brief', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(String num, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20, height: 20,
          decoration: BoxDecoration(color: Colors.purpleAccent.withValues(alpha: 0.2), shape: BoxShape.circle),
          child: Center(child: Text(num, style: const TextStyle(color: Colors.purpleAccent, fontSize: 11, fontWeight: FontWeight.bold))),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: const Text('Newsletters', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6200)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // --- EXPLAINER ---
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [const Color(0xFF1A001A), const Color(0xFF0D0D1A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.mark_email_read_outlined, color: Colors.purpleAccent, size: 20),
                        const SizedBox(width: 8),
                        const Text('How it works', style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                      ]),
                      const SizedBox(height: 10),
                      const Text(
                        'Turn any email newsletter into feed articles — no email inbox needed. One-time setup per newsletter.',
                        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                      ),
                      const SizedBox(height: 12),
                      _step('1', 'Tap a newsletter below → Open Kill the Newsletter → type a name → tap Create'),
                      const SizedBox(height: 4),
                      _step('2', 'Use the Email Address they give you to subscribe to that newsletter'),
                      const SizedBox(height: 4),
                      _step('3', 'Paste the Atom Feed URL into TruBrief — done! Articles appear in your Tru Brief tab'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // --- MY NEWSLETTERS ---
                if (_myNewsletters.isNotEmpty) ...[
                  const Text('My Newsletters', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 10),
                  ..._myNewsletters.map((nl) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.purpleAccent, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(nl['name']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: const Color(0xFF1C1C1E),
                                title: const Text('Remove Newsletter', style: TextStyle(color: Colors.white)),
                                content: Text('Remove ${nl['name']} from your feed?', style: const TextStyle(color: Colors.white70)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: Colors.redAccent))),
                                ],
                              ),
                            );
                            if (confirm == true) _deleteNewsletter(nl['id'].toString());
                          },
                        ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 24),
                ],

                // --- POPULAR NEWSLETTERS ---
                const Text('Popular Newsletters', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                const Text('Tap anywhere on a newsletter to set it up', style: TextStyle(fontSize: 12, color: Colors.white38)),
                const SizedBox(height: 12),
                ..._curated.map((nl) {
                  final alreadyAdded = _myNewsletters.any((m) => m['name'] == nl['name']);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Material(
                        color: alreadyAdded ? const Color(0xFF1A0D1A) : const Color(0xFF1C1C1E),
                        child: InkWell(
                          onTap: alreadyAdded ? null : () => _showAddSheet(prefillName: nl['name'], prefillUrl: nl['url']),
                          splashColor: Colors.purpleAccent.withValues(alpha: 0.15),
                          highlightColor: Colors.purpleAccent.withValues(alpha: 0.08),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: alreadyAdded ? Colors.purpleAccent.withValues(alpha: 0.4) : Colors.white10),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            child: Row(
                              children: [
                                Text(nl['icon']!, style: const TextStyle(fontSize: 26)),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(nl['name']!, style: TextStyle(color: alreadyAdded ? Colors.purpleAccent : Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                                      const SizedBox(height: 3),
                                      Text(nl['desc']!, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                alreadyAdded
                                    ? const Icon(Icons.check_circle, color: Colors.purpleAccent, size: 20)
                                    : const Icon(Icons.chevron_right, color: Colors.white24, size: 22),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 24),

                // --- ADD CUSTOM ---
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _showAddSheet(),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add, color: Colors.white54, size: 18),
                            SizedBox(width: 8),
                            Text('Add Custom Newsletter', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

class CategoryDetailScreen extends StatefulWidget {
  final String category;
  final List<dynamic> sources;
  final List<String> selectedSources;
  final bool isInFeed;
  final bool isTabVisible;
  final void Function(List<String> newSources, bool inFeed, bool tabVisible) onChanged;

  const CategoryDetailScreen({
    super.key,
    required this.category,
    required this.sources,
    required this.selectedSources,
    required this.isInFeed,
    this.isTabVisible = true,
    required this.onChanged,
  });

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  late List<String> _selectedSources;
  late bool _isInFeed;
  late bool _isTabVisible;

  @override
  void initState() {
    super.initState();
    _selectedSources = List<String>.from(widget.selectedSources);
    _isInFeed = widget.isInFeed;
    _isTabVisible = widget.isTabVisible;
  }

  void _toggle(String id, bool val) {
    setState(() {
      if (val) {
        _selectedSources.add(id);
      } else {
        _selectedSources.remove(id);
      }
    });
    widget.onChanged(_selectedSources, _isInFeed, _isTabVisible);
  }

  String _getHomepage(dynamic src) {
    final rssUrl = src['url']?.toString() ?? '';
    try {
      final uri = Uri.parse(rssUrl);
      String host = uri.host;
      const hostRemap = {
        'feeds.a.dj.com': 'www.wsj.com',
        'feeds.bloomberg.com': 'www.bloomberg.com',
        'feeds.apnews.com': 'apnews.com',
        'feeds.washingtonpost.com': 'www.washingtonpost.com',
        'feeds.npr.org': 'www.npr.org',
        'rss.nytimes.com': 'www.nytimes.com',
        'rss.cnn.com': 'www.cnn.com',
        'feeds.bbci.co.uk': 'www.bbc.co.uk',
        'newsnetwork.mayoclinic.org': 'www.mayoclinic.org',
        'rssfeeds.webmd.com': 'www.webmd.com',
      };
      host = hostRemap[host] ?? host.replaceFirst(RegExp(r'^(feeds?\d*|rss)\.'), 'www.');
      return 'https://$host';
    } catch (_) {
      return rssUrl;
    }
  }

  void _showSignInSheet(dynamic src) {
    final name = src['name']?.toString() ?? 'this source';
    final homepage = _getHomepage(src);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: const Color(0xFFFF6200).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.lock_open_rounded, color: Color(0xFFFF6200), size: 26),
            ),
            const SizedBox(height: 14),
            Text('Sign in to $name', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 8),
            Text(
              '$name requires an account to access full articles. Open their website to sign in — your session will carry over when reading articles in the app.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                launchUrl(Uri.parse(homepage), mode: LaunchMode.externalApplication);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: const Color(0xFFFF6200), borderRadius: BorderRadius.circular(12)),
                child: Text('Open $name Website', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'After signing in, return to TruBrief to access your content.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white24, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: const Text('Not now', style: TextStyle(color: Colors.white38, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceTile(dynamic src) {
    final id = src['id'].toString();
    final isSelected = _selectedSources.contains(id);
    final isSub = src['requires_subscription'] == true;
    return CheckboxListTile(
      title: Text(src['name'] ?? '', style: const TextStyle(fontSize: 16)),
      subtitle: Text(src['url'] ?? '', style: const TextStyle(fontSize: 13, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
      value: isSelected,
      activeColor: const Color(0xFFFF6200),
      contentPadding: EdgeInsets.zero,
      dense: true,
      onChanged: (val) {
        _toggle(id, val == true);
        if (val == true && isSub) _showSignInSheet(src);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final freeSources = widget.sources.where((s) => s['requires_subscription'] != true).toList();
    final subSources = widget.sources.where((s) => s['requires_subscription'] == true).toList();
    final top3 = freeSources.take(3).toList();
    final moreFree = freeSources.skip(3).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.category),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _isInFeed ? const Color(0xFFFF6200).withValues(alpha: 0.5) : Colors.white10),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      _isInFeed ? Icons.rss_feed : Icons.rss_feed_outlined,
                      size: 18,
                      color: _isInFeed ? const Color(0xFFFF6200) : Colors.white24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Show in Feed', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                          Text('Include ${widget.category} sources in Tru Brief', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: _isInFeed,
                      activeThumbColor: const Color(0xFFFF6200),
                      activeTrackColor: const Color(0xFFFF6200).withValues(alpha: 0.3),
                      onChanged: (val) {
                        setState(() => _isInFeed = val);
                        widget.onChanged(_selectedSources, val, _isTabVisible);
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                const Divider(color: Colors.white10, height: 20),
                Row(
                  children: [
                    Icon(
                      _isTabVisible ? Icons.tab : Icons.tab_unselected,
                      size: 18,
                      color: _isTabVisible ? const Color(0xFFFF6200) : Colors.white24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Display Tab', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                          const Text('Show as a tab on the main screen', style: TextStyle(fontSize: 12, color: Colors.white54)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: _isTabVisible,
                      activeThumbColor: const Color(0xFFFF6200),
                      activeTrackColor: const Color(0xFFFF6200).withValues(alpha: 0.3),
                      onChanged: (val) {
                        setState(() => _isTabVisible = val);
                        widget.onChanged(_selectedSources, _isInFeed, val);
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (top3.isNotEmpty) ...[
            const Text('Top 3 News Sources', style: TextStyle(fontSize: 13, color: Color(0xFFFF6200), fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ...top3.map(_sourceTile),
          ],
          if (moreFree.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white10),
            const Text('More Sources', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 4),
            ...moreFree.map(_sourceTile),
          ],
          if (subSources.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white24),
            Row(
              children: const [
                Icon(Icons.lock_outline, size: 13, color: Colors.orange),
                SizedBox(width: 6),
                Text('Sources Require Account', style: TextStyle(fontSize: 13, color: Colors.orange)),
              ],
            ),
            const SizedBox(height: 4),
            ...subSources.map(_sourceTile),
          ],
          const SizedBox(height: 12),
          const Divider(color: Colors.white10),
          Row(
            children: const [
              Icon(Icons.person_outline, size: 12, color: Colors.white38),
              SizedBox(width: 4),
              Text('Have an account? Tap ', style: TextStyle(fontSize: 11, color: Colors.white38)),
              Icon(Icons.login, size: 12, color: Colors.white38),
              Text(' on any source to sign in', style: TextStyle(fontSize: 11, color: Colors.white38)),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// Full-screen in-app browser with AI summary overlay
class ArticleReaderScreen extends StatefulWidget {
  final String url;
  final String sourceName;
  final String? articleTitle;
  final String? aiSummary;
  final bool isSubscribed;
  final String? sourceLoginUrl;
  final bool initialIsSaved;
  final VoidCallback? onToggleSave;
  final String? articleId;
  final String? imageUrl;

  const ArticleReaderScreen({
    super.key,
    required this.url,
    required this.sourceName,
    this.articleTitle,
    this.aiSummary,
    this.isSubscribed = false,
    this.sourceLoginUrl,
    this.initialIsSaved = false,
    this.onToggleSave,
    this.articleId,
    this.imageUrl,
  });

  @override
  State<ArticleReaderScreen> createState() => _ArticleReaderScreenState();
}

class _ArticleReaderScreenState extends State<ArticleReaderScreen> {
  bool _isError = false;
  bool _isGeoRestricted = false;
  double _progress = 0;
  InAppWebViewController? _webViewController;
  bool _summaryExpanded = true;
  late bool _isSaved;
  bool _isFollowed = false;

  bool get _isSubscribed => widget.isSubscribed;
  bool get _hasSummary => widget.aiSummary != null && widget.aiSummary!.isNotEmpty;

  void _showSubscribeCta(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 22),
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: const Color(0xFFFF6200).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.auto_awesome, color: Color(0xFFFF6200), size: 26),
            ),
            const SizedBox(height: 14),
            const Text('TruBrief AI Summary', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 8),
            const Text(
              'Understand every article in seconds. TruBrief Pro generates concise, unbiased summaries so you always get the full story — fast.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFF6200), Color(0xFFFF8C42)], begin: Alignment.centerLeft, end: Alignment.centerRight),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: const Color(0xFFFF6200).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: const Text('Subscribe — Coming Soon', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.pop(sheetCtx),
              child: const Text('Not now', style: TextStyle(color: Colors.white38, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  String get _displaySummary => _hasSummary
      ? widget.aiSummary!
      : 'AI summary generation is being set up.\n\nOnce active, TruBrief will automatically generate a concise, unbiased summary of this article — pulling out the key facts, context, and takeaways so you can understand the full story in seconds.';

  @override
  void initState() {
    super.initState();
    _summaryExpanded = false;
    _isSaved = widget.initialIsSaved;
    _checkIfFollowed();
  }

  Future<void> _checkIfFollowed() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final articleId = widget.articleId ?? widget.url.hashCode.toString();
    try {
      final row = await Supabase.instance.client
          .from('trl_followed_stories')
          .select('article_id')
          .eq('user_id', userId)
          .eq('article_id', articleId)
          .maybeSingle();
      if (mounted && row != null) setState(() => _isFollowed = true);
    } catch (_) {}
  }

  Future<void> _shareArticle(BuildContext ctx) async {
    final title = widget.articleTitle?.isNotEmpty == true
        ? widget.articleTitle!
        : 'Check out this article from ${widget.sourceName}';

    const int cardW = 1080;
    const int imgH = 608;
    const double padding = 48.0;
    const double titleFontSize = 46.0;
    const double titleLineHeight = 1.3;
    const int titleMaxLines = 4;
    const double barH = 6.0;
    const double barW = 80.0;
    const double iconTargetH = 68.0;
    const double nameFontSize = 54.0;
    const double tagFontSize = 30.0;
    const double sectionGap = 32.0;

    const Color bgColor = Color(0xFF0D0D0D);
    const Color orange = Color(0xFFFF6200);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final fillPaint = Paint()..color = bgColor;

    canvas.drawRect(Rect.fromLTWH(0, 0, cardW.toDouble(), 9999), fillPaint);

    ui.Image? articleImg;
    if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      try {
        final resp = await http.get(Uri.parse(widget.imageUrl!)).timeout(const Duration(seconds: 10));
        final codec = await ui.instantiateImageCodec(resp.bodyBytes, targetWidth: cardW);
        final frame = await codec.getNextFrame();
        articleImg = frame.image;
      } catch (_) {}
    }

    double cursorY = 0;

    if (articleImg != null) {
      final iw = articleImg.width.toDouble();
      final ih = articleImg.height.toDouble();
      final dstAspect = cardW / imgH;
      final srcAspect = iw / ih;
      final Rect srcRect;
      if (srcAspect > dstAspect) {
        final newW = ih * dstAspect;
        srcRect = Rect.fromLTWH((iw - newW) / 2, 0, newW, ih);
      } else {
        final newH = iw / dstAspect;
        srcRect = Rect.fromLTWH(0, (ih - newH) / 2, iw, newH);
      }
      canvas.drawImageRect(articleImg, srcRect, Rect.fromLTWH(0, 0, cardW.toDouble(), imgH.toDouble()), Paint()..filterQuality = FilterQuality.high);

      final shader = ui.Gradient.linear(
        const Offset(0, imgH * 0.35),
        Offset(0, imgH.toDouble()),
        [const Color(0x000D0D0D), bgColor],
      );
      canvas.drawRect(Rect.fromLTWH(0, 0, cardW.toDouble(), imgH.toDouble()), Paint()..shader = shader);
      cursorY = imgH.toDouble();
    }

    cursorY += sectionGap;

    final titleParagraph = (ui.ParagraphBuilder(ui.ParagraphStyle(
      textDirection: ui.TextDirection.ltr,
      maxLines: titleMaxLines,
      ellipsis: '…',
    ))
          ..pushStyle(ui.TextStyle(
            color: Colors.white,
            fontSize: titleFontSize,
            fontWeight: ui.FontWeight.w700,
            height: titleLineHeight,
          ))
          ..addText(title))
        .build()
      ..layout(ui.ParagraphConstraints(width: cardW - padding * 2));
    canvas.drawParagraph(titleParagraph, Offset(padding, cursorY));
    cursorY += titleParagraph.height + sectionGap;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(padding, cursorY, barW, barH), const Radius.circular(3)),
      Paint()..color = orange,
    );
    cursorY += barH + sectionGap;

    ui.Image? logoIcon;
    try {
      final data = await rootBundle.load('assets/images/1024x1024.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetHeight: iconTargetH.toInt());
      final frame = await codec.getNextFrame();
      logoIcon = frame.image;
    } catch (_) {}

    double logoRowY = cursorY;
    double iconEndX = padding;

    if (logoIcon != null) {
      final iconW = logoIcon.width.toDouble();
      final iconH2 = logoIcon.height.toDouble();
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(padding, logoRowY, iconW, iconH2), const Radius.circular(12)),
        Paint()..color = const Color(0xFF000000),
      );
      canvas.drawImage(logoIcon, Offset(padding, logoRowY), Paint()..filterQuality = FilterQuality.high);
      iconEndX = padding + iconW + 20;
    }

    final nameParagraph = (ui.ParagraphBuilder(ui.ParagraphStyle(textDirection: ui.TextDirection.ltr, maxLines: 1))
          ..pushStyle(ui.TextStyle(color: Colors.white, fontSize: nameFontSize, fontWeight: ui.FontWeight.w900, letterSpacing: -1.0))
          ..addText('Tru')
          ..pushStyle(ui.TextStyle(color: orange, fontSize: nameFontSize, fontWeight: ui.FontWeight.w900, letterSpacing: -1.0))
          ..addText('Brief'))
        .build()
      ..layout(ui.ParagraphConstraints(width: cardW - iconEndX - padding));

    final iconH = logoIcon?.height.toDouble() ?? nameFontSize * 1.2;
    final nameY = logoRowY + (iconH - nameFontSize * 1.2) / 2;
    canvas.drawParagraph(nameParagraph, Offset(iconEndX, nameY));

    cursorY = logoRowY + iconH + 24;

    final tagParagraph = (ui.ParagraphBuilder(ui.ParagraphStyle(textDirection: ui.TextDirection.ltr, maxLines: 1))
          ..pushStyle(ui.TextStyle(color: const Color(0xFF888888), fontSize: tagFontSize))
          ..addText('Smart News Delivered · Download Free on Google Play & App Store'))
        .build()
      ..layout(ui.ParagraphConstraints(width: cardW - padding * 2));
    canvas.drawParagraph(tagParagraph, Offset(padding, cursorY));
    cursorY += tagParagraph.height + sectionGap;

    final totalH = cursorY.ceil();
    final picture = recorder.endRecording();
    final image = await picture.toImage(cardW, totalH);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) return;

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/trubrief_share_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(byteData.buffer.asUint8List());

    if (!ctx.mounted) return;
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      subject: title,
    ));
  }

  Future<void> _toggleFollow() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final articleId = widget.articleId ?? widget.url.hashCode.toString();
    setState(() => _isFollowed = !_isFollowed);
    try {
      if (_isFollowed) {
        await Supabase.instance.client.from('trl_followed_stories').upsert({
          'user_id': userId,
          'article_id': articleId,
          'title': widget.articleTitle ?? '',
          'url': widget.url,
          'source_name': widget.sourceName,
          'followed_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,article_id', ignoreDuplicates: true);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Following this story. You\'ll be notified of updates.'), backgroundColor: Color(0xFF1C1C1E), duration: Duration(seconds: 3)),
        );
      } else {
        await Supabase.instance.client.from('trl_followed_stories').delete()
            .eq('user_id', userId).eq('article_id', articleId);
      }
    } catch (e) {
      setState(() => _isFollowed = !_isFollowed);
      debugPrint('Follow error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Reading Article'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: Icon(
              _isFollowed ? Icons.notifications_active : Icons.notifications_none,
              color: _isFollowed ? const Color(0xFFFF6200) : Colors.white,
            ),
            tooltip: _isFollowed ? 'Following story' : 'Follow story',
            onPressed: _toggleFollow,
          ),
          if (widget.onToggleSave != null)
            IconButton(
              icon: Icon(
                _isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: _isSaved ? const Color(0xFFFF6200) : Colors.white,
              ),
              tooltip: _isSaved ? 'Remove bookmark' : 'Bookmark article',
              onPressed: () {
                setState(() => _isSaved = !_isSaved);
                widget.onToggleSave!();
              },
            ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Share article',
            onPressed: () => _shareArticle(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── TOP PANEL: collapsible AI summary (subscribers) OR subscribe bar ──
          if (_isSubscribed)
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── pill header (always visible) ──
                  GestureDetector(
                    onTap: () => setState(() => _summaryExpanded = !_summaryExpanded),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF161616),
                        border: Border(
                          bottom: BorderSide(
                            color: _summaryExpanded
                                ? const Color(0xFFFF6200).withValues(alpha: 0.25)
                                : Colors.white.withValues(alpha: 0.06),
                            width: 1,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 30, height: 30,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF6200), Color(0xFFFF8C42)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 15),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'TruBrief AI Summary',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const Spacer(),
                          AnimatedRotation(
                            turns: _summaryExpanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 300),
                            child: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFFFF6200), size: 22),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _summaryExpanded ? 'Collapse' : 'Expand',
                            style: const TextStyle(color: Color(0xFFFF6200), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ── expandable body ──
                  if (_summaryExpanded)
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: screenHeight * 0.5),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF111111),
                          border: Border(
                            bottom: BorderSide(color: const Color(0xFFFF6200).withValues(alpha: 0.2), width: 1),
                          ),
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!_hasSummary)
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF6200).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.3)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.construction_rounded, color: Color(0xFFFF6200), size: 11),
                                          SizedBox(width: 5),
                                          Text('Coming soon', style: TextStyle(color: Color(0xFFFF6200), fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              if (!_hasSummary) const SizedBox(height: 14),
                              Text(
                                _displaySummary,
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.7,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            // Non-subscriber: sleek subscribe bar
            GestureDetector(
              onTap: () => _showSubscribeCta(context),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF161616),
                  border: Border(
                    bottom: BorderSide(color: const Color(0xFFFF6200).withValues(alpha: 0.2), width: 1),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6200).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.auto_awesome, color: Color(0xFFFF6200), size: 15),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'TruBrief AI Summary',
                      style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFF6200), Color(0xFFFF8C42)]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Subscribe', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                    ),
                  ],
                ),
              ),
            ),

          // ── Always-visible WebView (article) below ──
          Expanded(
            child: SafeArea(
              top: false,
              child: Stack(
                children: [
                  InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                    initialSettings: InAppWebViewSettings(
                      isFraudulentWebsiteWarningEnabled: true,
                      safeBrowsingEnabled: true,
                      allowsBackForwardNavigationGestures: true,
                      contentBlockers: [
                        for (final domain in const [
                          'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
                          'adservice.google.com', 'pagead2.googlesyndication.com',
                          'amazon-adsystem.com', 'ads.twitter.com', 'ads.linkedin.com',
                          'outbrain.com', 'taboola.com', 'pubmatic.com', 'openx.net',
                          'rubiconproject.com', 'criteo.com', 'moatads.com', 'adtech.de',
                          'scorecardresearch.com', 'quantserve.com', 'casalemedia.com',
                          'adsymptotic.com', 'advertising.com', 'adnxs.com', 'ads.yahoo.com',
                          'media.net', 'adsafeprotected.com', 'sharethrough.com',
                          'smartadserver.com', 'sovrn.com', 'indexexchange.com',
                          'lijit.com', 'tidaltv.com', 'turn.com', 'tremorhub.com',
                          'spotxchange.com', 'springserve.com', 'contextweb.com',
                          'oath.com', 'yldbt.com', 'bidswitch.net', 'rlcdn.com',
                        ])
                          ContentBlocker(
                            trigger: ContentBlockerTrigger(urlFilter: '.*$domain.*'),
                            action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
                          ),
                      ],
                    ),
                    onWebViewCreated: (controller) => _webViewController = controller,
                    onProgressChanged: (controller, progress) {
                      if (mounted) setState(() => _progress = progress / 100);
                    },
                    onLoadStop: (controller, url) async {
                      const adCssJs = '''
                        (function() {
                          var style = document.createElement('style');
                          style.textContent = `
                            ins.adsbygoogle, [id*="google_ads"], [class*="google-ad"],
                            [class*="adsbygoogle"], [data-ad-unit], [data-ad-slot],
                            [class*=" ad-"], [class*="-ad "], [class*="-ads "],
                            [class*=" ads-"], [id*="-ad-"], [id*="_ad_"],
                            .advertisement, .sponsored, .sponsored-content,
                            [class*="sponsor"], [class*="outbrain"], [class*="taboola"],
                            [id*="outbrain"], [id*="taboola"], [class*="dfp-ad"],
                            [class*="prebid"], [class*="banner-ad"], [id*="banner-ad"],
                            iframe[src*="doubleclick"], iframe[src*="googlesyndication"],
                            iframe[src*="adnxs"], iframe[src*="taboola"],
                            iframe[src*="outbrain"] { display: none !important; }
                          `;
                          document.head.appendChild(style);
                        })();
                      ''';
                      const cleanupJs = '''
                        (function() {
                          document.documentElement.style.overflow = 'auto';
                          document.body.style.overflow = 'auto';
                          document.body.style.position = 'relative';
                          var els = document.querySelectorAll('*');
                          for (var i = 0; i < els.length; i++) {
                            var style = window.getComputedStyle(els[i]);
                            var zIndex = parseInt(style.zIndex);
                            if (
                              (style.position === 'fixed' || style.position === 'sticky') &&
                              zIndex > 1000 &&
                              (els[i].scrollHeight > window.innerHeight * 0.4 ||
                               els[i].offsetWidth > window.innerWidth * 0.8)
                            ) {
                              els[i].style.display = 'none';
                            }
                          }
                        })();
                      ''';
                      await controller.evaluateJavascript(source: adCssJs);
                      await controller.evaluateJavascript(source: cleanupJs);
                      const geoCheckJs = '''
                        (function() {
                          var t = (document.body && document.body.innerText || '').toLowerCase();
                          var phrases = [
                            'not available in your region','not available in your country',
                            'only available in the uk','not available outside','geo-restricted',
                            'geo restricted','available only in','not available where you are',
                            'content is not available in your location',
                            'this video is not available','iplayer isn',
                          ];
                          for (var p of phrases) { if (t.includes(p)) return true; }
                          return false;
                        })()
                      ''';
                      final isGeoBlocked = await controller.evaluateJavascript(source: geoCheckJs);
                      if (isGeoBlocked == true && mounted) {
                        setState(() { _isGeoRestricted = true; _isError = true; });
                        return;
                      }
                      await Future.delayed(const Duration(seconds: 2));
                      if (mounted) {
                        await controller.evaluateJavascript(source: adCssJs);
                        await controller.evaluateJavascript(source: cleanupJs);
                      }
                      await Future.delayed(const Duration(seconds: 3));
                      if (mounted) await controller.evaluateJavascript(source: cleanupJs);
                    },
                    onLoadError: (controller, url, code, message) {
                      if (code == -999) return;
                      if (mounted) setState(() => _isError = true);
                    },
                    onLoadHttpError: (controller, url, statusCode, description) {
                      if (statusCode == 404 || statusCode >= 500) {
                        if (mounted) setState(() => _isError = true);
                      }
                    },
                  ),
                  if (_isError)
                    Container(
                      color: Colors.black,
                      width: double.infinity,
                      height: double.infinity,
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isGeoRestricted ? Icons.location_off : Icons.error_outline,
                            size: 64,
                            color: const Color(0xFFFF6200),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _isGeoRestricted ? 'Not Available in Your Region' : 'Article Unavailable',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isGeoRestricted
                                ? 'This content from ${widget.sourceName} is restricted to certain regions and cannot be viewed from your location.'
                                : widget.sourceLoginUrl != null
                                    ? 'This article may require a ${widget.sourceName} account to view.'
                                    : '${widget.sourceName} has removed this article or changed its location, and it is no longer accessible.',
                            style: const TextStyle(fontSize: 16, color: Colors.grey, height: 1.5),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          if (!_isGeoRestricted && widget.sourceLoginUrl != null)
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() => _isError = false);
                                _webViewController?.loadUrl(
                                  urlRequest: URLRequest(url: WebUri(widget.sourceLoginUrl!)),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF6200),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                              icon: const Icon(Icons.login, size: 18),
                              label: Text('Log In to ${widget.sourceName}'),
                            ),
                          if (!_isGeoRestricted && widget.sourceLoginUrl != null)
                            const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white12,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            ),
                            child: const Text('Go Back'),
                          ),
                        ],
                      ),
                    ),
                  if (_progress < 1.0 && !_isError)
                    LinearProgressIndicator(
                      value: _progress,
                      color: const Color(0xFFFF6200),
                      backgroundColor: Colors.transparent,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SavedArticlesScreen extends StatefulWidget {
  final bool isSubscribed;
  const SavedArticlesScreen({super.key, this.isSubscribed = false});

  @override
  State<SavedArticlesScreen> createState() => _SavedArticlesScreenState();
}

class _SavedArticlesScreenState extends State<SavedArticlesScreen> {
  String? get _userId => Supabase.instance.client.auth.currentUser?.id;
  bool _loading = true;
  List<Map<String, dynamic>> _articles = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _cleanUrl(dynamic raw) {
    if (raw == null) return '';
    var s = raw.toString().trim();
    s = s.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '').trim();
    return s;
  }

  Future<void> _load() async {
    final uid = _userId;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final saved = await Supabase.instance.client
          .from('trl_saved_articles')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false);

      if (saved.isEmpty) { setState(() { _articles = []; _loading = false; }); return; }

      final metaArticles = saved.map<Map<String, dynamic>>((r) => {
        'id': r['article_id']?.toString() ?? '',
        'title': r['title']?.toString() ?? '',
        'url': _cleanUrl(r['url']),
        'source_name': r['source_name']?.toString() ?? 'TruBrief',
        'image_url': r['thumbnail_url']?.toString(),
        'created_at': r['created_at'],
        'summary_brief': null,
      }).toList();

      // Enrich with live article data (url, title, image, summary) if available
      try {
        final ids = metaArticles.map((a) => a['id'].toString()).where((id) => id.isNotEmpty).toList();
        if (ids.isNotEmpty) {
          final articleRows = await Supabase.instance.client
              .from('trl_articles')
              .select('id, title, original_url, image_url, summary_brief, source_name')
              .inFilter('id', ids);
          if (articleRows.isNotEmpty) {
            final byId = { for (var a in articleRows) a['id'].toString(): a };
            for (var i = 0; i < metaArticles.length; i++) {
              final full = byId[metaArticles[i]['id']];
              if (full != null) {
                final liveUrl = _cleanUrl(full['original_url']);
                metaArticles[i] = {
                  ...metaArticles[i],
                  'title': (full['title']?.toString().isNotEmpty == true) ? full['title'].toString() : metaArticles[i]['title'],
                  'url': liveUrl.isNotEmpty ? liveUrl : metaArticles[i]['url'],
                  'source_name': full['source_name']?.toString() ?? metaArticles[i]['source_name'],
                  'image_url': full['image_url']?.toString() ?? metaArticles[i]['image_url'],
                  'summary_brief': full['summary_brief']?.toString(),
                };
              }
            }
          }
        }
      } catch (_) {}

      if (mounted) setState(() { _articles = metaArticles; _loading = false; });
    } catch (e) {
      debugPrint('SavedArticlesScreen load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unsave(String articleId) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await Supabase.instance.client
          .from('trl_saved_articles')
          .delete()
          .eq('user_id', uid)
          .eq('article_id', articleId);
      if (mounted) setState(() => _articles.removeWhere((a) => a['id'].toString() == articleId));
    } catch (e) {
      debugPrint('Unsave error: $e');
    }
  }

  String _getTimeAgo(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) { return ''; }
  }

  void _openArticle(Map<String, dynamic> article) {
    final url = article['url']?.toString() ?? '';
    if (url.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ArticleReaderScreen(
        url: url,
        sourceName: article['source_name']?.toString() ?? 'TruBrief',
        articleTitle: article['title']?.toString() ?? '',
        aiSummary: article['summary_brief']?.toString(),
        isSubscribed: widget.isSubscribed,
        initialIsSaved: true,
        onToggleSave: () => _unsave(article['id'].toString()),
        articleId: article['id']?.toString(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Saved Articles'),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          if (_articles.isNotEmpty)
            TextButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1C1C1E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Text('Clear all saved?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    content: const Text('This will remove all saved articles.', style: TextStyle(color: Colors.white54, fontSize: 14)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Clear all', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                );
                if (confirm != true || !mounted) return;
                final uid = _userId;
                if (uid == null) return;
                try {
                  await Supabase.instance.client
                      .from('trl_saved_articles')
                      .delete()
                      .eq('user_id', uid);
                  if (mounted) setState(() => _articles = []);
                } catch (_) {}
              },
              child: const Text('Clear all', style: TextStyle(color: Colors.white38, fontSize: 13)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6200)))
          : _articles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bookmark_border_rounded, size: 64, color: Colors.white12),
                      const SizedBox(height: 20),
                      const Text('No saved articles yet', style: TextStyle(fontSize: 18, color: Colors.white38, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      const Text('Tap the bookmark icon on any article\nto save it here.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.white24, height: 1.5)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  itemCount: _articles.length,
                  itemBuilder: (ctx, i) {
                    final article = _articles[i];
                    final title = article['title']?.toString() ?? 'Untitled';
                    final source = article['source_name']?.toString() ?? '';
                    final time = _getTimeAgo(article['created_at']);
                    return Dismissible(
                      key: Key(article['id'].toString()),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 26),
                      ),
                      onDismissed: (_) => _unsave(article['id'].toString()),
                      child: GestureDetector(
                        onTap: () => _openArticle(article),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(source.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFFF6200), letterSpacing: 1.1)),
                                  const Spacer(),
                                  const Icon(Icons.access_time, size: 12, color: Colors.white30),
                                  const SizedBox(width: 4),
                                  Text(time, style: const TextStyle(fontSize: 11, color: Colors.white30)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white, height: 1.3), maxLines: 3, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Spacer(),
                                  GestureDetector(
                                    onTap: () => _unsave(article['id'].toString()),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.bookmark_remove_outlined, size: 15, color: Colors.white30),
                                        const SizedBox(width: 4),
                                        const Text('Remove', style: TextStyle(fontSize: 11, color: Colors.white30)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class LegalContentScreen extends StatelessWidget {
  final String title;
  final String content;

  const LegalContentScreen({
    super.key,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFFFF6200),
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white10),
            const SizedBox(height: 16),
            Text(
              content,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.6,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 64),
            const Center(
              child: Opacity(
                opacity: 0.2,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Tru', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      TextSpan(
                        text: 'Brief',
                        style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFFF6200), fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Professional News Curation',
                style: TextStyle(color: Colors.white10, fontSize: 10, fontStyle: FontStyle.italic),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? highlightRect;
  final double pulse;
  _SpotlightPainter({this.highlightRect, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 10.0;
    const r = 16.0;
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.clipRect(fullRect);

    if (highlightRect == null) {
      canvas.drawRect(fullRect, Paint()..color = const Color(0xCC000000));
      return;
    }

    final inflated = highlightRect!.inflate(pad);
    final rrect = RRect.fromRectAndRadius(inflated, const Radius.circular(r));

    final path = Path()
      ..addRect(fullRect)
      ..addRRect(rrect);
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = const Color(0xCC000000));

    final glowAlpha = (0.5 + 0.5 * pulse).clamp(0.0, 1.0);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Color.fromRGBO(255, 98, 0, glowAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 + pulse * 1.5
        ..maskFilter = MaskFilter.blur(BlurStyle.solid, 6 + pulse * 6),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFFFF6200)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.pulse != pulse || old.highlightRect != highlightRect;
}

class TruFlashSettingsScreen extends StatefulWidget {
  const TruFlashSettingsScreen({super.key});

  @override
  State<TruFlashSettingsScreen> createState() => _TruFlashSettingsScreenState();
}

class _TruFlashSettingsScreenState extends State<TruFlashSettingsScreen> {
  static const List<Map<String, String>> _sources = [
    {'name': 'Fox News', 'url': 'https://feeds.foxnews.com/foxnews/latest'},
    {'name': 'CNN', 'url': 'https://rss.cnn.com/rss/edition.rss'},
    {'name': 'NBC News', 'url': 'https://feeds.nbcnews.com/nbcnews/public/news'},
    {'name': 'Politico', 'url': 'https://rss.politico.com/politics-news.xml'},
    {'name': 'ABC News', 'url': 'https://feeds.abcnews.com/abcnews/topstories'},
    {'name': 'CBS News', 'url': 'https://feeds.cbsnews.com/cbsnews/rss/latest'},
    {'name': 'NPR', 'url': 'https://feeds.npr.org/1001/rss.xml'},
    {'name': 'Reuters', 'url': 'https://feeds.reuters.com/reuters/topNews'},
    {'name': 'The Hill', 'url': 'https://thehill.com/rss/syndicator/19110'},
    {'name': 'DW News', 'url': 'https://rss.dw.com/rdf/rss-en-top'},
  ];

  List<String> _enabled = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('flash_enabled_sources');
    if (mounted) {
      setState(() {
        _enabled = saved ?? _sources.map((s) => s['name']!).toList();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('flash_enabled_sources', _enabled);
  }

  void _toggle(String name) {
    setState(() {
      if (_enabled.contains(name)) {
        if (_enabled.length > 1) _enabled.remove(name);
      } else {
        _enabled.add(name);
      }
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Tru Flash Sources', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6200)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Choose which sources appear in the Tru Flash tab. At least one source must be enabled.',
                    style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
                  ),
                ),
                ..._sources.map((source) {
                  final name = source['name']!;
                  final isEnabled = _enabled.contains(name);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isEnabled ? const Color(0xFFFF6200).withValues(alpha: 0.5) : Colors.white12,
                        width: 1.2,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _toggle(name),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: isEnabled
                                    ? const Color(0xFFFF6200).withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.bolt_rounded,
                                color: isEnabled ? const Color(0xFFFF6200) : Colors.white38,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                            ),
                            Switch(
                              value: isEnabled,
                              onChanged: (_) => _toggle(name),
                              activeThumbColor: const Color(0xFFFF6200),
                              activeTrackColor: const Color(0xFFFF6200).withValues(alpha: 0.3),
                              inactiveThumbColor: Colors.white38,
                              inactiveTrackColor: Colors.white12,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
