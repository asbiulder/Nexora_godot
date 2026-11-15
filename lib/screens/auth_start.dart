import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../net/auth.dart';
import '../ui/kit.dart';
import 'settings.dart' show AccountPanel;

class AuthStartScreen extends StatefulWidget {
  final VoidCallback onContinue;
  const AuthStartScreen({super.key, required this.onContinue});

  @override
  State<AuthStartScreen> createState() => _AuthStartScreenState();
}

class _AuthStartScreenState extends State<AuthStartScreen> {
  bool _complete = false;

  @override
  void initState() {
    super.initState();
    Auth.i.addListener(_authChanged);
  }

  void _authChanged() {
    if (Auth.i.uid != null && !_complete && mounted) setState(() => _complete = true);
  }

  @override
  void dispose() {
    Auth.i.removeListener(_authChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [
        const Positioned.fill(child: Space(theme: SpaceTheme.base, dim: .16)),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(18, 16, 18, pad.bottom + 22),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: .94, end: 1),
                  duration: const Duration(milliseconds: 620),
                  curve: Curves.easeOutCubic,
                  builder: (_, value, child) => Opacity(
                    opacity: value.clamp(0.0, 1.0).toDouble(),
                    child: Transform.translate(offset: Offset(0, (1 - value) * 20), child: Transform.scale(scale: value, child: child)),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 360),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _complete ? _welcomeBack(key: const ValueKey('authenticated')) : _chooseAccount(key: const ValueKey('choose')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _chooseAccount({Key? key}) => Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 22),
          Center(
            child: Container(
              width: 94,
              height: 94,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(colors: [Color(0x553ff4ff), Color(0x183e50ff), Color(0x003e50ff)]),
                border: Border.all(color: C.cyan.withValues(alpha: .42)),
                boxShadow: [BoxShadow(color: C.cyan.withValues(alpha: .16), blurRadius: 30)],
              ),
              child: const Center(child: Img('assets/g/ui/logo_nexora.webp', w: 74, h: 74, fit: BoxFit.contain)),
            ),
          ),
          const SizedBox(height: 18),
          tTitle('به جهان نکسورا خوش آمدی', size: 25, align: TextAlign.center),
          const SizedBox(height: 7),
          const T('وارد شو یا حساب بساز؛ می‌توانی بدون ثبت‌نام هم به‌عنوان مهمان بازی کنی.', size: 13, color: C.dim, align: TextAlign.center, height: 1.7),
          const SizedBox(height: 22),
          AccountPanel(onAuthenticated: _markAuthenticated),
          const SizedBox(height: 2),
          TextButton.icon(
            onPressed: widget.onContinue,
            icon: const Icon(Icons.sports_esports_rounded, color: C.dim2, size: 19),
            label: const T('فعلاً بدون حساب ادامه بده', size: 12, color: C.dim2),
          ),
        ],
      );

  void _markAuthenticated() {
    if (mounted && !_complete) setState(() => _complete = true);
  }

  Widget _welcomeBack({Key? key}) => Column(
        key: key,
        children: [
          const SizedBox(height: 52),
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x183dffa8),
              border: Border.all(color: C.green.withValues(alpha: .65), width: 1.5),
              boxShadow: [BoxShadow(color: C.green.withValues(alpha: .22), blurRadius: 28)],
            ),
            child: const Icon(Icons.check_rounded, size: 58, color: C.green),
          ),
          const SizedBox(height: 20),
          tTitle('آماده‌ای، ${Auth.i.profile?.s('username') ?? 'قهرمان'}؟', size: 24, align: TextAlign.center),
          const SizedBox(height: 8),
          const T('حسابت آماده است. بزن بریم سراغ بازی.', size: 13, color: C.dim, align: TextAlign.center),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: Btn('ورود به نکسورا', colors: G.gold, onTap: widget.onContinue)),
          const SizedBox(height: 42),
        ],
      );
}
