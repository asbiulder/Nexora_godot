// Keep only intro1.mp4: the spaceship flight through the portal to the NEXORA logo.
// Once it ends, the app hands off to the account/guest welcome screen. Skip appears after ~1 second.
// If playback fails or stalls, hand off to the welcome screen instead of showing another intro.
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../core/sound.dart';

class VideoIntro extends StatefulWidget {
  final VoidCallback onDone, onFail;
  const VideoIntro({super.key, required this.onDone, required this.onFail});
  static const asset = 'assets/video/intro1.mp4';

  @override
  State<VideoIntro> createState() => _VideoIntroState();
}

class _VideoIntroState extends State<VideoIntro> {
  late final VideoPlayerController _controller = VideoPlayerController.asset(VideoIntro.asset);
  bool _ready = false, _skip = false, _done = false;
  Timer? _skipTimer, _guardTimer;

  @override
  void initState() {
    super.initState();
    Sound.scene(AudioScene.match);
    _controller.addListener(_watch);
    _skipTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _skip = true);
    });
    _guardTimer = Timer(const Duration(seconds: 6), () {
      if (!_ready) _fail();
    });
    unawaited(_initializeAndPlay());
  }

  Future<void> _initializeAndPlay() async {
    try {
      await _controller.initialize();
      await _controller.setLooping(false);
      if (!mounted || _done) return;
      setState(() => _ready = true);
      await _controller.play();
    } catch (_) {
      _fail();
    }
  }

  void _watch() {
    if (_done) return;
    final value = _controller.value;
    if (value.hasError) return _fail();
    final atEnd = value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= value.duration - const Duration(milliseconds: 40) &&
        !value.isPlaying;
    if (atEnd) _finish();
  }

  void _fail() {
    if (_done || !mounted) return;
    _done = true;
    Sound.scene(AudioScene.menu);
    widget.onFail();
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    if (_ready) unawaited(_controller.pause());
    Sound.scene(AudioScene.menu);
    widget.onDone();
  }

  @override
  void dispose() {
    _skipTimer?.cancel();
    _guardTimer?.cancel();
    _controller.removeListener(_watch);
    _controller.dispose();
    super.dispose();
  }

  Widget _video() {
    if (!_ready) return const SizedBox.shrink();
    final size = _controller.value.size;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.center,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(_controller)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        _video(),
        Positioned(
          top: pad.top + 12,
          left: 14,
          child: AnimatedOpacity(
            opacity: _skip ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !_skip,
              child: GestureDetector(
                onTap: _finish,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0x8c000000),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0x66ffffff)),
                  ),
                  child: const Text(
                    'رد کردن  ›',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(color: Colors.white, fontFamily: 'Vazirmatn', fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
